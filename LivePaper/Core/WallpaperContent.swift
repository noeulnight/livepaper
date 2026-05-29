import Foundation

struct WallpaperContent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case video
        case web
    }

    let kind: Kind
    let url: URL
    let readAccessURL: URL?
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
        guard let host = url.host?.removingWWWPrefix, !host.isEmpty else {
            return "Web Wallpaper"
        }
        if host == "youtube-nocookie.com" || host == "youtube.com" {
            return "YouTube Wallpaper"
        }
        return host
    }

    func withSecurityScopedBookmarks() -> WallpaperContent {
        WallpaperContent(
            kind: kind,
            url: url,
            readAccessURL: readAccessURL,
            title: title,
            previewImageURL: previewImageURL,
            sourceURL: sourceURL,
            steamWorkshopID: steamWorkshopID,
            bookmarkData: bookmarkData ?? securityScopedBookmarkData(for: url),
            readAccessBookmarkData: readAccessBookmarkData ?? readAccessURL.flatMap(securityScopedBookmarkData)
        )
    }

    func resolvingSecurityScopedBookmarks() -> WallpaperContent {
        let resolvedURL = bookmarkData.flatMap(resolveSecurityScopedBookmark) ?? url
        let resolvedReadAccessURL = readAccessBookmarkData.flatMap(resolveSecurityScopedBookmark) ?? readAccessURL

        return WallpaperContent(
            kind: kind,
            url: resolvedURL,
            readAccessURL: resolvedReadAccessURL,
            title: title,
            previewImageURL: previewImageURL,
            sourceURL: sourceURL,
            steamWorkshopID: steamWorkshopID,
            bookmarkData: bookmarkData,
            readAccessBookmarkData: readAccessBookmarkData
        )
    }

    private func securityScopedBookmarkData(for url: URL) -> Data? {
        guard url.isFileURL else {
            return nil
        }

        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolveSecurityScopedBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var removingWWWPrefix: String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}

nonisolated enum YouTubeEmbedURL {
    static func normalizedURL(for url: URL) -> URL {
        guard let videoID = videoID(from: url) else {
            return url
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube-nocookie.com"
        components.path = "/embed/\(videoID)"
        components.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "mute", value: "1"),
            URLQueryItem(name: "loop", value: "1"),
            URLQueryItem(name: "playlist", value: videoID),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "controls", value: "0"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: "https://www.youtube-nocookie.com"),
            URLQueryItem(name: "widget_referrer", value: "https://www.youtube-nocookie.com")
        ]

        return components.url ?? url
    }

    static func isEmbedURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else {
            return false
        }
        let isYouTubeHost = host == "youtube.com" ||
            host.hasSuffix(".youtube.com") ||
            host == "youtube-nocookie.com" ||
            host.hasSuffix(".youtube-nocookie.com")
        return isYouTubeHost && url.pathComponents.contains("embed")
    }

    static func videoID(from url: URL) -> String? {
        guard let host = url.host()?.lowercased() else {
            return nil
        }

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return firstPathComponent(from: url)
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if pathComponents.first == "watch" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "v" }?
                .value
        }

        if ["shorts", "embed", "live"].contains(pathComponents.first), pathComponents.count >= 2 {
            return pathComponents[1]
        }

        return nil
    }

    private static func firstPathComponent(from url: URL) -> String? {
        url.pathComponents.first { $0 != "/" }
    }
}
