import AppKit
import Foundation

@MainActor
final class MusicWallpaperController {
    private static let refreshInterval: Duration = .seconds(2)

    private var view: MusicWallpaperView?
    private var provider: NowPlayingAlbumProviding?
    private var refreshTask: Task<Void, Never>?
    private var currentIdentity: String?
    private var currentConfig: WallpaperConfig?

    func start(config: WallpaperConfig, in contentView: NSView) {
        stop()

        let musicView = MusicWallpaperView(frame: contentView.bounds, style: config.musicStyle)
        musicView.autoresizingMask = [.width, .height]
        contentView.addSubview(musicView)
        view = musicView
        currentConfig = config

        let source = config.content.musicSource ?? .appleMusic
        provider = AppleScriptNowPlayingProvider(source: source)
        musicView.showPlaceholder(title: "Music Sync", subtitle: "Waiting for playback")
        startRefreshLoop()
    }

    func pause() {
        view?.pauseBackgroundSpin()
    }

    func resume() {
        view?.isHidden = false
        view?.resumeBackgroundSpin()
        startRefreshLoop()
    }

    func apply(config: WallpaperConfig) {
        guard currentConfig?.content.musicSource == config.content.musicSource else {
            guard let superview = view?.superview else {
                return
            }
            start(config: config, in: superview)
            return
        }

        currentConfig = config
        view?.style = config.musicStyle
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        view?.removeFromSuperview()
        view = nil
        provider = nil
        currentIdentity = nil
        currentConfig = nil
    }

    private func startRefreshLoop() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else {
                    return
                }
                await self?.refresh()
            }
        }
    }

    private func refresh() async {
        guard let provider, let view else {
            return
        }

        guard let snapshot = await provider.currentAlbum() else {
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
