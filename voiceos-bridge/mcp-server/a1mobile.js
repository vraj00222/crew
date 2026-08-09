#!/usr/bin/env node
// a1mobile — outbound SMS and calls via the hack.a1mobile.com hackathon API.
// Node stdlib only, no deps, no build step. Client module + one-time-setup CLI.
//
//   node a1mobile.js info                      what our number is wired to
//   node a1mobile.js verify  +1XXXXXXXXXX      OTP a phone we want to reach
//   node a1mobile.js confirm +1XXXXXXXXXX 123456
//   node a1mobile.js point   https://TUNNEL/voice
//   node a1mobile.js sms     +1XXXXXXXXXX "hello from the crew"
//   node a1mobile.js call    +1XXXXXXXXXX
//
// The team key is an API credential and lives in the gitignored
// ai-mobile-integration.md at the repo root — never in committed source, same
// rule as the VoiceOS config tokens. Env A1MOBILE_TEAM_KEY overrides, so a
// machine without the file still works.
//
// Two facts that shape everything here:
//   - You may only call/text numbers you have OTP-verified (consent). The API
//     enforces it; verify/confirm is the one-time human step, so it is CLI
//     only — never an agent tool.
//   - An outbound call runs our POINTED WEBHOOK on answer. Placing a call
//     without a pointed webhook rings a phone that then says nothing, which on
//     stage is worse than no call — see voice-webhook.js.

const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const BASE = (process.env.A1MOBILE_BASE_URL || 'https://hack.a1mobile.com').replace(/\/+$/, '');
const TIMEOUT_MS = Number(process.env.A1MOBILE_TIMEOUT_MS || 10_000);
// Rehearsal kill switch. A rehearsal loop that really texts a phone thirty
// times gets the demo number rate-limited or the human numb to it — either way
// the real run suffers. DRY logs what would have been sent and sends nothing.
const DRY = process.env.A1MOBILE_DRY === '1';
// Who "text me" / "call me" means when no number is given: the one phone we
// verified for the demo. Env, not hardcoded — it is somebody's personal number.
const DEFAULT_TO = process.env.CREW_PHONE || '';
const KEY_FILE = join(__dirname, '..', '..', 'ai-mobile-integration.md');

let _key;
function teamKey() {
  if (_key) return _key;
  _key = process.env.A1MOBILE_TEAM_KEY || '';
  if (!_key) {
    try { _key = (readFileSync(KEY_FILE, 'utf8').match(/team-[0-9a-f]+/i) || [''])[0]; } catch { /* no file */ }
  }
  if (!_key) {
    throw new Error(
      'no a1mobile team key — set A1MOBILE_TEAM_KEY or put ai-mobile-integration.md at the repo root'
    );
  }
  return _key;
}

async function api(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'X-Team-Key': teamKey(),
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { /* non-JSON error body — surfaced below */ }
  if (!res.ok) {
    throw new Error(`a1mobile ${path} -> HTTP ${res.status}: ${(json?.error || json?.detail || text).slice?.(0, 200) || text.slice(0, 200)}`);
  }
  return json ?? { ok: true };
}

// "text me" with no number means the demo phone. A missing default is a
// readable sentence, not a stack trace — VoiceOS may speak this out loud.
function resolveTo(to) {
  const n = (to || DEFAULT_TO).trim();
  if (!n) throw new Error('no phone number — pass "to", or set CREW_PHONE to the verified demo phone');
  if (!/^\+\d{7,15}$/.test(n)) throw new Error(`"${n}" is not an E.164 number like +14155551234`);
  return n;
}

const numberInfo = () => api('GET', '/api/numbers/me');
const claimNumber = () => api('POST', '/api/numbers/claim');
const pointWebhook = (webhook_url) => api('POST', '/api/numbers/point', { webhook_url });
const unpoint = () => api('POST', '/api/numbers/unpoint');
const requestVerification = (phone) => api('POST', '/api/verified-numbers', { phone });
const confirmVerification = (phone, code) => api('POST', '/api/verified-numbers/confirm', { phone, code });

async function sendSms({ to, body }) {
  const number = resolveTo(to);
  if (!body || !String(body).trim()) throw new Error('sendSms needs a non-empty body');
  if (DRY) return { dry: true, to: number, body };
  const r = await api('POST', '/api/sms', { to: number, body: String(body) });
  return { to: number, body: String(body), ...r };
}

async function placeCall({ to }) {
  const number = resolveTo(to);
  if (DRY) return { dry: true, to: number };
  const r = await api('POST', '/api/calls', { to: number });
  return { to: number, ...r };
}

module.exports = {
  numberInfo, claimNumber, pointWebhook, unpoint,
  requestVerification, confirmVerification, sendSms, placeCall,
  resolveTo, DRY,
};

// --- CLI: the one-time setup a human does before the demo ---
if (require.main === module) {
  const [cmd, a, ...rest] = process.argv.slice(2);
  const run = {
    info: () => numberInfo(),
    claim: () => claimNumber(),
    point: () => pointWebhook(a),
    unpoint: () => unpoint(),
    verify: () => requestVerification(a),
    confirm: () => confirmVerification(a, rest[0]),
    sms: () => sendSms({ to: a, body: rest.join(' ') }),
    call: () => placeCall({ to: a }),
  }[cmd];
  if (!run) {
    console.error(
      'usage: node a1mobile.js {info | claim | point <url> | unpoint | verify <phone> | confirm <phone> <code> | sms <phone> <body...> | call <phone>}'
    );
    process.exit(2);
  }
  run().then(
    (r) => console.log(JSON.stringify(r, null, 2)),
    (e) => { console.error(e.message); process.exit(1); }
  );
}
