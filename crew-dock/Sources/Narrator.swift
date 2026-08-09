import Foundation

/// Speaks agent narration out loud via `say`.
///
/// Everything here exists to keep utterances from overlapping. Two characters
/// talking at once is unintelligible in the room, and — because the demo's
/// control loop runs through a microphone — it also gives VoiceOS a mix of two
/// voices to transcribe. One utterance at a time, always.
final class Narrator {
    /// Per-character voice, so the swarm sounds like several entities rather
    /// than one process with three sprites.
    private static let defaultVoices = [
        "triage": "Samantha",
        "scheduler": "Daniel",
        "recap": "Karen",
    ]
    private static let fallbackVoice = "Samantha"

    /// Two agents narrate in parallel but there is only one voice channel, so
    /// lines arrive faster than they can be spoken. This is the budget for how
    /// far speech may trail the bubbles before we start skipping lines.
    /// At 2 it dropped over half the run, including "Booking two PM with David
    /// Chen" — the line the whole demo is for. 4 keeps the content and trails
    /// by a few seconds, which reads as a character finishing its thought.
    private static let maxBacklog = 4

    /// Default `say` is ~175 wpm. A little faster keeps narration close to the
    /// bubbles without sounding rushed.
    private static let defaultRate = 200

    /// Orchestrator placeholder — it shows in the bubble as the character fades
    /// in, but spending a speech slot on it costs a real line later.
    private static let unspoken: Set<String> = ["waking up"]

    /// A `say` that somehow never exits must not silence the rest of the show.
    private static let utteranceTimeout: TimeInterval = 15

    /// `state` guards the queue; `speech` runs the utterances, one at a time,
    /// blocking on each until the audio finishes.
    private let queue = DispatchQueue(label: "xyz.crew.narrator.state")
    private let speech = DispatchQueue(label: "xyz.crew.narrator.speech")
    private let voices: [String: String]
    private let device: String?
    private let muted: Bool
    private let rate: Int

    private var pending: [(text: String, voice: String, final: Bool)] = []
    private var draining = false
    private var lastSaid: [String: String] = [:]

    init(environment env: [String: String] = ProcessInfo.processInfo.environment) {
        muted = env["CREW_MUTE"] == "1"
        // Set this to keep narration off whichever device VoiceOS is listening
        // on — otherwise the dock narrates into the agents' own command channel.
        device = env["CREW_AUDIO_DEVICE"].flatMap { $0.isEmpty ? nil : $0 }
        rate = env["CREW_RATE"].flatMap(Int.init) ?? Self.defaultRate

        var v = Self.defaultVoices
        for role in v.keys {
            if let override = env["CREW_VOICE_\(role.uppercased())"], !override.isEmpty {
                v[role] = override
            }
        }
        voices = v
    }

    /// Called on every status POST. Safe to call from any thread.
    func narrate(character: String, message: String, state: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !muted, !text.isEmpty, state != "idle",
              !Self.unspoken.contains(text.lowercased()) else { return }

        queue.async {
            // The orchestrator re-sends the last line with state "done" to close
            // an agent out, so without this every agent says its sign-off twice.
            guard self.lastSaid[character] != text else { return }
            self.lastSaid[character] = text

            // "Done: …" is the character's last word on stage — it always gets
            // said, even when we're trimming a backlog.
            let final = text.hasPrefix("Done:")
            self.pending.append((text, self.voices[character] ?? Self.fallbackVoice, final))
            if self.pending.count > Self.maxBacklog {
                let cut = self.pending.count - Self.maxBacklog
                // `Array(...)` matters: a slice keeps its parent's indices, so
                // inserting at 0 into one traps at runtime.
                var kept = Array(self.pending.suffix(Self.maxBacklog))
                // Never drop a sign-off that fell outside the window.
                kept.insert(contentsOf: self.pending.prefix(cut).filter(\.final), at: 0)
                self.pending = kept
            }
            guard !self.draining else { return }
            self.draining = true
            self.speech.async { self.drain() }
        }
    }

    /// Runs on `speech`. Speaks until the queue is empty, then stops.
    ///
    /// Deliberately blocking rather than driven by `Process.terminationHandler`:
    /// the handler did not fire reliably, which left the narrator wedged
    /// mid-utterance and silenced the dock for the rest of its life. Waiting on
    /// the process is the thing we actually mean, and it can't be missed.
    private func drain() {
        while true {
            var next: (text: String, voice: String, final: Bool)?
            queue.sync {
                if self.pending.isEmpty {
                    self.draining = false
                } else {
                    next = self.pending.removeFirst()
                }
            }
            guard let utterance = next else { return }
            speak(utterance)
        }
    }

    /// Returns once the audio has finished playing.
    private func speak(_ utterance: (text: String, voice: String, final: Bool)) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args = ["-v", utterance.voice, "-r", String(rate)]
        if let device { args += ["-a", device] }
        // `--` so a message starting with "-" is never read as a flag.
        args += ["--", utterance.text]
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        // Same spirit as the DOCK <- lines: the pipeline has to be verifiable
        // from a log, because "was that silent?" is not answerable on stage.
        FileHandle.standardError.write(Data("SAY -> [\(utterance.voice)] \(utterance.text)\n".utf8))

        do {
            try proc.run()
        } catch {
            // No voice is better than a dead dock — keep the queue moving.
            FileHandle.standardError.write(Data("SAY !! failed: \(error)\n".utf8))
            return
        }

        // Not on `speech` — this drain is blocking that queue right now.
        let watchdog = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.utteranceTimeout,
                                         execute: watchdog)
        proc.waitUntilExit()
        watchdog.cancel()
    }
}
