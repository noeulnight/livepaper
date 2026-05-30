import Foundation

struct WallpaperContent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case video
        case web
        case music
    }

    enum MusicSource: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case appleMusic
        case spotify

        var id: Self { self }

        var title: String {
            switch self {
            case .appleMusic:
                return "Apple Music"
            case .spotify:
                return "Spotify"
            }
        }

        var syncTitle: String {
            "\(title) Album Sync"
        }

        var bundleIdentifier: String {
            switch self {
            case .appleMusic:
                return "com.apple.Music"
            case .spotify:
                return "com.spotify.client"
            }
        }
    }

    let kind: Kind
    let url: URL
    let readAccessURL: URL?
    let musicSource: MusicSource?
    let title: String?
    let previewImageURL: URL?
    let sourceURL: URL?
    let steamWorkshopID: String?
    let bookmarkData: Data?
    let readAccessBookmarkData: Data?

    init(
        kind: Kind,
        url: URL,
        readAccessURL: URL?,
        musicSource: MusicSource? = nil,
        title: String? = nil,
        previewImageURL: URL? = nil,
        sourceURL: URL? = nil,
        steamWorkshopID: String? = nil,
        bookmarkData: Data? = nil,
        readAccessBookmarkData: Data? = nil
    ) {
        self.kind = kind
        self.url = url
        self.readAccessURL = readAccessURL
        self.musicSource = musicSource
        self.title = title?.nilIfBlank
        self.previewImageURL = previewImageURL
        self.sourceURL = sourceURL
        self.steamWorkshopID = steamWorkshopID?.nilIfBlank
        self.bookmarkData = bookmarkData
        self.readAccessBookmarkData = readAccessBookmarkData
    }

    static func video(_ url: URL) -> WallpaperContent {
        WallpaperContent(kind: .video, url: url, readAccessURL: url)
    }

    static func web(_ url: URL, readAccessURL: URL? = nil) -> WallpaperContent {
        WallpaperContent(kind: .web, url: url, readAccessURL: readAccessURL)
    }

    static func webPage(_ url: URL) -> WallpaperContent {
        WallpaperContent(kind: .web, url: YouTubeEmbedURL.normalizedURL(for: url), readAccessURL: nil)
    }

    static func musicAlbumSync(source: MusicSource) -> WallpaperContent {
        WallpaperContent(
            kind: .music,
            url: URL(string: "livepaper://music/\(source.rawValue)")!,
            readAccessURL: nil,
            musicSource: source,
            title: source.syncTitle
        )
    }

    func withMetadata(
        title: String? = nil,
        previewImageURL: URL? = nil,
        sourceURL: URL? = nil,
        steamWorkshopID: String? = nil
    ) -> WallpaperContent {
        WallpaperContent(
            kind: kind,
            url: url,
            readAccessURL: readAccessURL,
            musicSource: musicSource,
            title: title?.nilIfBlank ?? self.title,
            previewImageURL: previewImageURL ?? self.previewImageURL,
            sourceURL: sourceURL ?? self.sourceURL,
            steamWorkshopID: steamWorkshopID?.nilIfBlank ?? self.steamWorkshopID,
            bookmarkData: bookmarkData,
            readAccessBookmarkData: readAccessBookmarkData
        )
    }

    func mergingMetadata(from content: WallpaperContent) -> WallpaperContent {
        withMetadata(
            title: content.title,
            previewImageURL: content.previewImageURL,
            sourceURL: content.sourceURL,
            steamWorkshopID: content.steamWorkshopID
        )
    }

    var displayName: String {
        if let title = title?.nilIfBlank {
            return title
        }
        if url.isFileURL {
            return url.lastPathComponent
        }
        if kind == .music, let musicSource {
            return musicSource.syncTitle
        }
        guard let host = url.host?.removingWWWPrefix, !host.isEmpty else {
            return "Web Wallpaper"
        }
        if host == "youtube-nocookie.com" || host == "youtube.com" {
            return "YouTube Wallpaper"
        }
        return host
    }

}

private extension String {
    var removingWWWPrefix: String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}
