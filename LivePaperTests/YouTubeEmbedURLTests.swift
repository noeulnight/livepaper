import XCTest
@testable import LivePaper

final class YouTubeEmbedURLTests: XCTestCase {
    func testExtractsVideoIDFromSupportedYouTubeURLs() {
        XCTAssertEqual(YouTubeEmbedURL.videoID(from: URL(string: "https://www.youtube.com/watch?v=abc123")!), "abc123")
        XCTAssertEqual(YouTubeEmbedURL.videoID(from: URL(string: "https://youtu.be/abc123")!), "abc123")
        XCTAssertEqual(YouTubeEmbedURL.videoID(from: URL(string: "https://www.youtube.com/shorts/abc123")!), "abc123")
        XCTAssertEqual(YouTubeEmbedURL.videoID(from: URL(string: "https://www.youtube.com/live/abc123")!), "abc123")
        XCTAssertEqual(YouTubeEmbedURL.videoID(from: URL(string: "https://www.youtube.com/embed/abc123")!), "abc123")
    }

    func testNormalizesYouTubeURLToNoCookieEmbedURL() {
        let normalizedURL = YouTubeEmbedURL.normalizedURL(
            for: URL(string: "https://www.youtube.com/watch?v=abc123")!
        )

        XCTAssertEqual(normalizedURL.scheme, "https")
        XCTAssertEqual(normalizedURL.host, "www.youtube-nocookie.com")
        XCTAssertEqual(normalizedURL.path, "/embed/abc123")
        XCTAssertTrue(YouTubeEmbedURL.isEmbedURL(normalizedURL))
        XCTAssertTrue(normalizedURL.absoluteString.contains("playlist=abc123"))
    }
}
