import AVFoundation
import AppKit

struct VideoPlaybackSyncSnapshot {
    let time: CMTime
}

@MainActor
final class VideoPlaybackController: NSObject {
    private static let synchronizationThreshold = 0.08

    private var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var looper: AVPlayerLooper?

    func start(config: WallpaperConfig, in contentView: NSView) {
        stop()

        let item = AVPlayerItem(url: config.content.url)
        let player = AVQueuePlayer()
        let looper = AVPlayerLooper(player: player, templateItem: item)
        player.allowsExternalPlayback = false
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = contentView.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.videoGravity = config.scaleMode.videoGravity
        playerLayer.isHidden = false

        contentView.layer?.addSublayer(playerLayer)

        player.isMuted = config.muted
        player.volume = Float(max(0, min(config.volume, 1)))
        self.player = player
        self.playerLayer = playerLayer
        self.looper = looper

        player.play()
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        playerLayer?.isHidden = false
        player?.play()
    }

    func apply(config: WallpaperConfig) {
        playerLayer?.videoGravity = config.scaleMode.videoGravity
        player?.isMuted = config.muted
        player?.volume = Float(max(0, min(config.volume, 1)))
    }

    var synchronizationSnapshot: VideoPlaybackSyncSnapshot? {
        guard let player else {
            return nil
        }

        let time = player.currentTime()
        guard time.isValid, !time.isIndefinite, CMTimeGetSeconds(time).isFinite else {
            return nil
        }
        return VideoPlaybackSyncSnapshot(time: time)
    }

    func synchronizeTimeline(to snapshot: VideoPlaybackSyncSnapshot) {
        guard let player else {
            return
        }

        let currentSeconds = CMTimeGetSeconds(player.currentTime())
        let targetSeconds = CMTimeGetSeconds(snapshot.time)
        guard currentSeconds.isFinite, targetSeconds.isFinite else {
            return
        }
        guard abs(currentSeconds - targetSeconds) > Self.synchronizationThreshold else {
            return
        }

        player.seek(to: snapshot.time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player?.pause()
        player?.removeAllItems()
        playerLayer?.removeFromSuperlayer()
        looper = nil
        self.playerLayer = nil
        self.player = nil
    }
}
