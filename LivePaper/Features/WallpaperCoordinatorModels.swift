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
        }

        if steamWorkshopID != nil {
            return "Steam Workshop - \(mediaType)"
        }
        return mediaType
    }
}

extension WallpaperContent {
    var galleryID: String {
        "\(kind.rawValue):\(url.absoluteString)"
    }
}
