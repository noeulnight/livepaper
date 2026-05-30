import XCTest
@testable import LivePaper

final class WallpaperContentTests: XCTestCase {
    func testDisplayNamePrefersTitleThenFileThenHost() {
        XCTAssertEqual(
            WallpaperContent.video(URL(fileURLWithPath: "/tmp/demo.mov")).displayName,
            "demo.mov"
        )
        XCTAssertEqual(
            WallpaperContent.web(URL(string: "https://www.example.com/wallpaper")!).displayName,
            "example.com"
        )
        XCTAssertEqual(
            WallpaperContent.web(URL(string: "https://example.com")!).withMetadata(title: "City Loop").displayName,
            "City Loop"
        )
        XCTAssertEqual(
            WallpaperContent.musicAlbumSync(source: .spotify).displayName,
            "Spotify Album Sync"
        )
    }

    func testMusicContentCarriesSourceInGalleryID() {
        let appleMusic = WallpaperContent.musicAlbumSync(source: .appleMusic)
        let spotify = WallpaperContent.musicAlbumSync(source: .spotify)

        XCTAssertEqual(appleMusic.kind, .music)
        XCTAssertEqual(appleMusic.musicSource, .appleMusic)
        XCTAssertNotEqual(appleMusic.galleryID, spotify.galleryID)
    }

    func testMergingMetadataKeepsExistingValuesWhenIncomingIsBlank() {
        let base = WallpaperContent
            .web(URL(string: "https://example.com")!)
            .withMetadata(
                title: "Existing",
                previewImageURL: URL(string: "https://example.com/preview.jpg"),
                sourceURL: URL(string: "https://example.com/source"),
                steamWorkshopID: "123"
            )
        let merged = base.mergingMetadata(
            from: WallpaperContent.web(URL(string: "https://example.com")!).withMetadata(title: " ")
        )

        XCTAssertEqual(merged.title, "Existing")
        XCTAssertEqual(merged.previewImageURL, URL(string: "https://example.com/preview.jpg"))
        XCTAssertEqual(merged.sourceURL, URL(string: "https://example.com/source"))
        XCTAssertEqual(merged.steamWorkshopID, "123")
    }

    func testBookmarkResolverFallsBackToOriginalURLWhenBookmarkCannotResolve() {
        let originalURL = URL(fileURLWithPath: "/tmp/missing.mov")
        let content = WallpaperContent(
            kind: .video,
            url: originalURL,
            readAccessURL: originalURL.deletingLastPathComponent(),
            bookmarkData: Data("not-a-bookmark".utf8),
            readAccessBookmarkData: Data("not-a-bookmark".utf8)
        )

        let resolved = content.resolvingSecurityScopedBookmarks()

        XCTAssertEqual(resolved.url, originalURL)
        XCTAssertEqual(resolved.readAccessURL, originalURL.deletingLastPathComponent())
    }
}
