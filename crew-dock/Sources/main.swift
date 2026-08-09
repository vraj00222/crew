import AppKit

// Crew dock — the visible half of the demo. Listens on :4002 and puts a
// talking character on screen for each agent the orchestrator wakes.
// AgentCharacter art from lil-agents (MIT, © 2026 Ryan Stephen).

let roles = ["triage", "scheduler", "recap"]
let videoFor = ["triage": "walk-bruce-01", "scheduler": "walk-jazz-01", "recap": "walk-bruce-01"]

final class DockController {
    private var characters: [String: AgentCharacter] = [:]

    init() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        // Spread them along the bottom, just above the dock.
        let totalWidth = AgentCharacter.width * CGFloat(roles.count)
        let startX = vf.midX - totalWidth / 2
        for (i, role) in roles.enumerated() {
            guard let url = Bundle.main.url(forResource: videoFor[role], withExtension: "mov")
                ?? localAssetURL(videoFor[role]!) else {
                FileHandle.standardError.write(Data("missing video for \(role)\n".utf8))
                continue
            }
            characters[role] = AgentCharacter(role: role, videoURL: url,
                                         originX: startX + CGFloat(i) * AgentCharacter.width,
                                         originY: vf.minY - 12)
        }
    }

    /// Running unbundled (swift build / dev loop) — fall back to ./Assets.
    private func localAssetURL(_ name: String) -> URL? {
        let p = FileManager.default.currentDirectoryPath + "/Assets/\(name).mov"
        return FileManager.default.fileExists(atPath: p) ? URL(fileURLWithPath: p) : nil
    }

    func apply(_ s: StatusServer.Status) {
        // stderr so the pipeline is verifiable from a log when you can't watch the screen
        FileHandle.standardError.write(Data("DOCK <- \(s.character) [\(s.state)] \(s.message)\n".utf8))
        guard let c = characters[s.character] else {
            FileHandle.standardError.write(Data("  (no character named '\(s.character)')\n".utf8))
            return
        }
        c.apply(message: s.message, state: s.state)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no dock icon, no menu bar — just the characters

let dock = DockController()
let narrator = Narrator()
guard let server = StatusServer(port: 4002, onStatus: { status in
    // Bubble updates immediately; speech queues behind whoever is talking.
    DispatchQueue.main.async { dock.apply(status) }
    narrator.narrate(character: status.character, message: status.message, state: status.state)
}) else {
    FileHandle.standardError.write(Data("could not bind :4002 — already in use?\n".utf8))
    exit(1)
}
server.start()
FileHandle.standardError.write(Data("crew dock listening on :4002\n".utf8))
app.run()
