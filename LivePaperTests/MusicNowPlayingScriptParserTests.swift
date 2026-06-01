import XCTest
@testable import LivePaper

final class MusicNowPlayingScriptParserTests: XCTestCase {
    func testParsesSpotifyArtworkURL() {
        let separator = MusicNowPlayingScriptParser.separator
        let output = [
            "playing",
            "spotify:track:123",
            "Song",
            "Artist",
            "Album",
            "https://i.scdn.co/image/cover",
            "42.5",
            "180"
        ].joined(separator: separator)

        let snapshot = MusicNowPlayingScriptParser.parse(output, source: .spotify)

        XCTAssertEqual(snapshot?.playbackState, .playing)
        XCTAssertEqual(snapshot?.trackTitle, "Song")
        XCTAssertEqual(snapshot?.artistName, "Artist")
        XCTAssertEqual(snapshot?.albumTitle, "Album")
        XCTAssertEqual(snapshot?.artworkURL, URL(string: "https://i.scdn.co/image/cover"))
        XCTAssertEqual(snapshot?.playbackPosition, 42.5)
        XCTAssertEqual(snapshot?.playbackDuration, 180)
        XCTAssertEqual(snapshot?.progressFraction ?? -1, CGFloat(42.5 / 180), accuracy: 0.001)
        XCTAssertEqual(snapshot?.playbackPositionText, "0:42")
        XCTAssertEqual(snapshot?.playbackDurationText, "3:00")
    }

    func testParsesStoppedPlaybackAsPlaceholder() {
        let separator = MusicNowPlayingScriptParser.separator
        let output = ["stopped", "", "", "", "", ""].joined(separator: separator)

        let snapshot = MusicNowPlayingScriptParser.parse(output, source: .appleMusic)

        XCTAssertEqual(snapshot?.playbackState, .stopped)
        XCTAssertEqual(snapshot?.trackTitle, "Not Playing")
        XCTAssertEqual(snapshot?.artistName, "Waiting for playback")
        XCTAssertEqual(snapshot?.albumTitle, "Music Sync")
        XCTAssertNil(snapshot?.playbackPosition)
        XCTAssertNil(snapshot?.playbackDuration)
    }

    func testParsesLocalArtworkPathAndCommaDecimalTimes() throws {
        let artworkFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LivePaper-\(UUID().uuidString).jpg")
        try Data([0]).write(to: artworkFileURL)
        defer { try? FileManager.default.removeItem(at: artworkFileURL) }

        let separator = MusicNowPlayingScriptParser.separator
        let output = [
            "playing",
            "",
            "Song",
            "Artist",
            "Album",
            artworkFileURL.path,
            "12,5",
            "100,0"
        ].joined(separator: separator)

        let snapshot = MusicNowPlayingScriptParser.parse(output, source: .appleMusic)

        XCTAssertEqual(snapshot?.trackID, "Song|Artist|Album")
        XCTAssertEqual(snapshot?.artworkFileURL, artworkFileURL)
        XCTAssertNil(snapshot?.artworkURL)
        XCTAssertEqual(snapshot?.playbackPosition, 12.5)
        XCTAssertEqual(snapshot?.playbackDuration, 100)
    }

    @MainActor
    func testAppleMusicProviderExtractsArtworkOnlyWhenTrackChanges() async throws {
        let separator = MusicNowPlayingScriptParser.separator
        var artworkScriptCalls = 0
        let provider = AppleScriptNowPlayingProvider(
            source: .appleMusic,
            scriptExecutor: { script in
                if script.contains("raw data of artwork 1") {
                    artworkScriptCalls += 1
                    let path = Self.artworkPath(from: script)
                    try? Data([1, 2, 3]).write(to: URL(fileURLWithPath: path))
                    return path
                }

                return [
                    "playing",
                    "track-1",
                    "Song",
                    "Artist",
                    "Album",
                    "",
                    "12",
                    "120"
                ].joined(separator: separator)
            },
            runningApplicationBundleIDs: {
                [WallpaperContent.MusicSource.appleMusic.bundleIdentifier]
            }
        )

        let firstSnapshot = await provider.currentAlbum()
        let secondSnapshot = await provider.currentAlbum()

        XCTAssertEqual(artworkScriptCalls, 1)
        XCTAssertEqual(firstSnapshot?.artworkFileURL, secondSnapshot?.artworkFileURL)
        XCTAssertNotNil(secondSnapshot?.artworkFileURL)
        if let artworkFileURL = secondSnapshot?.artworkFileURL {
            try? FileManager.default.removeItem(at: artworkFileURL)
        }
    }

    @MainActor
    func testMonitorSharesProviderForSubscribersOfSameSource() {
        var providerCreationCount = 0
        let monitor = AppleScriptNowPlayingMonitor { source in
            providerCreationCount += 1
            return StaticNowPlayingProvider(source: source)
        }

        let firstSubscription = monitor.subscribe(source: .spotify) { _ in }
        let secondSubscription = monitor.subscribe(source: .spotify) { _ in }

        XCTAssertEqual(providerCreationCount, 1)
        firstSubscription.cancel()
        secondSubscription.cancel()
    }

    @MainActor
    func testMonitorCurrentAlbumReturnsOneShotSnapshotWithoutSubscribers() async {
        let monitor = AppleScriptNowPlayingMonitor { source in
            StaticNowPlayingProvider(source: source)
        }

        let snapshot = await monitor.currentAlbum(source: .spotify)

        XCTAssertEqual(snapshot?.source, .spotify)
        XCTAssertEqual(snapshot?.trackTitle, "Song")
    }

    private static func artworkPath(from script: String) -> String {
        let marker = "set artworkPath to \""
        guard let markerRange = script.range(of: marker) else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("LivePaper-test-artwork")
                .path
        }

        let remainder = script[markerRange.upperBound...]
        guard let endIndex = remainder.firstIndex(of: "\"") else {
            return String(remainder)
        }
        return String(remainder[..<endIndex])
    }
}

private struct StaticNowPlayingProvider: NowPlayingAlbumProviding {
    let source: WallpaperContent.MusicSource

    func currentAlbum() async -> NowPlayingAlbumSnapshot? {
        NowPlayingAlbumSnapshot(
            source: source,
            playbackState: .playing,
            trackID: "track-id",
            trackTitle: "Song",
            artistName: "Artist",
            albumTitle: "Album",
            artworkURL: nil,
            artworkFileURL: nil,
            playbackPosition: 12,
            playbackDuration: 120
        )
    }
}
