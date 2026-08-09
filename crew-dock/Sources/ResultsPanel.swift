import AppKit

/// A receipt, at the top of the screen, filling in as each agent signs off.
///
/// The speech bubbles are transient by design — they show the line a character
/// is saying right now and then move on. So at the end of a run the audience has
/// heard everything and can see almost none of it, and the one question a person
/// actually has ("what did it DO?") has no answer on screen.
///
/// This holds only the `Done:` lines: one row per agent, kept until the next
/// run. It stays out of the characters' way in the top centre, while they work
/// the corners.
final class ResultsPanel {
    private let window: NSWindow
    private let stack = NSStackView()
    private let title = NSTextField(labelWithString: "")
    private var rows: [String: NSTextField] = [:]

    static let width: CGFloat = 560

    init(screen: NSScreen) {
        let vf = screen.visibleFrame
        // Below the character row, not inside it. The crew stands across the top
        // and a five-agent run reaches the middle, so a panel centred at the very
        // top sat underneath two of them. This keeps the whole thing in the upper
        // third and still clear of the terminal.
        let top = vf.maxY - AgentCharacter.totalHeight - 6
        let frame = NSRect(x: vf.midX - Self.width / 2, y: top - 190,
                           width: Self.width, height: 190)
        window = NSWindow(contentRect: frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let card = CardView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = card

        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = NSColor.secondaryLabelColor
        title.stringValue = ""

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
        ])
        stack.addArrangedSubview(title)

        window.alphaValue = 0
        window.orderFrontRegardless()
    }

    /// What the person asked for, shown while the crew works on it.
    func askedFor(_ text: String) {
        clear()
        title.stringValue = "“" + text + "”"
        show()
    }

    /// One agent has finished. Its sign-off joins the receipt.
    ///
    /// `Done:` is stripped — it is a marker for the orchestrator, not something
    /// a reader needs, and every row starting with the same word is noise.
    func finished(role: String, line: String) {
        let text = line.replacingOccurrences(of: "Done:", with: "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let existing = rows[role] { existing.stringValue = "✓  " + text; return }

        let label = NSTextField(labelWithString: "✓  " + text)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rows[role] = label
        stack.addArrangedSubview(label)
        label.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            label.animator().alphaValue = 1
        }
        show()
    }

    func clear() {
        rows.values.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        title.stringValue = ""
    }

    private func show() {
        guard window.alphaValue == 0 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            window.animator().alphaValue = 1
        }
    }
}

/// Rounded translucent card, drawn rather than themed, so it reads the same on
/// any wallpaper and needs no assets.
private final class CardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 6, dy: 6)
        let path = NSBezierPath(roundedRect: box, xRadius: 16, yRadius: 16)
        NSColor(calibratedWhite: 0.09, alpha: 0.93).setFill()
        path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
