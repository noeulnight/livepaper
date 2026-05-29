import AppKit

@MainActor
final class WallpaperWindow {
    let contentView: NSView
    private let window: NSWindow

    init(screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        contentView.wantsLayer = true
        contentView.layer = CALayer()
        window.contentView = contentView
        window.setFrame(screen.frame, display: true)

        self.window = window
        self.contentView = contentView
    }

    func showBehindDesktopIcons() {
        window.orderBack(nil)
    }

    func hide() {
        window.orderOut(nil)
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}
