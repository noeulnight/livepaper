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
}
