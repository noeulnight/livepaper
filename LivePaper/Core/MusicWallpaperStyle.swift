import Foundation

enum MusicWallpaperStyle: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case ambient
    case focus
    case minimal

    var id: Self { self }

    var title: String {
        switch self {
        case .ambient:
            return "Ambient"
        case .focus:
            return "Focus"
        case .minimal:
            return "Minimal"
        }
    }
}
