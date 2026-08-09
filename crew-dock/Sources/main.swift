import AppKit

// Crew dock — the visible half of the demo. Listens on :4002 and puts a
// talking character on screen for each agent the orchestrator wakes.
// AgentCharacter art from lil-agents (MIT, © 2026 Ryan Stephen).

/// Who is on the crew, and how each kind of work moves.
///
/// Data rather than Swift, so adding a crew member is a row plus an asset
/// instead of an edit here — D owns `characters.json` and the art, C owns this
/// loader. **A missing or unreadable manifest falls back to exactly today's
/// three characters**, so the dock can never be broken by the file it is
/// supposed to be configured by: the rehearsed run keeps working either way.
struct Roster {
    struct Character { let role: String; let asset: String; let mirrored: Bool }

    var characters: [Character]
    /// activity -> playback rate while `working`. Keyed on the work, not the
    /// name, so two agents doing research move alike and this file never has to
    /// learn the roster.
    var activityRate: [String: Float]

    static let builtIn = Roster(characters: [
        Character(role: "triage",    asset: "walk-bruce-01", mirrored: false),
        Character(role: "scheduler", asset: "walk-jazz-01",  mirrored: false),
        // recap reuses triage's clip — mirror it so the same character is not
        // on screen twice, side by side.
        Character(role: "recap",     asset: "walk-bruce-01", mirrored: true),
    ], activityRate: [:])

    /// Loads the roster and states, in one line, **which** roster is in effect
    /// and where it came from.
    ///
    /// It used to print `(from characters.json)` only on the happy path and a
    /// warning on the others. D pointed out the real hazard in that: whoever is
    /// editing the manifest greps for `roster:` and, on a fallback, sees
    /// nothing — and silence is ambiguous in exactly the moment you need an
    /// answer. So the line is unconditional and always names its source. The
    /// claim "I read your file" is now only ever made when a row from it was
    /// actually used.
    static func load() -> Roster {
        let (roster, source) = resolve()
        let line = "roster: \(roster.characters.map(\.role).joined(separator: ", ")) (\(source))\n"
        FileHandle.standardError.write(Data(line.utf8))
        return roster
    }

    private static func resolve() -> (Roster, String) {
        // No manifest at all is the normal case today, not a fault.
        guard let url = manifestURL() else { return (builtIn, "built-in — no characters.json") }

        // Note both of these say what to fix, not just that something is wrong:
        // a bad manifest is edited by a person who needs to know which shape
        // the loader wanted.
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["characters"] as? [[String: Any]]
        else {
            return (builtIn, "built-in — \(url.path) is unreadable or has no \"characters\" array")
        }

        let chars = rows.compactMap { row -> Character? in
            guard let role = row["role"] as? String, let asset = row["asset"] as? String
            else { return nil }
            return Character(role: role, asset: asset, mirrored: row["mirrored"] as? Bool ?? false)
        }
        guard !chars.isEmpty else {
            return (builtIn, "built-in — \(url.path) has no usable rows; each needs \"role\" and \"asset\"")
        }

        var rates: [String: Float] = [:]
        for (name, value) in (json["activities"] as? [String: Any] ?? [:]) {
            if let spec = value as? [String: Any], let r = spec["rate"] as? Double {
                rates[name] = Float(r)
            }
        }
        return (Roster(characters: chars, activityRate: rates), "from characters.json")
    }

    private static func manifestURL() -> URL? {
        if let u = Bundle.main.url(forResource: "characters", withExtension: "json") { return u }
        // Unbundled dev loop, run from the repo root or from crew-dock/.
        for p in ["crew-dock/characters.json", "characters.json"] {
            let f = FileManager.default.currentDirectoryPath + "/" + p
            if FileManager.default.fileExists(atPath: f) { return URL(fileURLWithPath: f) }
        }
        return nil
    }
}

final class DockController {
    private var characters: [String: AgentCharacter] = [:]
    /// Roles that have sent at least one line, i.e. the crew actually on stage.
    private var woken: [String] = []
    private let roster = Roster.load()

