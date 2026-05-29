import Foundation

struct SavedWallpaperConfig: Codable, Equatable, Sendable {
    let displayID: DisplayID
    let content: WallpaperContent
    let scaleMode: ScaleMode
    let volume: Double
    let muted: Bool
    let pauseOnBattery: Bool
    let pauseOnFullscreen: Bool

    init(
        displayID: DisplayID,
        content: WallpaperContent,
        scaleMode: ScaleMode,
        volume: Double,
        muted: Bool,
        pauseOnBattery: Bool,
        pauseOnFullscreen: Bool
    ) {
        self.displayID = displayID
        self.content = content
        self.scaleMode = scaleMode
        self.volume = volume
        self.muted = muted
        self.pauseOnBattery = pauseOnBattery
        self.pauseOnFullscreen = pauseOnFullscreen
    }

    private enum CodingKeys: String, CodingKey {
        case displayID
        case content
        case videoURL
        case scaleMode
        case volume
        case muted
        case pauseOnBattery
        case pauseOnFullscreen
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayID = try container.decode(DisplayID.self, forKey: .displayID)
        if let content = try container.decodeIfPresent(WallpaperContent.self, forKey: .content) {
            self.content = content
        } else {
            let videoURL = try container.decode(URL.self, forKey: .videoURL)
            self.content = .video(videoURL)
        }
        scaleMode = try container.decode(ScaleMode.self, forKey: .scaleMode)
        volume = try container.decode(Double.self, forKey: .volume)
        muted = try container.decode(Bool.self, forKey: .muted)
        pauseOnBattery = try container.decode(Bool.self, forKey: .pauseOnBattery)
        pauseOnFullscreen = try container.decode(Bool.self, forKey: .pauseOnFullscreen)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(content, forKey: .content)
        try container.encode(scaleMode, forKey: .scaleMode)
        try container.encode(volume, forKey: .volume)
        try container.encode(muted, forKey: .muted)
        try container.encode(pauseOnBattery, forKey: .pauseOnBattery)
        try container.encode(pauseOnFullscreen, forKey: .pauseOnFullscreen)
    }
}

@MainActor
final class WallpaperSettingsStore {
    private enum Keys {
        static let configs = "wallpaper.configs"
        static let library = "wallpaper.library"
        static let scaleMode = "wallpaper.scaleMode"
        static let muted = "wallpaper.muted"
        static let volume = "wallpaper.volume"
        static let pauseOnBattery = "wallpaper.pauseOnBattery"
        static let pauseOnFullscreen = "wallpaper.pauseOnFullscreen"
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
            pauseOnBattery: defaults.object(forKey: Keys.pauseOnBattery) as? Bool ?? true,
            pauseOnFullscreen: defaults.object(forKey: Keys.pauseOnFullscreen) as? Bool ?? true
        )
    }

    func saveRuntimePreferences(_ preferences: RuntimePreferences) {
        defaults.set(preferences.scaleMode.rawValue, forKey: Keys.scaleMode)
        defaults.set(preferences.muted, forKey: Keys.muted)
        defaults.set(preferences.volume, forKey: Keys.volume)
        defaults.set(preferences.pauseOnBattery, forKey: Keys.pauseOnBattery)
        defaults.set(preferences.pauseOnFullscreen, forKey: Keys.pauseOnFullscreen)
    }

    func loadSavedConfigs() -> [DisplayID: SavedWallpaperConfig] {
        guard let data = defaults.data(forKey: Keys.configs),
              let configs = try? JSONDecoder().decode([SavedWallpaperConfig].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: configs.map { ($0.displayID, $0) })
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

        return contents
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

struct RuntimePreferences: Equatable, Sendable {
    var scaleMode: ScaleMode
    var muted: Bool
    var volume: Double
    var pauseOnBattery: Bool
    var pauseOnFullscreen: Bool
}
