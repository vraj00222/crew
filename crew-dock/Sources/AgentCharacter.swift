import AppKit
import AVFoundation

/// One agent = one borderless, click-through window sitting above the dock:
/// a looping transparent-HEVC character with a speech bubble over its head.
final class AgentCharacter {
    let role: String
    private let window: NSWindow
    private let bubble: BubbleView
    private let videoLayer: AVPlayerLayer
    private let looper: AVPlayerLooper?
    private let player: AVQueuePlayer

    static let width: CGFloat = 300
    static let charHeight: CGFloat = 170
    static let bubbleHeight: CGFloat = 86

    /// Where this character lives once it has arrived. `enter()` animates to it
    /// from the top of the screen, so the resting place has to outlive the frame.
    private let restingOrigin: NSPoint
    /// Staggered per slot so the crew arrives one after another, not in a rank.
    private let entranceSeconds: TimeInterval
    private static let entranceBase: TimeInterval = 0.85

    init(role: String, videoURL: URL, originX: CGFloat, originY: CGFloat,
         mirrored: Bool = false, slot: Int = 0) {
        self.role = role
        self.restingOrigin = NSPoint(x: originX, y: originY)
        self.entranceSeconds = Self.entranceBase + Double(slot) * 0.18

        let height = Self.charHeight + Self.bubbleHeight
        window = NSWindow(contentRect: NSRect(x: originX, y: originY, width: Self.width, height: height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true          // never steal a click during the demo
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
        content.wantsLayer = true
        window.contentView = content

        // AgentCharacter video, centred at the bottom. Source is 1080x1920 portrait.
        let vidWidth = Self.charHeight * (1080.0 / 1920.0)
        player = AVQueuePlayer()
        player.isMuted = true
        let item = AVPlayerItem(url: videoURL)
        looper = AVPlayerLooper(player: player, templateItem: item)
        videoLayer = AVPlayerLayer(player: player)
        videoLayer.frame = CGRect(x: (Self.width - vidWidth) / 2, y: 0, width: vidWidth, height: Self.charHeight)
        videoLayer.videoGravity = .resizeAspect
        // Upstream ships two walk loops for three roles, so triage and recap were
        // the same sprite twice. Mirroring one of them costs nothing and stops
        // the audience seeing the same character in two places at once.
        if mirrored { videoLayer.transform = CATransform3DMakeScale(-1, 1, 1) }
        content.layer?.addSublayer(videoLayer)

        bubble = BubbleView(frame: NSRect(x: 0, y: Self.charHeight - 6, width: Self.width, height: Self.bubbleHeight))
        content.addSubview(bubble)

        window.alphaValue = 0
        window.orderFrontRegardless()
    }

    /// Playback rate per state. There are only two walk loops upstream and three
    /// characters, so state has to read as *tempo* rather than as a new clip:
    /// an amble while waiting, a brisk walk while working, an easy one once the
    /// job is done. Same asset, three legible behaviours.
    private static func rate(for state: String) -> Float {
        switch state {
        case "idle": return 0.55   // barely moving — waiting to be given something
        case "done": return 0.70   // still walking, just unhurried
        default:     return 1.15   // working: a shade faster than natural
        }
    }

    /// How long a `working` character may go without a new line before it starts
    /// visibly thinking. Lines land on a ~2.2s beat, so 10s is comfortably past
    /// "the next one is coming" and well short of the orchestrator's 180s kill.
    private static let thinkingAfter: TimeInterval = 10
    /// Slower than `idle` — a character mulling something over, not walking off.
    private static let thinkingRate: Float = 0.40

    private var currentMessage = ""
    private var currentState = "idle"
    private var lastLineAt = Date()
    private var thinking = false
    private var ellipsisTick = 0
    /// Set from `characters.json` via the POST's `activity`, when there is one.
    private var activityRate: Float?

    /// The single place tempo is decided, so thinking, state and activity can
    /// never disagree about how fast the character should be walking.
    private func desiredRate() -> Float {
        if thinking { return Self.thinkingRate }
        if currentState == "working", let r = activityRate { return r }
        return Self.rate(for: currentState)
    }

    func apply(message: String, state: String, activityRate: Float? = nil) {
        self.activityRate = activityRate
        let waking = window.alphaValue == 0
        if waking { enter() }
        currentMessage = message
        currentState = state
        lastLineAt = Date()
        if thinking {
            thinking = false
            FileHandle.standardError.write(Data("THINK <- \(role) resumed\n".utf8))
        }
        bubble.set(text: message, done: state == "done")

        // NEVER pause. Pausing on "done" froze the character mid-stride, and
        // because two agents finish long before the recap does, most of the show
        // was played to a screen of statues. A frozen character reads as a
        // crashed app — which is exactly the impression the dock exists to avoid.
        //
        // play() first: setting `rate` alone is ignored while the item is still
        // getting ready, which is exactly the case on the very first line.
        player.play()
        player.rate = desiredRate()

        // A real line just arrived: bob, so the character reads as *saying* it
        // rather than as a walking sprite that happens to have a caption.
        if !message.isEmpty && message != "waking up" { bob() }
    }

    /// Called ~4x/second by the dock. Turns "nothing has arrived for a while"
    /// into something the audience can read.
    ///
    /// A stuck agent and a healthy one looked identical: both walked briskly
    /// under a caption that had stopped changing. On stage that is the worst
    /// possible ambiguity — the audience cannot tell a crash from a pause, so
    /// they assume the crash. A character that slows down and trails an ellipsis
    /// reads as *thinking*, which is both honest and survivable. It says nothing
    /// new, because the dock genuinely knows nothing new.
    func tick(_ now: Date) {
        // Only `working` can stall. `done` is finished and `idle` has not been
        // handed anything yet — neither is waiting on a line that isn't coming.
        guard currentState == "working", window.alphaValue > 0 else { return }

        if now.timeIntervalSince(lastLineAt) >= Self.thinkingAfter {
            if !thinking {
                thinking = true
                ellipsisTick = 0
                FileHandle.standardError.write(Data(
                    "THINK -> \(role) — no line for \(Int(Self.thinkingAfter))s\n".utf8))
            }
            ellipsisTick += 1
            // One dot every ~0.5s, cycling 1→2→3.
            bubble.setText(currentMessage + " " + String(repeating: ".", count: 1 + (ellipsisTick / 2) % 3))
        }

        // Re-assert tempo rather than trusting it to persist: `rate` is a
        // property of the player, and an AVPlayerLooper swaps the item under it
        // on every loop. Cheap, and it keeps the state legible for a whole run.
        let want = desiredRate()
        if player.rate != want { player.rate = want }
    }

    /// The characters arrive by dropping out of the top of the screen and walking
    /// down to their place above the dock, instead of fading in already there.
    ///
    /// It reads as the crew coming out of the machine rather than as three
    /// windows appearing, and it gives the audience something to watch during the
    /// second or two before the first agent has anything to say — which used to
    /// be dead air right at the open. Staggered per character so they arrive as a
    /// crew rather than a rank.
    ///
    /// Position is animated on the window itself: these are borderless
    /// click-through windows, so there is no layout to fight.
    private func enter() {
        let drop = restingOrigin
        var start = drop
        start.y = (window.screen ?? NSScreen.main)?.frame.maxY ?? drop.y + 900
        window.setFrameOrigin(start)
        window.alphaValue = 1
        player.play()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = entranceSeconds
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(drop)
        }
    }

    /// One small hop, on the layer so it costs nothing and can't fight AppKit.
    private func bob() {
        let hop = CABasicAnimation(keyPath: "position.y")
        hop.fromValue = videoLayer.position.y
        hop.toValue = videoLayer.position.y + 7
        hop.duration = 0.16
        hop.autoreverses = true
        hop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        videoLayer.add(hop, forKey: "bob")
    }

    func reset() {
        window.alphaValue = 0
        player.pause()
        bubble.set(text: "", done: false)
    }
}

/// Rounded speech bubble with a tail. Drawn by hand so the app needs no assets
/// beyond the character videos.
final class BubbleView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var done = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.frame = NSRect(x: 16, y: 16, width: frame.width - 32, height: frame.height - 26)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .black
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        label.alignment = .center
        label.cell?.wraps = true
        addSubview(label)
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(text: String, done: Bool) {
        self.done = done
        label.stringValue = text
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().alphaValue = text.isEmpty ? 0 : 1
        }
    }

    /// Text only, no fade. The ellipsis updates twice a second and re-running
    /// the fade-in that often makes the bubble shimmer.
    func setText(_ text: String) {
        label.stringValue = text
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !label.stringValue.isEmpty else { return }
        let box = NSRect(x: 8, y: 10, width: bounds.width - 16, height: bounds.height - 16)
        let path = NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14)

        // little tail pointing down at the character
        let tail = NSBezierPath()
        let cx = bounds.midX
        tail.move(to: NSPoint(x: cx - 9, y: box.minY + 1))
        tail.line(to: NSPoint(x: cx, y: box.minY - 10))
        tail.line(to: NSPoint(x: cx + 9, y: box.minY + 1))
        tail.close()
        path.append(tail)

        (done ? NSColor(calibratedRed: 0.80, green: 0.94, blue: 0.82, alpha: 0.97)
              : NSColor(calibratedWhite: 1.0, alpha: 0.97)).setFill()
        path.fill()
        NSColor(calibratedWhite: 0, alpha: 0.10).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
