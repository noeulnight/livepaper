import Foundation

enum MusicSyncSourceSelection: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case auto
    case appleMusic
    case spotify

    var id: Self { self }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .appleMusic:
            return WallpaperContent.MusicSource.appleMusic.title
        case .spotify:
            return WallpaperContent.MusicSource.spotify.title
        }
    }

    var forcedSource: WallpaperContent.MusicSource? {
        switch self {
        case .auto:
            return nil
        case .appleMusic:
            return .appleMusic
        case .spotify:
            return .spotify
        }
    }
}
