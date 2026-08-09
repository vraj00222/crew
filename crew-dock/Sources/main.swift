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

    static func load() -> Roster {
        // No manifest at all is a normal, quiet case — the built-in three are
        // the truth today.
        guard let url = manifestURL() else { return builtIn }

        // A manifest that exists but can't be read is not quiet. Whoever is
        // editing this file needs to know their edit did nothing, or they will
        // change it, see no difference, and conclude the loader is ignoring them.
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["characters"] as? [[String: Any]]
        else {
            let warning = "characters.json is unreadable or has no \"characters\" array — "
                + "using the built-in three (\(url.path))\n"
            FileHandle.standardError.write(Data(warning.utf8))
            return builtIn
        }

        let chars = rows.compactMap { row -> Character? in
            guard let role = row["role"] as? String, let asset = row["asset"] as? String
            else { return nil }
            return Character(role: role, asset: asset, mirrored: row["mirrored"] as? Bool ?? false)
        }
        guard !chars.isEmpty else {
            FileHandle.standardError.write(Data(
                "characters.json has no usable rows — using the built-in three\n".utf8))
            return builtIn
        }

        var rates: [String: Float] = [:]
        for (name, value) in (json["activities"] as? [String: Any] ?? [:]) {
            if let spec = value as? [String: Any], let r = spec["rate"] as? Double {
                rates[name] = Float(r)
            }
        }
        FileHandle.standardError.write(Data(
            "roster: \(chars.map(\.role).joined(separator: ", ")) (from characters.json)\n".utf8))
        return Roster(characters: chars, activityRate: rates)
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
    private let roster = Roster.load()

    init() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        // Spread them along the bottom, just above the dock.
        let totalWidth = AgentCharacter.width * CGFloat(roster.characters.count)
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
                                         originX: startX + CGFloat(i) * AgentCharacter.width,
                                         originY: vf.minY - 12,
                                         mirrored: spec.mirrored)
        }
    }

    /// Running unbundled (swift build / dev loop) — fall back to ./Assets.
    private func localAssetURL(_ name: String) -> URL? {
        let p = FileManager.default.currentDirectoryPath + "/Assets/\(name).mov"
        return FileManager.default.fileExists(atPath: p) ? URL(fileURLWithPath: p) : nil
    }

    /// One timer for every character rather than one each: the dock has to stay
    /// out of the way of the thing it is narrating, and this is the only clock
    /// in the app. Drives the "still thinking" behaviour when an agent goes
    /// quiet — see AgentCharacter.tick.
    func startClock() {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            let now = Date()
            self?.characters.values.forEach { $0.tick(now) }
        }
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
app.run()
