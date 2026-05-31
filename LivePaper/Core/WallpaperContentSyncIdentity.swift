import Foundation

extension WallpaperContent {
    var videoSynchronizationID: String? {
        guard kind == .video else {
            return nil
        }

        if url.isFileURL {
            return "video:file:\(url.standardizedFileURL.resolvingSymlinksInPath().path)"
        }
        return "video:url:\(url.standardized.absoluteString)"
    }
}
