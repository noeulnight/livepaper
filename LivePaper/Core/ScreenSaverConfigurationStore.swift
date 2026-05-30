import Foundation

enum ScreenSaverConfigurationError: LocalizedError {
    case unsupportedContent

    var errorDescription: String? {
        switch self {
        case .unsupportedContent:
            return "Screen Saver supports local video wallpapers only."
        }
    }
}

struct ScreenSaverConfiguration: Codable, Equatable, Sendable {
    let videoURL: URL
    let title: String?
    let bookmarkData: Data?
}

struct ScreenSaverConfigurationStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func supports(_ content: WallpaperContent) -> Bool {
        content.kind == .video && content.url.isFileURL
    }

    func save(content: WallpaperContent) throws {
        guard supports(content) else {
            throw ScreenSaverConfigurationError.unsupportedContent
        }

        let configuration = ScreenSaverConfiguration(
            videoURL: content.url,
            title: content.title,
            bookmarkData: content.bookmarkData ?? SecurityScopedBookmarkResolver().bookmarkData(for: content.url)
        )
        let data = try JSONEncoder().encode(configuration)
        let url = try configurationURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func configurationURL() throws -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupportURL
            .appendingPathComponent("LivePaper")
            .appendingPathComponent("ScreenSaverConfig.json")
    }
}
