import Foundation

@MainActor
final class WallpaperRuntimeController {
    private let runtime: WallpaperRuntime

    private(set) var activeConfigs: [DisplayID: WallpaperConfig] = [:]
    private(set) var pausedDisplayIDs: Set<DisplayID> = []

    init(runtime: WallpaperRuntime) {
        self.runtime = runtime
    }

    func removePausedDisplay(_ displayID: DisplayID) {
        pausedDisplayIDs.remove(displayID)
    }

    func intersectPausedDisplays(with displayIDs: Set<DisplayID>) {
        pausedDisplayIDs.formIntersection(displayIDs)
    }

    func stopAll() async {
        await runtime.stopAll()
        activeConfigs.removeAll()
        pausedDisplayIDs.removeAll()
    }

    func stop(displayID: DisplayID) async {
        await runtime.stop(displayID: displayID)
        activeConfigs.removeValue(forKey: displayID)
        pausedDisplayIDs.remove(displayID)
    }

    func pause(displayID: DisplayID) async {
        await runtime.pause(displayID: displayID)
        pausedDisplayIDs.insert(displayID)
    }

    func update(config: WallpaperConfig) async throws {
        try await runtime.update(config: config)
    }

    func applyRuntimeConfigs(
        _ desiredConfigs: [DisplayID: WallpaperConfig],
        audioOwnerID: DisplayID?,
        fullscreenDisplayIDs: Set<DisplayID>,
        pausedDisplayIDs: Set<DisplayID>? = nil,
        orderedDisplayIDs: (Set<DisplayID>) -> [DisplayID]
    ) async throws {
        let pausedDisplayIDs = pausedDisplayIDs ?? []

        for displayID in orderedDisplayIDs(Set(desiredConfigs.keys)) {
            guard let config = desiredConfigs[displayID] else {
                continue
            }

            if pausedDisplayIDs.contains(displayID) {
                await runtime.pause(displayID: displayID)
                self.pausedDisplayIDs.insert(displayID)
                continue
            }

            try await runtime.update(
                config: Self.runtimeConfig(
                    from: config,
                    audioOwnerID: audioOwnerID,
                    fullscreenDisplayIDs: fullscreenDisplayIDs
                )
            )
            self.pausedDisplayIDs.remove(displayID)
        }

        activeConfigs = desiredConfigs
    }

    static func desiredConfig(
        displayID: DisplayID,
        content: WallpaperContent,
        scaleMode: ScaleMode,
        volume: Double,
        muted: Bool,
        pauseOnBattery: Bool,
        pauseOnFullscreen: Bool,
        muteOnFullscreen: Bool
    ) -> WallpaperConfig {
        WallpaperConfig(
            displayID: displayID,
            content: content,
            scaleMode: scaleMode,
            volume: volume,
            muted: muted,
            pauseOnBattery: pauseOnBattery,
            pauseOnFullscreen: pauseOnFullscreen,
            muteOnFullscreen: muteOnFullscreen
        )
    }

    static func desiredConfig(from savedConfig: SavedWallpaperConfig) -> WallpaperConfig {
        desiredConfig(
            displayID: savedConfig.displayID,
            content: savedConfig.content,
            scaleMode: savedConfig.scaleMode,
            volume: savedConfig.volume,
            muted: savedConfig.muted,
            pauseOnBattery: savedConfig.pauseOnBattery,
            pauseOnFullscreen: savedConfig.pauseOnFullscreen,
            muteOnFullscreen: savedConfig.muteOnFullscreen
        )
    }

    static func savedConfig(from config: WallpaperConfig) -> SavedWallpaperConfig {
        SavedWallpaperConfig(
            displayID: config.displayID,
            content: config.content,
            scaleMode: config.scaleMode,
            volume: config.volume,
            muted: config.muted,
            pauseOnBattery: config.pauseOnBattery,
            pauseOnFullscreen: config.pauseOnFullscreen,
            muteOnFullscreen: config.muteOnFullscreen
        )
    }

    static func runtimeConfig(
        from config: WallpaperConfig,
        audioOwnerID: DisplayID?,
        fullscreenDisplayIDs: Set<DisplayID>
    ) -> WallpaperConfig {
        desiredConfig(
            displayID: config.displayID,
            content: config.content,
            scaleMode: config.scaleMode,
            volume: config.volume,
            muted: shouldMute(config: config, audioOwnerID: audioOwnerID, fullscreenDisplayIDs: fullscreenDisplayIDs),
            pauseOnBattery: config.pauseOnBattery,
            pauseOnFullscreen: config.pauseOnFullscreen,
            muteOnFullscreen: config.muteOnFullscreen
        )
    }

    static func shouldMute(
        config: WallpaperConfig,
        audioOwnerID: DisplayID?,
        fullscreenDisplayIDs: Set<DisplayID>
    ) -> Bool {
        config.muted
            || audioOwnerID != config.displayID
            || (config.muteOnFullscreen && fullscreenDisplayIDs.contains(config.displayID))
    }
}
