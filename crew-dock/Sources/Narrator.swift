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
        // Resolved once, now, rather than at the first utterance: the first
        // utterance happens in front of the audience.
        let requested = env["CREW_AUDIO_DEVICE"].flatMap { $0.isEmpty ? nil : $0 }
        device = muted ? nil : requested.flatMap(Self.resolveDevice)
        rate = env["CREW_RATE"].flatMap(Int.init) ?? Self.defaultRate

        var v = Self.defaultVoices
        for role in v.keys {
            if let override = env["CREW_VOICE_\(role.uppercased())"], !override.isEmpty {
                v[role] = override
            }
        }
        voices = v
    }

    /// Checks `CREW_AUDIO_DEVICE` against the devices `say` will actually accept.
    ///
    /// `say -a` takes a device name or a numeric ID and rejects anything else —
    /// but it reports that on *its* stderr, which we discard, and it fails per
    /// utterance rather than at launch. So a name that doesn't resolve (a typo,
    /// or BlackHole simply not installed on that Mac yet) produces a dock that
    /// prints a flawless `SAY ->` for every line and makes no sound at all.
    /// That is the same "the log is not evidence" trap that already cost us a
    /// run, so the name is resolved once, out loud, before the show.
    ///
    /// Never refuses to speak — narration on the wrong speaker beats a silent
    /// demo. But it prefers the *built-in speakers* over the system default,
    /// because the system default is not a safe place to land here: the audio
    /// rig switches the default output around, so falling back to it could put
    /// narration on BlackHole — i.e. straight into VoiceOS's ear, which is the
    /// exact collision the device split exists to prevent. Built-in speakers
    /// are the audience channel by definition, and BlackHole can never match.
    private static func resolveDevice(_ name: String) -> String? {
        if !name.isEmpty, name.allSatisfy(\.isNumber) { return name }  // device ID

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        proc.arguments = ["-a", "?"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        // If we can't even ask, don't second-guess the operator — pass it through.
        guard (try? proc.run()) != nil else { return name }
        let listing = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
                             as: UTF8.self)
        proc.waitUntilExit()

        // Lines look like "   71 MacBook Air Speakers".
        let devices: [String] = listing.split(separator: "\n").map { line in
            let withoutID = line.drop(while: { $0 == " " }).drop(while: { $0.isNumber })
            return withoutID.trimmingCharacters(in: .whitespaces)
        }
        if devices.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return name
        }

        // "MacBook Air Speakers", "MacBook Pro Speakers", "iMac Speakers" — the
        // built-in output. A loopback device ("BlackHole 2ch") never matches.
        let builtIn = devices.first { $0.hasSuffix("Speakers") }

        let landing = builtIn.map { "\"\($0)\"" } ?? "the system default output"
        let warning = "SAY !! no audio output device named \"\(name)\" — narrating to "
            + "\(landing) instead so the dock still speaks. Available: "
            + devices.joined(separator: " | ") + "\n"
        FileHandle.standardError.write(Data(warning.utf8))
        return builtIn
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

        // `SAY ->` above only proves we asked. Without this, any failure `say`
        // reports on the stderr we discard — a device that vanished mid-run, a
        // watchdog kill — leaves a log that reads like the line was heard.
        if proc.terminationStatus != 0 {
            FileHandle.standardError.write(Data(
                "SAY !! `say` exited \(proc.terminationStatus) — that line was NOT heard\n".utf8))
        }
    }
}
