import AppKit

@MainActor
final class DisplayHighlighter {
    static let shared = DisplayHighlighter()

    private var windows: [DisplayID: NSWindow] = [:]
    private var highlightTokens: [DisplayID: UUID] = [:]

    private init() {}

    func highlight(displayID: DisplayID, duration: TimeInterval? = 1.4) {
        guard let screen = NSScreen.screens.first(where: { $0.livePaperDisplayID == displayID }) else {
            return
        }

        let token = UUID()
        highlightTokens[displayID] = token

        windows[displayID]?.close()

        let window = makeWindow(screen: screen)
        windows[displayID] = window
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }

        guard let duration else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak window] in
            Task { @MainActor [weak self, weak window] in
                guard let self, self.highlightTokens[displayID] == token, let window else {
                    return
                }
                self.fadeOut(window: window, displayID: displayID, token: token)
            }
        }
    }

    func hide(displayID: DisplayID) {
        highlightTokens[displayID] = nil

        guard let window = windows[displayID] else {
            return
        }

        windows[displayID] = nil
        window.close()
    }

    private func makeWindow(screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.isReleasedWhenClosed = false

        window.contentView = DisplayHighlightView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.setFrame(screen.frame, display: true)
        return window
    }

    private func fadeOut(window: NSWindow, displayID: DisplayID, token: UUID) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor [weak self, weak window] in
                guard let self, self.highlightTokens[displayID] == token else {
                    return
                }
                window?.close()
                self.windows[displayID] = nil
                self.highlightTokens[displayID] = nil
            }
        }
    }
}

private final class DisplayHighlightView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let glowWidth = min(max(bounds.width, bounds.height) * 0.07, 110)
        let blue = NSColor.systemBlue.cgColor
        let clearBlue = NSColor.systemBlue.withAlphaComponent(0).cgColor

        drawGradient(
            in: context,
            colors: [blue.copy(alpha: 0.34) ?? blue, clearBlue],
            start: CGPoint(x: bounds.midX, y: bounds.maxY),
            end: CGPoint(x: bounds.midX, y: bounds.maxY - glowWidth),
            clip: NSRect(x: bounds.minX, y: bounds.maxY - glowWidth, width: bounds.width, height: glowWidth)
        )
        drawGradient(
            in: context,
            colors: [blue.copy(alpha: 0.34) ?? blue, clearBlue],
            start: CGPoint(x: bounds.midX, y: bounds.minY),
            end: CGPoint(x: bounds.midX, y: bounds.minY + glowWidth),
            clip: NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: glowWidth)
        )
        drawGradient(
            in: context,
            colors: [blue.copy(alpha: 0.3) ?? blue, clearBlue],
            start: CGPoint(x: bounds.minX, y: bounds.midY),
            end: CGPoint(x: bounds.minX + glowWidth, y: bounds.midY),
            clip: NSRect(x: bounds.minX, y: bounds.minY, width: glowWidth, height: bounds.height)
        )
        drawGradient(
            in: context,
            colors: [blue.copy(alpha: 0.3) ?? blue, clearBlue],
            start: CGPoint(x: bounds.maxX, y: bounds.midY),
            end: CGPoint(x: bounds.maxX - glowWidth, y: bounds.midY),
            clip: NSRect(x: bounds.maxX - glowWidth, y: bounds.minY, width: glowWidth, height: bounds.height)
        )
    }

    private func drawGradient(
        in context: CGContext,
        colors: [CGColor],
        start: CGPoint,
        end: CGPoint,
        clip: NSRect
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 1]
        ) else {
            return
        }

        context.saveGState()
        context.clip(to: clip)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }
}
