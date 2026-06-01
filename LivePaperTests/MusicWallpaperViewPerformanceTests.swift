import AppKit
import XCTest
@testable import LivePaper

@MainActor
final class MusicWallpaperViewPerformanceTests: XCTestCase {
    func testBackgroundArtworkDoesNotUseLiveLayerFilters() throws {
        let view = MusicWallpaperView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), style: .minimal)
        let backgroundView = try XCTUnwrap(view.subviews.first)

        XCTAssertNil(backgroundView.layer?.filters)
    }

    func testMinimalStyleKeepsBackgroundArtworkStatic() throws {
        let view = MusicWallpaperView(frame: NSRect(x: 0, y: 0, width: 640, height: 360), style: .minimal)
        let snapshot = NowPlayingAlbumSnapshot(
            source: .spotify,
            playbackState: .playing,
            trackID: "track-id",
            trackTitle: "Track",
            artistName: "Artist",
            albumTitle: "Album",
            artworkURL: nil,
            artworkFileURL: nil,
            playbackPosition: 12,
            playbackDuration: 120
        )

        view.update(snapshot: snapshot, artwork: NSImage(size: NSSize(width: 16, height: 16)))

        let backgroundView = try XCTUnwrap(view.subviews.first)
        let backgroundSpin = backgroundView.layer?.animation(forKey: "livepaper.music.backgroundSpin")
        XCTAssertNil(backgroundSpin)
        XCTAssertFalse(backgroundView.isHidden)
        XCTAssertGreaterThan(backgroundView.alphaValue, 0)
    }

    func testMinimalTitleLabelAllowsFontLineHeight() throws {
        let view = MusicWallpaperView(frame: NSRect(x: 0, y: 0, width: 816, height: 276), style: .minimal)
        let snapshot = NowPlayingAlbumSnapshot(
            source: .spotify,
            playbackState: .playing,
            trackID: "track-id",
            trackTitle: "Wingless (feat. RANASOL)",
            artistName: "rejection",
            albumTitle: "Wingless (feat. RANASOL)",
            artworkURL: nil,
            artworkFileURL: nil,
            playbackPosition: 4,
            playbackDuration: 239
        )

        view.update(snapshot: snapshot, artwork: NSImage(size: NSSize(width: 16, height: 16)))
        view.layoutSubtreeIfNeeded()

        let titleLabel = try XCTUnwrap(
            view.subviews
                .compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "Wingless (feat. RANASOL)" }
        )
        let titleFont = try XCTUnwrap(titleLabel.font)

        XCTAssertGreaterThanOrEqual(titleLabel.frame.height, ceil(titleFont.boundingRectForFont.height) + 4)
    }
}