    init() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        // Spread them along the bottom, just above the dock — and fit the crew
        // to the screen rather than assuming it fits.
        //
        // At one window-width apart, five characters need 1500pt. This Air has
        // 1470pt of usable width, so the last window was asked to sit partly
        // offscreen; macOS clamps a window onscreen instead, which silently
        // parks the last two almost on top of each other with their bubbles
        // overlapping. It looks like a layout that was never designed rather
        // than one that ran out of room, and it only appears on screens narrower
        // than the author's — the crew grew from three to five today, so this
        // was reachable the moment a longer sentence spawned a bigger crew.
        //
        // Packing to the available width keeps the spacing even at any crew
        // size. Identical to the old maths whenever the crew genuinely fits,
        // so the rehearsed three are placed exactly where they always were.
        let w = AgentCharacter.width
        let n = roster.characters.count
        let spacing = n > 1 ? min(w, (vf.width - w) / CGFloat(n - 1)) : 0
        let totalWidth = w + spacing * CGFloat(max(0, n - 1))
        let startX = vf.midX - totalWidth / 2
        for (i, spec) in roster.characters.enumerated() {
            guard let url = Bundle.main.url(forResource: spec.asset, withExtension: "mov")
                ?? localAssetURL(spec.asset) else {
                // Named in the manifest but the .mov isn't there — say which,
                // because the symptom is a character silently missing on stage.
                FileHandle.standardError.write(Data(
                    "missing asset '\(spec.asset).mov' for \(spec.role) — that character will not appear\n".utf8))
                continue
            }
            characters[spec.role] = AgentCharacter(role: spec.role, videoURL: url,
                                         originX: startX + CGFloat(i) * spacing,
                                         originY: vf.minY - 12,
                                         mirrored: spec.mirrored,
                                         // staggered entrance: a crew, not a rank
                                         slot: i)
        }
    }

    /// Running unbundled (swift build / dev loop) — fall back to ./Assets.
    private func localAssetURL(_ name: String) -> URL? {
        let p = FileManager.default.currentDirectoryPath + "/Assets/\(name).mov"
        return FileManager.default.fileExists(atPath: p) ? URL(fileURLWithPath: p) : nil
    }

    /// Spreads the crew that actually woke evenly across the screen, in
    /// manifest order so left-to-right identity stays stable between runs.
    ///
    /// Laying out by manifest index instead left holes: with five roles listed
    /// and the rehearsed three running, they landed on slots 0, 1 and 4 — two
    /// crowded together with overlapping bubbles and one marooned. What is on
    /// screen should be spaced by what is on screen.
    private func recentre() {
        guard let vf = NSScreen.main?.visibleFrame else { return }
        let order = roster.characters.map(\.role).filter { woken.contains($0) }
        let w = AgentCharacter.width
        let n = order.count
        let spacing = n > 1 ? min(w, (vf.width - w) / CGFloat(n - 1)) : 0
        let startX = vf.midX - (w + spacing * CGFloat(max(0, n - 1))) / 2
        var placed: [String] = []
        for (i, role) in order.enumerated() {
            let x = startX + CGFloat(i) * spacing
            characters[role]?.place(x: x)
            placed.append("\(role)@\(Int(x))")
        }
        // Where the crew actually stands, from the code that decides it. Every
        // layout bug on this project so far has been invisible in a log and
        // obvious on screen; this is the one number that connects the two.
        let stage = "STAGE screen \(Int(vf.width))x\(Int(vf.height)) @\(Int(vf.minX)),\(Int(vf.minY))"
            + " | \(placed.joined(separator: " "))\n"
        FileHandle.standardError.write(Data(stage.utf8))
    }

    /// One timer for every character rather than one each: the dock has to stay
    /// out of the way of the thing it is narrating, and this is the only clock
    /// in the app. Drives the "still thinking" behaviour when an agent goes
    /// quiet — see AgentCharacter.tick.
    /// Who signed off last — the closer. It is whoever most recently reached
    /// `done`, rather than a hardcoded "recap", so it stays right when the crew
    /// is 2 or 5 and whatever the roles are called.
    private var lastToFinish: String?
    private var allDoneAt: Date?
    /// Long enough for the closer's last line to be *spoken*, not just posted —
    /// speech trails the bubbles, and sending the crew away over the top of the
    /// summary would undo the one line the audience is meant to leave with.
    private let curtainAfter: TimeInterval = 7

    func startClock() {
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            self.characters.values.forEach { $0.tick(now) }
            self.curtainTick(now)
        }
    }

    /// The end of the show used to be five characters standing under stale
    /// bubbles until somebody hit ctrl-C. When every character on screen has
    /// signed off, wait for the last line to finish being spoken, then send the
    /// crew away and leave the closer alone with the summary.
    private func curtainTick(_ now: Date) {
        let onScreen = characters.values.filter(\.isOnScreen)
        guard !onScreen.isEmpty, onScreen.allSatisfy(\.isDone) else {
            allDoneAt = nil
            return
        }
        if allDoneAt == nil { allDoneAt = now; return }
        guard now.timeIntervalSince(allDoneAt!) >= curtainAfter else { return }
        allDoneAt = nil

        let keep = lastToFinish
        FileHandle.standardError.write(Data(
            "CURTAIN -> crew leaving, \(keep ?? "nobody") stays with the summary\n".utf8))
        for (role, c) in characters where role != keep { c.leave() }
    }

    func apply(_ s: StatusServer.Status) {
        // stderr so the pipeline is verifiable from a log when you can't watch the screen
        let act = s.activity.isEmpty ? "" : " {\(s.activity)}"
        FileHandle.standardError.write(Data("DOCK <- \(s.character) [\(s.state)]\(act) \(s.message)\n".utf8))
        guard let c = characters[s.character] else {
            // A crew member with no costume. Logged loudly because the narrator
            // still speaks this line — so it is heard with nothing on screen,
            // which is the one failure the audience notices and the log doesn't.
            FileHandle.standardError.write(Data(
                "  (no character named '\(s.character)' — spoken but NOT shown)\n".utf8))
            return
        }
        if s.state == "done" { lastToFinish = s.character }
        // First sight of this role: it joins the line-up and the crew re-centres.
        if !woken.contains(s.character) {
            woken.append(s.character)
            recentre()
        }
        c.apply(message: s.message, state: s.state, activityRate: roster.activityRate[s.activity])
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no dock icon, no menu bar — just the characters

let dock = DockController()
dock.startClock()
let narrator = Narrator()
guard let server = StatusServer(port: 4002, onStatus: { status in
    // Bubble updates immediately; speech queues behind whoever is talking.
    DispatchQueue.main.async { dock.apply(status) }
    narrator.narrate(character: status.character, message: status.message, state: status.state)
}) else {
    FileHandle.standardError.write(Data("could not bind :4002 — already in use?\n".utf8))
    exit(1)
}
server.start()   // prints "listening" itself, once the bind actually succeeds

/// Global hotkey: ⌃⌥C wakes the crew, from anywhere, with no terminal.
///
/// The demo used to begin with somebody typing a command, which is a bad first
/// beat — it says "a script did this". A chord says "I asked, and they came".
/// It is deliberately NOT plain ⌃⌥: VoiceOS has that exact pair registered as
/// its own chord, and two things firing on one press is a stage bug nobody
/// would diagnose in the moment.
///
/// Needs Accessibility (System Settings -> Privacy & Security -> Accessibility),
/// the same grant `spike.sh trigger` needs. Without it the monitor silently
/// never fires, so we say so at start-up rather than leaving it a mystery.
/// Two chords, two tasks, so the demo is not one hardcoded sentence.
///
/// ⌃⌥C is the rehearsed run — three agents, ~45s, said out loud dozens of times.
/// ⌃⌥L is the long one — five agents, ~90s, and it shows the hand-off: the
/// analyst waits for the researcher and opens on what the researcher found.
/// Both are overridable, so a different demo is an env var rather than a build.
let shortPhrase = ProcessInfo.processInfo.environment["CREW_PHRASE"]
    ?? "clean up my inbox and schedule everything"
let longPhrase = ProcessInfo.processInfo.environment["CREW_PHRASE_LONG"]
    ?? "go through my inbox, research what is actually urgent, analyse which threads need a reply, and schedule the meetings"

/// ⌃⌥C asks the orchestrator to WAKE, not to run a fixed task: the crew arrives,
/// says "what can I do for you?", listens, and works on whatever you actually
/// said. Firing a hardcoded sentence was a demo of a script.
/// ⌃⌥L keeps the direct path for rehearsal, where you want the same run twice.
func wakeTheCrew(_ hotkeyPhrase: String?) {
    let path = hotkeyPhrase == nil ? "/wake" : "/start-task"
    guard let url = URL(string: "http://localhost:4001" + path) else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    if let p = hotkeyPhrase {
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["instructions": p])
    }
    FileHandle.standardError.write(Data(
        "HOTKEY -> \(hotkeyPhrase.map { "running: \"\($0)\"" } ?? "waking the crew — it will ask you")\n".utf8))
    URLSession.shared.dataTask(with: req) { _, resp, err in
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code != 200 {
            // The orchestrator not being up is the one likely failure, and it is
            // invisible otherwise — the chord would just do nothing.
            FileHandle.standardError.write(Data(
                "HOTKEY !! orchestrator did not answer (\(err?.localizedDescription ?? "HTTP \(code)")) — is ./run-demo.sh wait running?\n".utf8))
        }
    }.resume()
}

