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

    /// Where this character lives once it has arrived, and the anchor its roam
    /// wanders around. `enter()` animates to it from the top of the screen, so
    /// the resting place has to outlive the frame. Settable because the crew is
    /// centred on however many members actually woke, not on however many the
    /// manifest lists — see `place(x:)`.
    private var restingOrigin: NSPoint
    /// Kept because walking flips the layer and must know the resting orientation.
    private let mirrored: Bool
    /// Staggered per slot so the crew arrives one after another, not in a rank.
    private let entranceSeconds: TimeInterval
    private static let entranceBase: TimeInterval = 0.85

    init(role: String, videoURL: URL, originX: CGFloat, originY: CGFloat,
         mirrored: Bool = false, slot: Int = 0) {
        self.role = role
        self.restingOrigin = NSPoint(x: originX, y: originY)
        self.mirrored = mirrored
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
        guard window.alphaValue > 0 else { return }

        // Walking is not conditional on state — a character that stops moving
        // the moment it finishes is the frozen-dock problem again, just later in
        // the run. Tempo already says what state it is in; position says it is
        // alive. `done` characters amble, they do not stand.
        walkTick()

        // Only `working` can stall. `done` is finished and `idle` has not been
        // handed anything yet — neither is waiting on a line that isn't coming.
        guard currentState == "working" else { return }

        if now.timeIntervalSince(lastLineAt) >= Self.thinkingAfter {
            if !thinking {
                thinking = true
                ellipsisTick = 0
                FileHandle.standardError.write(Data(
                    "THINK -> \(role) — no line for \(Int(Self.thinkingAfter))s\n".utf8))
            }
            // Time-based, not tick-based: the clock runs at 30Hz for movement
            // now, and a tick-counted ellipsis would flicker seven times too fast.
            let dots = 1 + Int(now.timeIntervalSince(lastLineAt) * 2) % 3
            bubble.setText(currentMessage + " " + String(repeating: ".", count: dots))
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
    /// Moves this character's stand-and-roam anchor.
    ///
    /// The manifest lists five roles but a run uses whichever subset the
    /// sentence asked for, so a fixed slot per manifest row leaves holes: the
    /// rehearsed three sat at slots 0, 1 and 4 of five — two bunched left with
    /// their bubbles overlapping and the recap stranded across the screen. The
    /// dock re-centres on the crew that actually woke instead.
    ///
    /// Before the entrance this only sets where it will walk to. After it, the
    /// character slides over — the orchestrator wakes every participant inside
    /// the first second, so in practice this happens before the show starts,
    /// and if a later member does join the others making room reads as crew.
    func place(x: CGFloat) {
        guard abs(restingOrigin.x - x) > 0.5 else { return }
        restingOrigin.x = x
        guard window.alphaValue > 0 else { return }   // not on stage yet
        let target = NSRect(origin: NSPoint(x: x, y: restingOrigin.y), size: window.frame.size)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.window.setFrame(target, display: true)
        })
    }

    /// click-through windows, so there is no layout to fight.
    private func enter() {
        let size = window.frame.size
        let resting = NSRect(origin: restingOrigin, size: size)
        var start = resting
        start.origin.y = (window.screen ?? NSScreen.main)?.frame.maxY ?? resting.origin.y + 900

        window.setFrame(start, display: false)
        window.alphaValue = 1
        player.play()

        // `setFrame(_:display:)` on the animator, NOT `setFrameOrigin`. Only
        // `frame` is animatable through the proxy — animating the origin is a
        // silent no-op, which parked every character above the top of the screen
        // and left the show audible but invisible. Exactly the failure mode this
        // project keeps producing: the logs were perfect and the stage was empty.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = entranceSeconds
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(resting, display: true)
        }, completionHandler: { [weak self] in
            // Land it exactly, in case the animation was interrupted — a
            // character a few points off is invisible at the screen edge.
            self?.window.setFrame(resting, display: true)
        })
    }

    // MARK: - Walking, ported from lil-agents' WalkerCharacter (MIT)
    //
    // The characters used to walk on the spot, which reads as a looping sprite
    // rather than someone crossing the room. Upstream's insight is that
    // translation must be driven by the *video's own* timeline, not by a
    // wall-clock tween: the clip has a stand, an acceleration, a cruise and a
    // stop, and if you move at a constant rate the feet slide against the floor.
    //
    // These are upstream's measurements of the shipped clip, in seconds.
    private static let accelStart: Double = 3.0     // stands still until here
    private static let fullSpeedStart: Double = 3.75
    private static let decelStart: Double = 7.5
    private static let walkStop: Double = 8.25      // stopped again after this

    /// Fraction of the walk covered by `t` seconds into the clip, 0...1.
    /// Trapezoid: ease in over `dIn`, cruise, ease out over `dOut`, normalised
    /// so the whole trip is exactly 1.
    private static func progress(atVideoTime t: Double) -> CGFloat {
        let dIn = fullSpeedStart - accelStart
        let dLin = decelStart - fullSpeedStart
        let dOut = walkStop - decelStart
        let v = 1.0 / (dIn / 2.0 + dLin + dOut / 2.0)
        if t <= accelStart { return 0 }
        if t <= fullSpeedStart { let x = t - accelStart; return CGFloat(v * x * x / (2 * dIn)) }
        if t <= decelStart { return CGFloat(v * dIn / 2 + v * (t - fullSpeedStart)) }
        if t <= walkStop {
            let x = t - decelStart
            return CGFloat(v * dIn / 2 + v * dLin + v * (x - x * x / (2 * dOut)))
        }
        return 1
    }

    private var walkFromX: CGFloat = 0
    private var walkToX: CGFloat = 0
    private var walking = false
    private var pauseUntil = Date.distantPast
    /// Player time at which the current walk began, so the trapezoid measures
    /// this walk rather than the whole session.
    private var walkStartVideoTime: Double = 0
    /// Loop length, for detecting a wrap mid-walk.
    private var clipSeconds: Double = 8.25
    /// How far either side of its slot a character may wander. Wide enough to
    /// read as walking, narrow enough that three of them never trade places —
    /// upstream keeps siblings apart at runtime; fixed lanes do it for free.
    private static let roam: CGFloat = 95

    private func walkTick() {
        guard window.alphaValue > 0 else { return }
        let t = player.currentTime().seconds
        guard t.isFinite else { return }

        // Elapsed within THIS walk, not the player's absolute clock. Using the
        // absolute time meant every walk after the first started already past
        // `walkStop`, completed instantly with zero distance, and the crew
        // simply stopped moving after one step. AVPlayerLooper restarts the item
        // underneath us, so a negative delta means the clip wrapped mid-walk.
        var elapsed = t - walkStartVideoTime
        if elapsed < 0 { elapsed += max(clipSeconds, 0.001) }

        if !walking {
            // Between walks the character stands. Upstream pauses 5-12s; ours
            // are on stage for ~45s, so a shorter beat keeps them alive without
            // turning the dock into a screensaver.
            guard Date() >= pauseUntil else { return }
            let here = window.frame.origin.x
            let low = restingOrigin.x - Self.roam, high = restingOrigin.x + Self.roam
            // Turn around at the edge of the lane, otherwise pick a side.
            let goRight = here <= low ? true : (here >= high ? false : Bool.random())
            let dist = CGFloat.random(in: 60...Self.roam)
            walkFromX = here
            walkToX = min(max(goRight ? here + dist : here - dist, low), high)
            walking = true
            walkStartVideoTime = t
            if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { clipSeconds = d }
            // Face the way we are going. The mirrored roles are flipped to begin
            // with, so "forward" for them is the other transform.
            let faceRight = goRight != mirrored
            videoLayer.transform = faceRight ? CATransform3DIdentity : CATransform3DMakeScale(-1, 1, 1)
        }

        let p = Self.progress(atVideoTime: elapsed)
        var f = window.frame
        f.origin.x = walkFromX + (walkToX - walkFromX) * p
        window.setFrameOrigin(f.origin)

        if p >= 1 {
            walking = false
            pauseUntil = Date().addingTimeInterval(Double.random(in: 1.5...4.0))
        }
    }

    /// Walk off the top of the screen and stand down.
    ///
    /// The reverse of `enter()`, and it exists because the end of the show was
    /// the weakest moment in it: five characters stood in a row under stale
    /// bubbles until somebody hit ctrl-C. Sending the crew away leaves the one
    /// who spoke last alone on screen with the summary — which is the thing the
    /// audience should be reading — and it makes the run feel finished rather
    /// than merely stopped.
    ///
    /// Resets to `alpha 0` at its resting place afterwards, so the next `⌃⌥C`
    /// gets a clean entrance instead of a character sliding in from wherever it
    /// happened to be.
    func leave() {
        guard window.alphaValue > 0, !leaving else { return }
        leaving = true
        walking = false
        bubble.set(text: "", done: false)

        var away = window.frame
        away.origin.y = (window.screen ?? NSScreen.main)?.frame.maxY ?? away.origin.y + 900
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(away, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.window.alphaValue = 0
            self.window.setFrame(NSRect(origin: self.restingOrigin, size: self.window.frame.size),
                                 display: false)
            self.currentState = "idle"
            self.leaving = false
        })
    }

    /// True once every line has landed and this character has signed off.
    var isDone: Bool { currentState == "done" && window.alphaValue > 0 }
    var isOnScreen: Bool { window.alphaValue > 0 }
    private var leaving = false

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
