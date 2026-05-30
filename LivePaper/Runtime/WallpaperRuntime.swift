protocol WallpaperRuntime: AnyObject {
    func setMatchingWallpaperAudioLeader(_ displayID: DisplayID?) async
    func setSynchronizesMatchingWallpapers(_ isEnabled: Bool) async
    func start(config: WallpaperConfig) async throws
    func stop(displayID: DisplayID) async
    func stopAll() async
    func update(config: WallpaperConfig) async throws
    func pause(displayID: DisplayID) async
    func resume(displayID: DisplayID) async
}
