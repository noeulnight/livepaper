import Foundation

struct WallpaperConfig: Codable, Equatable, Sendable {
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
        scaleMode: ScaleMode = .fill,
        volume: Double = 1,
        muted: Bool = false,
        pauseOnBattery: Bool = true,
        pauseOnFullscreen: Bool = true
    ) {
        self.displayID = displayID
        self.content = content
        self.scaleMode = scaleMode
        self.volume = volume
        self.muted = muted
        self.pauseOnBattery = pauseOnBattery
        self.pauseOnFullscreen = pauseOnFullscreen
    }
}
