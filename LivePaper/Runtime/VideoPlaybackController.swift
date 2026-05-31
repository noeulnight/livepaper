import AVFoundation
import AppKit

@MainActor
final class VideoPlaybackAttachment {
    let displayID: DisplayID
    let groupKey: String
    weak var contentView: NSView?
    fileprivate let layer: AVPlayerLayer

    var player: AVPlayer? {
        layer.player
    }

    init(displayID: DisplayID, groupKey: String, contentView: NSView, layer: AVPlayerLayer) {
        self.displayID = displayID
        self.groupKey = groupKey
        self.contentView = contentView
        self.layer = layer
    }
}

@MainActor
final class SharedVideoPlaybackGroup {
    private struct Member {
        var config: WallpaperConfig
        var layer: AVPlayerLayer
        var isPaused: Bool
    }

    let key: String
    private let player: AVQueuePlayer
    private let looper: AVPlayerLooper
    private var members: [DisplayID: Member] = [:]
    private var audioOwnerDisplayID: DisplayID?

    init(key: String, config: WallpaperConfig) {
        self.key = key

        let item = AVPlayerItem(url: config.content.url)
        let player = AVQueuePlayer()
        player.allowsExternalPlayback = false
        self.player = player
        self.looper = AVPlayerLooper(player: player, templateItem: item)
    }

    var isEmpty: Bool {
        members.isEmpty
    }

    func attach(config: WallpaperConfig, in contentView: NSView) -> VideoPlaybackAttachment {
        detach(displayID: config.displayID)

        contentView.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.frame = contentView.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.videoGravity = config.scaleMode.videoGravity
        layer.isHidden = false
        contentView.layer?.addSublayer(layer)

        members[config.displayID] = Member(config: config, layer: layer, isPaused: false)
        updatePlayback()
        return VideoPlaybackAttachment(
            displayID: config.displayID,
            groupKey: key,
            contentView: contentView,
            layer: layer
        )
    }

    func apply(config: WallpaperConfig, attachment: VideoPlaybackAttachment) {
        guard var member = members[attachment.displayID] else {
            return
        }

        member.config = config
        member.layer.videoGravity = config.scaleMode.videoGravity
        members[attachment.displayID] = member
        updatePlayback()
    }

    func pause(displayID: DisplayID) {
        guard var member = members[displayID] else {
            return
        }

        member.isPaused = true
        member.layer.isHidden = true
        members[displayID] = member
        updatePlayback()
    }

    func resume(displayID: DisplayID) {
        guard var member = members[displayID] else {
            return
        }

        member.isPaused = false
        member.layer.isHidden = false
        members[displayID] = member
        updatePlayback()
    }

    func detach(displayID: DisplayID) {
        if let member = members.removeValue(forKey: displayID) {
            member.layer.player = nil
            member.layer.removeFromSuperlayer()
        }
        updatePlayback()
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        for member in members.values {
            member.layer.player = nil
            member.layer.removeFromSuperlayer()
        }
        members.removeAll()
    }

    func updateAudioOwner(_ displayID: DisplayID?) {
        audioOwnerDisplayID = displayID
        updatePlayback()
    }

    private func updatePlayback() {
        let activeMembers = members
            .filter { !$0.value.isPaused }
            .sorted { $0.key.uuid < $1.key.uuid }

        guard !activeMembers.isEmpty else {
            player.pause()
            return
        }

        let audioMember = audioOwnerDisplayID
            .flatMap { members[$0] }
            .flatMap { $0.isPaused ? nil : $0 }
            ?? activeMembers.first(where: { !$0.value.config.muted })?.value
            ?? activeMembers[0].value

        player.isMuted = audioMember.config.muted
        player.volume = Float(max(0, min(audioMember.config.volume, 1)))
        player.play()
    }
}
