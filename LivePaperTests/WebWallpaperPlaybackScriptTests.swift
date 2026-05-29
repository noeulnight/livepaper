import XCTest
@testable import LivePaper

final class WebWallpaperPlaybackScriptTests: XCTestCase {
    func testPauseScriptPausesYouTubeAndPageMedia() {
        let script = WebWallpaperPlaybackScript.pauseScript

        XCTAssertTrue(script.contains("player.pauseVideo()"))
        XCTAssertTrue(script.contains("querySelectorAll(\"video, audio\")"))
        XCTAssertTrue(script.contains("dataset.livePaperPaused"))
        XCTAssertTrue(script.contains("element.pause()"))
    }

    func testResumeScriptResumesYouTubeWhenRequested() {
        let script = WebWallpaperPlaybackScript.resumeScript(shouldResumeYouTube: true)

        XCTAssertTrue(script.contains("player.playVideo()"))
        XCTAssertTrue(script.contains("element.play()"))
        XCTAssertTrue(script.contains("catch(function() {})"))
    }

    func testResumeScriptDoesNotForceYouTubeForRegularWebPages() {
        let script = WebWallpaperPlaybackScript.resumeScript(shouldResumeYouTube: false)

        XCTAssertFalse(script.contains("player.playVideo()"))
        XCTAssertTrue(script.contains("element.play()"))
    }
}
