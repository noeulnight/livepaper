import AppKit
import Foundation

@MainActor
final class MusicWallpaperController {
    private var view: MusicWallpaperView?
    private var subscription: NowPlayingAlbumSubscription?
    private var currentIdentity: String?
    private var currentConfig: WallpaperConfig?
    private let monitor: NowPlayingAlbumMonitoring

    init(monitor: NowPlayingAlbumMonitoring? = nil) {
        self.monitor = monitor ?? AppleScriptNowPlayingMonitor.shared
    }

    func start(config: WallpaperConfig, in contentView: NSView) {
        stop()

        let musicView = MusicWallpaperView(frame: contentView.bounds, style: config.musicStyle)
        musicView.autoresizingMask = [.width, .height]
        contentView.addSubview(musicView)
        view = musicView
        currentConfig = config

        let source = config.content.musicSource ?? .appleMusic
        musicView.showPlaceholder(title: "Music Sync", subtitle: "Waiting for playback")
        subscribe(to: source)
    }

    func pause() {
        view?.pauseBackgroundSpin()
    }

    func resume() {
        view?.isHidden = false
        view?.resumeBackgroundSpin()
    }

    func apply(config: WallpaperConfig) {
        guard currentConfig?.content.musicSource == config.content.musicSource else {
            guard let superview = view?.superview else {
                return
            }
            start(config: config, in: superview)
            return
        }

        let previousStyle = currentConfig?.musicStyle
        currentConfig = config
        if previousStyle != config.musicStyle {
            view?.style = config.musicStyle
        }
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
        view?.removeFromSuperview()
        view = nil
        currentIdentity = nil
        currentConfig = nil
    }

    private func subscribe(to source: WallpaperContent.MusicSource) {
        subscription?.cancel()
        subscription = monitor.subscribe(source: source) { [weak self] snapshot in
            Task {
                await self?.refresh(snapshot: snapshot)
            }
        }
    }

    private func refresh(snapshot: NowPlayingAlbumSnapshot?) async {
        guard let view else {
            return
        }

        guard let snapshot else {
            view.showPlaceholder(title: "Music Sync", subtitle: "Waiting for playback")
            currentIdentity = nil
            return
        }

        if snapshot.identity == currentIdentity {
            view.updateText(snapshot: snapshot)
            return
        }

        currentIdentity = snapshot.identity
        let image = await image(for: snapshot)
        view.update(snapshot: snapshot, artwork: image)
    }

    private func image(for snapshot: NowPlayingAlbumSnapshot) async -> NSImage? {
        if let artworkFileURL = snapshot.artworkFileURL {
            return NSImage(contentsOf: artworkFileURL)
        }

        guard let artworkURL = snapshot.artworkURL else {
            return nil
        }

        guard let (data, _) = try? await URLSession.shared.data(from: artworkURL) else {
            return nil
        }
        return NSImage(data: data)
    }
}
