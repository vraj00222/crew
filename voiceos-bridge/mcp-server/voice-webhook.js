#!/usr/bin/env node
// a1mobile voice webhook — the crew's way of phoning the user. Node stdlib, no deps.
//
//   node voice-webhook.js          serves :4003
//
// a1mobile runs the number's pointed webhook when an outbound call is answered
// (their trunk is sip.telnyx.com; the contract is Telnyx TeXML). Two kinds of
// call, queued by the bridge before it dials:
//
//   announce — POST /say {message}    the call speaks one message and hangs up.
//   ask      — POST /ask {question}   the call states the question, beeps,
//              listens to the answer, and the transcript comes back to whoever
//              is long-polling GET /answer. This is the "agents are stuck"
//              path: the agent's tool call waits, the user speaks, the agent
//              continues on what they actually said.
//
// What happens to the audio: Telnyx's `transcribe` attribute is NOT honoured
// through a1mobile (tested live 2026-08-09 — recordingStatusCallback fired,
// transcriptionCallback never did), so we transcribe the answer ourselves:
// OpenAI's transcription API when a key is around (repo-root .env or
// OPENAI_API_KEY — works on any machine, ~2s), local mlx-whisper via uvx when
// it is not. The recording is downloaded to the OS temp dir just long enough
// to transcribe and then DELETED, success or failure — the user's answer
// belongs to them; only the transcript text is kept (call-log.jsonl,
// gitignored). The call never claims to be recorded, because nothing is kept.
//
//   POST /voice          a1mobile calls this on answer -> TeXML
//   POST /record-done    after the answer -> TeXML sign-off
//   POST /recording-status  Telnyx: presigned recording URL (expires in 10 min)
//   GET  /answer?timeout=ms   long-poll for the transcript of the current ask
//   GET  /transcripts    every transcript heard so far, newest last
//   GET  /health         {ok, mode, message}
//
// One-time wiring (the tunnel is the only non-local piece — Telnyx must reach
// the callbacks, so localhost alone is not enough):
//
//   cloudflared tunnel --url http://localhost:4003     # or ngrok http 4003
//   node a1mobile.js point https://YOUR-TUNNEL/voice

const http = require('node:http');
const { spawn } = require('node:child_process');
const { appendFileSync, readFileSync, mkdtempSync, rm } = require('node:fs');
const { join } = require('node:path');
const { tmpdir } = require('node:os');

const PORT = Number(process.env.CREW_VOICE_PORT || 4003);
const LOG_PATH = process.env.CREW_CALL_LOG || join(__dirname, 'call-log.jsonl');
// How long the person gets to talk, in seconds. Short on purpose: this is one
// question and one answer, not an open line. Going quiet or hanging up ends it.
const RECORD_S = Number(process.env.CREW_RECORD_SECONDS || 60);
const WHISPER_MODEL = process.env.CREW_WHISPER_MODEL || 'mlx-community/whisper-large-v3-turbo';

// The one queued call. `mode` decides the TeXML: announce = say and hang up
// (nothing recorded at all); ask = say, beep, listen. One at a time on
// purpose — there is one phone and one voice channel, same as the dock.
const DEFAULT_MSG = process.env.CREW_CALL_DEFAULT || 'Hello from your crew. The job is done.';
let call = { mode: 'announce', message: DEFAULT_MSG, spoken: DEFAULT_MSG, audioId: null };
// The current ask's answer: null until the transcript lands. /answer polls it.
let answer = null;

function logEvent(event, data) {
  const line = JSON.stringify({ ts: new Date().toISOString(), event, ...data });
  try { appendFileSync(LOG_PATH, line + '\n'); } catch (e) { console.error(`log write failed: ${e.message}`); }
  return line;
}

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&apos;');

// Callback URLs must be absolute AND public — Telnyx calls them from outside.
// The webhook itself arrives through the tunnel, so its Host header is the one
// address we know the outside world can reach.
const base = (req) => {
  const host = req.headers.host || `localhost:${PORT}`;
  const proto = req.headers['x-forwarded-proto'] || (host.startsWith('localhost') ? 'http' : 'https');
  return `${proto}://${host}`;
};

// Play the synthesised line when we have one, fall back to robotic <Say>.
const speech = (req, text, audioId) =>
  audioId && ttsById.has(audioId)
    ? `<Play>${base(req)}/audio/${audioId}.mp3</Play>`
    : `<Say>${esc(text)}</Say>`;

