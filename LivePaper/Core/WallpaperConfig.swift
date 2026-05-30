import Foundation

struct WallpaperConfig: Codable, Equatable, Sendable {
    let displayID: DisplayID
    let content: WallpaperContent
    let scaleMode: ScaleMode
    let volume: Double
    let muted: Bool
    let pauseOnBattery: Bool
    let pauseOnFullscreen: Bool
    let muteOnFullscreen: Bool
    let musicStyle: MusicWallpaperStyle

    init(
        displayID: DisplayID,
        content: WallpaperContent,
        scaleMode: ScaleMode = .fill,
        volume: Double = 1,
        muted: Bool = false,
        pauseOnBattery: Bool = true,
        pauseOnFullscreen: Bool = true,
        muteOnFullscreen: Bool = false,
        musicStyle: MusicWallpaperStyle = .ambient
    ) {
        self.displayID = displayID
        self.content = content
        self.scaleMode = scaleMode
        self.volume = volume
        self.muted = muted
        self.pauseOnBattery = pauseOnBattery
        self.pauseOnFullscreen = pauseOnFullscreen
        self.muteOnFullscreen = muteOnFullscreen
        self.musicStyle = musicStyle
    }
}
