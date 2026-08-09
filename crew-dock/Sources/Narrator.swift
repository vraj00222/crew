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

    /// Narration is decoration over the visuals: if we fall this far behind,
    /// the bubbles are already showing later lines and the backlog is stale.
    private static let maxBacklog = 2

    private let queue = DispatchQueue(label: "xyz.crew.narrator")
    private let voices: [String: String]
    private let device: String?
    private let muted: Bool

    private var pending: [(text: String, voice: String, final: Bool)] = []
    private var speaking = false
    private var lastSaid: [String: String] = [:]

    init(environment env: [String: String] = ProcessInfo.processInfo.environment) {
        muted = env["CREW_MUTE"] == "1"
        // Set this to keep narration off whichever device VoiceOS is listening
        // on — otherwise the dock narrates into the agents' own command channel.
        device = env["CREW_AUDIO_DEVICE"].flatMap { $0.isEmpty ? nil : $0 }

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
        guard !muted, !text.isEmpty, state != "idle" else { return }

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
            self.speakNext()
        }
    }

    /// Must be called on `queue`.
    private func speakNext() {
        guard !speaking, !pending.isEmpty else { return }
        let utterance = pending.removeFirst()
        speaking = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var args = ["-v", utterance.voice]
        if let device { args += ["-a", device] }
        // `--` so a message starting with "-" is never read as a flag.
        args += ["--", utterance.text]
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        // `say` exits when the audio finishes playing, which is exactly the
        // gate we want before starting the next line.
        proc.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.speaking = false
                self.speakNext()
            }
        }

        do {
            try proc.run()
        } catch {
            // No voice is better than a dead dock — keep the queue moving.
            FileHandle.standardError.write(Data("say failed: \(error)\n".utf8))
            speaking = false
            speakNext()
        }
    }
}
