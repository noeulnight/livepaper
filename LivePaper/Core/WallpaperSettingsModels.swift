import Foundation

struct SavedWallpaperConfig: Codable, Equatable, Sendable {
    let displayID: DisplayID
    let content: WallpaperContent
    let scaleMode: ScaleMode
    let volume: Double
    let muted: Bool
    let pauseOnBattery: Bool
    let pauseOnFullscreen: Bool
    let muteOnFullscreen: Bool

    init(
        displayID: DisplayID,
        content: WallpaperContent,
        scaleMode: ScaleMode,
        volume: Double,
        muted: Bool,
        pauseOnBattery: Bool,
        pauseOnFullscreen: Bool,
        muteOnFullscreen: Bool = false
    ) {
        self.displayID = displayID
        self.content = content
        self.scaleMode = scaleMode
        self.volume = volume
        self.muted = muted
        self.pauseOnBattery = pauseOnBattery
        self.pauseOnFullscreen = pauseOnFullscreen
        self.muteOnFullscreen = muteOnFullscreen
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
        case muteOnFullscreen
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
        muteOnFullscreen = try container.decodeIfPresent(Bool.self, forKey: .muteOnFullscreen) ?? false
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
        try container.encode(muteOnFullscreen, forKey: .muteOnFullscreen)
    }
}

struct RuntimePreferences: Equatable, Sendable {
    var scaleMode: ScaleMode
    var muted: Bool
    var volume: Double
    var audioDisplayID: DisplayID?
    var pauseOnBattery: Bool
    var pauseOnFullscreen: Bool
    var muteOnFullscreen: Bool
}
