import AppKit
import Foundation

struct DisplayState: Identifiable, Hashable, Sendable {
    let id: DisplayID
    let name: String
    let frameDescription: String

    init?(screen: NSScreen) {
        guard let id = screen.livePaperDisplayID else {
            return nil
        }
        self.id = id
        self.name = screen.localizedName
        self.frameDescription = "\(Int(screen.frame.width)) x \(Int(screen.frame.height))"
    }
}

struct WallpaperGalleryItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: WallpaperContent.Kind
    let url: URL
    let previewImageURL: URL?
    let sourceURL: URL?
    let steamWorkshopID: String?
    let savedDisplayCount: Int

    var subtitle: String {
        let mediaType: String
        switch kind {
        case .video:
            mediaType = "Video"
        case .web:
            mediaType = url.isFileURL ? "Web folder" : "Web page"
        case .music:
            mediaType = "Album sync"
        }

        if steamWorkshopID != nil {
            return "Steam Workshop - \(mediaType)"
        }
        return mediaType
    }
}

enum WallpaperApplySurfaceState: Equatable, Sendable {
    case idle
    case applying
    case applied
    case skipped
    case failed
}

enum ApplyProgressDuration: Sendable {
    case primary
    case secondary
    case verification

    var nanoseconds: UInt64 {
        switch self {
        case .primary:
            return 150_000_000
        case .secondary:
            return 100_000_000
        case .verification:
            return 250_000_000
        }
    }
}

struct WallpaperApplySurfaceStatus: Equatable, Sendable {
    var state: WallpaperApplySurfaceState
    var detail: String

    static let idle = WallpaperApplySurfaceStatus(state: .idle, detail: "Ready")
}

struct WallpaperApplyStatus: Equatable, Sendable {
    var contentName: String
    var displayCount: Int
    var desktop: WallpaperApplySurfaceStatus
    var lockScreen: WallpaperApplySurfaceStatus
    var screenSaver: WallpaperApplySurfaceStatus

    static let idle = WallpaperApplyStatus(
        contentName: "No wallpaper applied",
        displayCount: 0,
        desktop: .idle,
        lockScreen: .idle,
        screenSaver: .idle
    )
}

extension WallpaperContent {
    var galleryID: String {
        "\(kind.rawValue):\(url.absoluteString)"
    }
}