/// Holding the chord for half a second spawned 23 tasks: macOS repeats keyDown
/// while a key is held, and every repeat started a whole crew. On stage that is
/// two dozen agents talking over each other and a Claude bill to match.
/// `isARepeat` stops the held key; the cooldown stops a nervous double-press.
var lastWake = Date.distantPast
let wakeCooldown: TimeInterval = 0.6

if AXIsProcessTrusted() {
    // Match VoiceOS's OWN chord — control-left + option-left — rather than
    // inventing one next to it.
    //
    // VoiceOS registers that pair itself (keyboardShortcuts, mode 3), which is
    // why pressing ⌃⌥C was already making its notch UI react. So instead of
    // avoiding the collision, be the collision: ONE press opens VoiceOS's ear
    // and wakes the crew at the same time, and `fn`+`space` — the step no script
    // could ever do — stops being needed at all.
    //
    // Modifiers with no letter, so it arrives as flagsChanged, not keyDown.
    var chordDown = false
    NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { e in
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let held = mods.contains(.control) && mods.contains(.option)
            && !mods.contains(.command) && !mods.contains(.shift)

        // Fire once per press, on the way down. Held modifiers repeat flags
        // events, and a run per event is how one press became 23 crews.
        guard held != chordDown else { return }
        chordDown = held
        guard held else { return }

        let now = Date()
        guard now.timeIntervalSince(lastWake) > wakeCooldown else { return }
        lastWake = now
        wakeTheCrew(nil)
    }
    // ⌃⌥L stays for rehearsal: same task twice, no talking.
    NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard e.keyCode == 37, mods.contains(.control), mods.contains(.option), !e.isARepeat else { return }
        let now = Date()
        guard now.timeIntervalSince(lastWake) > wakeCooldown else { return }
        lastWake = now
        wakeTheCrew(longPhrase)
    }
    FileHandle.standardError.write(Data(
        "hotkey ready — hold control+option: summon, speak, press again to send\n".utf8))
} else {
    FileHandle.standardError.write(Data((
        "hotkey OFF — no Accessibility permission, so control+option will do nothing.\n"
        + "  System Settings -> Privacy & Security -> Accessibility -> add this app or your terminal.\n").utf8))
}

app.run()
