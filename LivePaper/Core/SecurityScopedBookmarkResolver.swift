import Foundation

struct SecurityScopedBookmarkResolver {
    func bookmarkData(for url: URL) -> Data? {
        guard url.isFileURL else {
            return nil
        }

        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolve(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}

extension WallpaperContent {
    func withSecurityScopedBookmarks(
        resolver: SecurityScopedBookmarkResolver = SecurityScopedBookmarkResolver()
    ) -> WallpaperContent {
        WallpaperContent(
            kind: kind,
            url: url,
            readAccessURL: readAccessURL,
            musicSource: musicSource,
            title: title,
            previewImageURL: previewImageURL,
            sourceURL: sourceURL,
            steamWorkshopID: steamWorkshopID,
            bookmarkData: bookmarkData ?? resolver.bookmarkData(for: url),
            readAccessBookmarkData: readAccessBookmarkData ?? readAccessURL.flatMap(resolver.bookmarkData)
        )
    }

    func resolvingSecurityScopedBookmarks(
        resolver: SecurityScopedBookmarkResolver = SecurityScopedBookmarkResolver()
    ) -> WallpaperContent {
        let resolvedURL = bookmarkData.flatMap(resolver.resolve) ?? url
        let resolvedReadAccessURL = readAccessBookmarkData.flatMap(resolver.resolve) ?? readAccessURL

        return WallpaperContent(
            kind: kind,
            url: resolvedURL,
            readAccessURL: resolvedReadAccessURL,
            musicSource: musicSource,
            title: title,
            previewImageURL: previewImageURL,
            sourceURL: sourceURL,
            steamWorkshopID: steamWorkshopID,
            bookmarkData: bookmarkData,
            readAccessBookmarkData: readAccessBookmarkData
        )
    }
}
