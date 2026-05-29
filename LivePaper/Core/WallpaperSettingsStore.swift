import Foundation

@MainActor
final class WallpaperSettingsStore {
    private enum Keys {
        static let configs = "wallpaper.configs"
        static let library = "wallpaper.library"
        static let scaleMode = "wallpaper.scaleMode"
        static let muted = "wallpaper.muted"
        static let volume = "wallpaper.volume"
        static let audioDisplayID = "wallpaper.audioDisplayID"
        static let pauseOnBattery = "wallpaper.pauseOnBattery"
        static let pauseOnFullscreen = "wallpaper.pauseOnFullscreen"
        static let muteOnFullscreen = "wallpaper.muteOnFullscreen"
        static let steamCMDPath = "steam.steamCMDPath"
        static let steamCMDBookmark = "steam.steamCMDBookmark"
        static let steamCMDLoginMode = "steam.loginMode"
        static let steamUsername = "steam.username"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRuntimePreferences() -> RuntimePreferences {
        RuntimePreferences(
            scaleMode: ScaleMode(rawValue: defaults.string(forKey: Keys.scaleMode) ?? "") ?? .fill,
            muted: defaults.object(forKey: Keys.muted) as? Bool ?? false,
            volume: defaults.object(forKey: Keys.volume) as? Double ?? 1,
            audioDisplayID: defaults.string(forKey: Keys.audioDisplayID).map(DisplayID.init(uuid:)),
            pauseOnBattery: defaults.object(forKey: Keys.pauseOnBattery) as? Bool ?? true,
            pauseOnFullscreen: defaults.object(forKey: Keys.pauseOnFullscreen) as? Bool ?? true,
            muteOnFullscreen: defaults.object(forKey: Keys.muteOnFullscreen) as? Bool ?? false
        )
    }

    func saveRuntimePreferences(_ preferences: RuntimePreferences) {
        defaults.set(preferences.scaleMode.rawValue, forKey: Keys.scaleMode)
        defaults.set(preferences.muted, forKey: Keys.muted)
        defaults.set(preferences.volume, forKey: Keys.volume)
        if let audioDisplayID = preferences.audioDisplayID {
            defaults.set(audioDisplayID.uuid, forKey: Keys.audioDisplayID)
        } else {
            defaults.removeObject(forKey: Keys.audioDisplayID)
        }
        defaults.set(preferences.pauseOnBattery, forKey: Keys.pauseOnBattery)
        defaults.set(preferences.pauseOnFullscreen, forKey: Keys.pauseOnFullscreen)
        defaults.set(preferences.muteOnFullscreen, forKey: Keys.muteOnFullscreen)
    }

    func loadSavedConfigs() -> [DisplayID: SavedWallpaperConfig] {
        guard let data = defaults.data(forKey: Keys.configs),
              let configs = try? JSONDecoder().decode([SavedWallpaperConfig].self, from: data) else {
            return [:]
        }

        return Dictionary(
            uniqueKeysWithValues: configs.map {
                let resolvedConfig = SavedWallpaperConfig(
                    displayID: $0.displayID,
                    content: $0.content.resolvingSecurityScopedBookmarks(),
                    scaleMode: $0.scaleMode,
                    volume: $0.volume,
                    muted: $0.muted,
                    pauseOnBattery: $0.pauseOnBattery,
                    pauseOnFullscreen: $0.pauseOnFullscreen,
                    muteOnFullscreen: $0.muteOnFullscreen
                )
                return (resolvedConfig.displayID, resolvedConfig)
            }
        )
    }

    func save(configs: [DisplayID: SavedWallpaperConfig]) {
        let orderedConfigs = configs.values.sorted { $0.displayID.uuid < $1.displayID.uuid }
        guard let data = try? JSONEncoder().encode(orderedConfigs) else {
            return
        }
        defaults.set(data, forKey: Keys.configs)
    }

    func loadLibrary() -> [WallpaperContent] {
        guard let data = defaults.data(forKey: Keys.library),
              let contents = try? JSONDecoder().decode([WallpaperContent].self, from: data) else {
            return []
        }

        return contents.map { $0.resolvingSecurityScopedBookmarks() }
    }

    func save(library: [WallpaperContent]) {
        guard let data = try? JSONEncoder().encode(library) else {
            return
        }
        defaults.set(data, forKey: Keys.library)
    }

    func removeAllConfigs() {
        defaults.removeObject(forKey: Keys.configs)
    }

    func loadSteamCMDURL() -> URL? {
        if let bookmarkData = defaults.data(forKey: Keys.steamCMDBookmark) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }

        guard let path = defaults.string(forKey: Keys.steamCMDPath), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func saveSteamCMDURL(_ url: URL) {
        if let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmarkData, forKey: Keys.steamCMDBookmark)
        }
        defaults.set(url.path, forKey: Keys.steamCMDPath)
    }

    func loadSteamCMDLoginMode() -> SteamCMDLoginMode {
        SteamCMDLoginMode(rawValue: defaults.string(forKey: Keys.steamCMDLoginMode) ?? "") ?? .anonymous
    }

    func saveSteamCMDLoginMode(_ mode: SteamCMDLoginMode) {
        defaults.set(mode.rawValue, forKey: Keys.steamCMDLoginMode)
    }

    func loadSteamUsername() -> String {
        defaults.string(forKey: Keys.steamUsername) ?? ""
    }

    func saveSteamUsername(_ username: String) {
        defaults.set(username, forKey: Keys.steamUsername)
    }
}