// The leading pause is answer-to-ear time: TeXML starts executing the moment
// the call connects, which is a beat before a human has the phone at their
// ear — a live test at length="1" lost half the intro. Do not trim it back.
const answerTexml = (req) => call.mode === 'ask'
  ? `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Pause length="2"/>
  ${speech(req, call.spoken, call.audioId)}
  <Record maxLength="${RECORD_S}" playBeep="true" trim="trim-silence"
          timeout="3" finishOnKey="#"
          action="${base(req)}/record-done"
          recordingStatusCallback="${base(req)}/recording-status"/>
  <Say>Goodbye.</Say>
  <Hangup/>
</Response>`
  : `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Pause length="2"/>
  ${speech(req, call.spoken, call.audioId)}
  <Hangup/>
</Response>`;

const doneTexml = (req) => `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  ${speech(req, GOODBYE, ttsByText.get(GOODBYE))}
  <Hangup/>
</Response>`;

// The OpenAI key, if there is one: env wins, else the repo root's gitignored
// .env. Read lazily and cached — a machine with neither still works via uvx.
let _openaiKey;
function openaiKey() {
  if (_openaiKey !== undefined) return _openaiKey;
  _openaiKey = process.env.OPENAI_API_KEY || '';
  if (!_openaiKey) {
    try {
      const env = readFileSync(join(__dirname, '..', '..', '.env'), 'utf8');
      _openaiKey = (env.match(/^OPENAI_API_KEY\s*=\s*["']?([^"'\n]+)/m) || [])[1] || '';
    } catch { /* no .env — uvx fallback below */ }
  }
  return _openaiKey;
}

const OPENAI_MODEL = process.env.CREW_TRANSCRIBE_MODEL || 'gpt-4o-mini-transcribe';

// --- the voice of the call ---
// Telnyx's default <Say> voice is the robotic one everyone knows from IVRs,
// and through a phone codec it is genuinely hard to follow. So when there is
// an OpenAI key we synthesise the speech ourselves and hand the call a <Play>
// URL instead — the same trick that made settle-wise's calls sound human,
// minus the Vapi dependency. Synthesis happens at QUEUE time, before the dial,
// so the audio is sitting ready when the call answers. No key, or a failed
// synth → <Say> fallback, because a robotic call beats a silent one.
const TTS_MODEL = process.env.CREW_TTS_MODEL || 'gpt-4o-mini-tts';
const TTS_VOICE = process.env.CREW_TTS_VOICE || 'coral';
const ttsById = new Map();   // id -> mp3 buffer, served at /audio/<id>.mp3
const ttsByText = new Map(); // text -> id, so the constant goodbye is made once
let nextTtsId = 1;

async function tts(text) {
  if (!openaiKey()) return null;
  if (ttsByText.has(text)) return ttsByText.get(text);
  const r = await fetch('https://api.openai.com/v1/audio/speech', {
    method: 'POST',
    headers: { authorization: `Bearer ${openaiKey()}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      model: TTS_MODEL,
      voice: TTS_VOICE,
      input: text,
      // Every line is a separate render, and an expressive model treats each
      // as a fresh take — a live test's goodbye came out sounding like a
      // different person than the intro. Pin one persona, one register.
      instructions:
        'A real person mid-way through one continuous, friendly work phone call. ' +
        'Every line must sound like the SAME speaker in the SAME call: identical tone, ' +
        'pace and energy — calm, warm, medium energy, natural pauses, a slight smile. ' +
        'Short lines get the same relaxed delivery as long ones, never a chirpy sign-off. ' +
        'Never announcer-like, never IVR, never robotic.',
      response_format: 'mp3',
    }),
    signal: AbortSignal.timeout(15_000),
  });
  if (!r.ok) throw new Error(`OpenAI TTS HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const id = nextTtsId++;
  ttsById.set(id, Buffer.from(await r.arrayBuffer()));
  ttsByText.set(text, id);
  // The cache only ever holds this session's handful of lines, but bound it
  // anyway — a long rehearsal shouldn't hoard every mp3 it ever spoke.
  if (ttsById.size > 20) {
    const oldest = ttsById.keys().next().value;
    ttsById.delete(oldest);
    for (const [t, i] of ttsByText) if (i === oldest) ttsByText.delete(t);
  }
  return id;
}

// What an ask sounds like, start to finish. The opening and close are the
// house style, fixed here so every agent's call sounds the same: say why we
// are calling, ask, and once the person has answered — thanks, and hang up.
const ASK_INTRO =
  "Hi — it's your crew calling. The agents are running, and one of them has a query that needs your approval before it can carry on. Here it is.";
// The 3s pause matches the Record timeout below — the outro must promise
// exactly what the call will do, or the person sits waiting like our user did
// on the first live test and gives up.
const ASK_OUTRO = "Go ahead after the beep — when you're done, just pause, and I'll take it from there.";
const GOODBYE = "Okay, got it. I'll pass that along and the crew will carry on. Bye.";

async function openaiTranscribe(mp3) {
  const form = new FormData();
  form.append('file', new Blob([readFileSync(mp3)], { type: 'audio/mpeg' }), 'answer.mp3');
  form.append('model', OPENAI_MODEL);
  const r = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { authorization: `Bearer ${openaiKey()}` },
    body: form,
    signal: AbortSignal.timeout(30_000),
  });
  if (!r.ok) throw new Error(`OpenAI transcription HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return ((await r.json()).text || '').replace(/\s+/g, ' ').trim();
}

// uvx mlx-whisper — the no-API fallback. Apple silicon, model cached after
// the first run, but the first run downloads ~1.6GB, so the API path is the
// one to have working before a demo.
const localTranscribe = (mp3, dir) => new Promise((resolve, reject) => {
  const w = spawn('uvx', [
    '--from', 'mlx-whisper', 'mlx_whisper', mp3,
    '--model', WHISPER_MODEL, '--output-dir', dir, '--output-name', 'answer', '--output-format', 'txt',
  ], { stdio: 'ignore' });
  w.on('error', () => reject(new Error('uvx not found — brew install uv, or provide an OpenAI key')));
  w.on('close', (c) => {
    if (c) return reject(new Error(`whisper exited ${c}`));
    try { resolve(readFileSync(join(dir, 'answer.txt'), 'utf8').replace(/\s+/g, ' ').trim()); }
    catch { reject(new Error('whisper wrote no text')); }
  });
});

// Download the answer, transcribe it, throw the audio away. The recording URL
// is a presigned S3 link that expires in 10 minutes, so this starts the moment
// the callback lands. Failure resolves an honest empty answer rather than
// hanging the agent forever.
function transcribeAndDiscard(url, callSid) {
  const dir = mkdtempSync(join(tmpdir(), 'crew-call-'));
  const mp3 = join(dir, 'answer.mp3');
  const discard = () => rm(dir, { recursive: true, force: true }, () => {});
  const resolve = (text, source, note) => {
    discard();
    answer = { text, ts: new Date().toISOString() };
    if (text) logEvent('transcript', { callSid, source, text });
    console.log(text ? `[voice] the user said: "${text}"` : `[voice] no transcript — ${note}`);
  };
  const curl = spawn('curl', ['-sf', url, '-o', mp3], { stdio: 'ignore' });
  curl.on('error', (e) => resolve('', '', `download failed: ${e.message}`));
  curl.on('close', async (code) => {
    if (code) return resolve('', '', `download failed (curl exit ${code})`);
    if (openaiKey()) {
      try { return resolve(await openaiTranscribe(mp3), 'openai', ''); }
      catch (e) { console.error(`[voice] ${e.message} — falling back to local whisper`); }
    }
    try { resolve(await localTranscribe(mp3, dir), 'local-whisper', ''); }
    catch (e) { resolve('', '', e.message); }
  });
}

// Telnyx TeXML callbacks are form-encoded (Twilio-compatible); /say and /ask
// are JSON. Parse whichever arrives — and log a slice of the raw body, so a
// shape we did not expect is a line in the log instead of a lost event.
function parseBody(raw, contentType = '') {
  if (contentType.includes('json')) { try { return JSON.parse(raw); } catch { return {}; } }
  return Object.fromEntries(new URLSearchParams(raw));
}

const readBody = (req) => new Promise((resolve) => {
  let raw = '';
  req.on('data', (d) => (raw += d));
  req.on('end', () => resolve(raw));
});

const reply = (res, code, type, body) => { res.writeHead(code, { 'content-type': type }); res.end(body); };
const xml = (res, body) => reply(res, 200, 'application/xml', body);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;

  if (req.method === 'POST' && (path === '/say' || path === '/ask')) {
    const p = parseBody(await readBody(req), 'json');
    const m = path === '/ask' ? p.question : p.message;
    if (typeof m !== 'string' || !m.trim()) {
      return reply(res, 400, 'application/json', `{"error":"${path === '/ask' ? 'question' : 'message'} (string) required"}`);
    }
    const mode = path === '/ask' ? 'ask' : 'announce';
    const spoken = mode === 'ask'
      ? `${ASK_INTRO} ${m.trim()} ${ASK_OUTRO}`
      : m.trim();
    let audioId = null;
    try {
      audioId = await tts(spoken);
      if (mode === 'ask') await tts(GOODBYE); // made once, cached for /record-done
    } catch (e) { console.error(`[voice] TTS failed, <Say> fallback: ${e.message}`); }
    call = { mode, message: m.trim(), spoken, audioId };
    answer = null; // a new ask forgets the previous answer
    console.log(`[voice] queued ${call.mode} (${audioId ? 'openai voice' : 'telnyx say'}): "${call.message}"`);
    return reply(res, 200, 'application/json', '{"ok":true}');
  }

  // The synthesised speech the TeXML <Play> points back at.
  const audioMatch = path.match(/^\/audio\/(\d+)\.mp3$/);
  if (req.method === 'GET' && audioMatch) {
    const buf = ttsById.get(Number(audioMatch[1]));
    if (!buf) return reply(res, 404, 'application/json', '{"error":"no such audio"}');
    res.writeHead(200, { 'content-type': 'audio/mpeg', 'content-length': buf.length });
    return res.end(buf);
  }

  if (path === '/voice') {
    const raw = req.method === 'POST' ? await readBody(req) : '';
    const p = parseBody(raw, req.headers['content-type'] || '');
    console.log(`[voice] ${req.method} /voice — call answered (${call.mode})`);
    logEvent('call_answered', { callSid: p.CallSid, from: p.From, to: p.To, mode: call.mode, said: call.message });
    return xml(res, answerTexml(req));
  }

  if (req.method === 'POST' && path === '/record-done') {
    await readBody(req); // nothing kept from it — the recording callback has the URL
    return xml(res, doneTexml(req));
  }

  if (req.method === 'POST' && path === '/recording-status') {
    const raw = await readBody(req);
    const p = parseBody(raw, req.headers['content-type'] || '');
    // The URL arrives with HTML-escaped ampersands through a1mobile's relay;
    // unescape or the S3 signature never matches.
    const rec = (p.RecordingUrl || '').replace(/&amp;/g, '&');
    if (call.mode === 'ask' && rec) transcribeAndDiscard(rec, p.CallSid);
    else console.log(`[voice] recording callback ignored (${call.mode} mode)`);
    return reply(res, 200, 'application/json', '{"ok":true}');
  }

  // The bridge parks here while the phone rings and the person talks. Answer
  // arrives -> respond at once; deadline passes -> honest null, caller decides.
  if (req.method === 'GET' && path === '/answer') {
    const deadline = Date.now() + Math.min(Number(url.searchParams.get('timeout')) || 120_000, 300_000);
    while (!answer && Date.now() < deadline) await sleep(500);
    return reply(res, 200, 'application/json', JSON.stringify(answer || { text: null }));
  }

  if (req.method === 'GET' && path === '/transcripts') {
    let lines = [];
    try {
      lines = readFileSync(LOG_PATH, 'utf8').trim().split('\n')
        .map((l) => { try { return JSON.parse(l); } catch { return null; } })
        .filter((e) => e && e.event === 'transcript');
    } catch { /* no log yet — an empty list is the honest answer */ }
    return reply(res, 200, 'application/json', JSON.stringify(lines, null, 2));
  }

  if (req.method === 'GET' && path === '/health') {
    return reply(res, 200, 'application/json', JSON.stringify({ ok: true, mode: call.mode, message: call.message, log: LOG_PATH }));
  }

  reply(res, 404, 'application/json', '{"error":"not found"}');
})
  .on('error', (e) => {
    console.error(e.code === 'EADDRINUSE'
      ? `voice-webhook: :${PORT} is already in use — another one is running.`
      : `voice-webhook: ${e.message}`);
    process.exit(1);
  })
  .listen(PORT, () => console.log(`voice-webhook on :${PORT} — point the number at https://YOUR-TUNNEL/voice (log: ${LOG_PATH})`));
