import AppKit

@MainActor
final class InAppWallpaperRuntime: WallpaperRuntime {
    private var sessions: [DisplayID: ScreenSession] = [:]
    private var videoGroups: [String: SharedVideoPlaybackGroup] = [:]
    private var synchronizesMatchingWallpapers = true
    private var matchingWallpaperAudioLeaderDisplayID: DisplayID?

    func setMatchingWallpaperAudioLeader(_ displayID: DisplayID?) async {
        guard matchingWallpaperAudioLeaderDisplayID != displayID else {
            return
        }

        matchingWallpaperAudioLeaderDisplayID = displayID
        updateVideoGroupAudioOwners()
    }

    func setSynchronizesMatchingWallpapers(_ isEnabled: Bool) async {
        guard synchronizesMatchingWallpapers != isEnabled else {
            return
        }

        synchronizesMatchingWallpapers = isEnabled
        reattachVideoSessions()
    }

    func start(config: WallpaperConfig) async throws {
        let screen = try screen(for: config.displayID)
        let session = ScreenSession(config: config, screen: screen, videoGroups: self)
        sessions[config.displayID] = session
        session.start()
    }

    func stop(displayID: DisplayID) async {
        sessions[displayID]?.stop()
        sessions.removeValue(forKey: displayID)
    }

    func stopAll() async {
        for session in sessions.values {
            session.stop()
        }
        sessions.removeAll()
        stopVideoGroups()
    }

    func update(config: WallpaperConfig) async throws {
        if let session = sessions[config.displayID] {
            session.update(config: config)
        } else {
            try await start(config: config)
        }
    }

    func pause(displayID: DisplayID) async {
        sessions[displayID]?.pause()
    }

    func resume(displayID: DisplayID) async {
        sessions[displayID]?.resume()
    }

    private func screen(for displayID: DisplayID) throws -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.livePaperDisplayID == displayID }) {
            return screen
        }
        throw WallpaperRuntimeError.displayNotFound(displayID.uuid)
    }

    private func reattachVideoSessions() {
        stopVideoGroups()
        for session in sessions.values {
            session.reattachVideoIfNeeded()
        }
    }

    private func stopVideoGroups() {
        for group in videoGroups.values {
            group.stop()
        }
        videoGroups.removeAll()
    }

    private func updateVideoGroupAudioOwners() {
        for group in videoGroups.values {
            group.updateAudioOwner(matchingWallpaperAudioLeaderDisplayID)
        }
    }

    nonisolated static func synchronizationReferenceDisplayID(
        in displayIDs: [DisplayID],
        audioLeaderDisplayID: DisplayID?
    ) -> DisplayID? {
        if let audioLeaderDisplayID, displayIDs.contains(audioLeaderDisplayID) {
            return audioLeaderDisplayID
        }

        return displayIDs.first
    }
}

extension InAppWallpaperRuntime: VideoPlaybackGroupProviding {
    func attachVideo(config: WallpaperConfig, in contentView: NSView) -> VideoPlaybackAttachment? {
        guard let groupKey = videoGroupKey(for: config) else {
            return nil
        }

        let group = videoGroups[groupKey] ?? SharedVideoPlaybackGroup(key: groupKey, config: config)
        videoGroups[groupKey] = group
        let attachment = group.attach(config: config, in: contentView)
        group.updateAudioOwner(matchingWallpaperAudioLeaderDisplayID)
        return attachment
    }

    func applyVideo(
        config: WallpaperConfig,
        attachment: VideoPlaybackAttachment?
    ) -> VideoPlaybackAttachment? {
        guard let attachment,
              attachment.groupKey == videoGroupKey(for: config),
              let group = videoGroups[attachment.groupKey] else {
            detachVideo(attachment: attachment)
            guard let contentView = attachment?.contentView else {
                return nil
            }
            return attachVideo(config: config, in: contentView)
        }

        group.apply(config: config, attachment: attachment)
        group.updateAudioOwner(matchingWallpaperAudioLeaderDisplayID)
        return attachment
    }

    func pauseVideo(attachment: VideoPlaybackAttachment?) {
        guard let attachment,
              let group = videoGroups[attachment.groupKey] else {
            return
        }

        group.pause(displayID: attachment.displayID)
    }

    func resumeVideo(attachment: VideoPlaybackAttachment?) {
        guard let attachment,
              let group = videoGroups[attachment.groupKey] else {
            return
        }

        group.resume(displayID: attachment.displayID)
        group.updateAudioOwner(matchingWallpaperAudioLeaderDisplayID)
    }

    func detachVideo(attachment: VideoPlaybackAttachment?) {
        guard let attachment,
              let group = videoGroups[attachment.groupKey] else {
            return
        }

        group.detach(displayID: attachment.displayID)
        if group.isEmpty {
            group.stop()
            videoGroups.removeValue(forKey: attachment.groupKey)
        }
    }

    private func videoGroupKey(for config: WallpaperConfig) -> String? {
        guard let synchronizationID = config.content.videoSynchronizationID else {
            return nil
        }

        if synchronizesMatchingWallpapers {
            return synchronizationID
        }
        return "\(synchronizationID)#display:\(config.displayID.uuid)"
    }
}
