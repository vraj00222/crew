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

    init(role: String, videoURL: URL, originX: CGFloat, originY: CGFloat) {
        self.role = role

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
        content.layer?.addSublayer(videoLayer)

        bubble = BubbleView(frame: NSRect(x: 0, y: Self.charHeight - 6, width: Self.width, height: Self.bubbleHeight))
        content.addSubview(bubble)

        window.alphaValue = 0
        window.orderFrontRegardless()
    }

    func apply(message: String, state: String) {
        let waking = window.alphaValue == 0
        if waking {
            player.play()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.45
                window.animator().alphaValue = 1
            }
        }
        bubble.set(text: message, done: state == "done")
        if state == "done" { player.pause() } else { player.play() }
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
