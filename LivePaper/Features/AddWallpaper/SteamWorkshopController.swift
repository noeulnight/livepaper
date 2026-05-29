import Foundation

@MainActor
final class SteamWorkshopController {
    private let store: WallpaperSettingsStore

    private var steamCMDURL: URL?
    var steamCMDLoginMode: SteamCMDLoginMode = .anonymous {
        didSet {
            store.saveSteamCMDLoginMode(steamCMDLoginMode)
        }
    }
    var steamUsername = "" {
        didSet {
            store.saveSteamUsername(steamUsername)
        }
    }
    private(set) var steamDownloadLog = ""

    init(store: WallpaperSettingsStore) {
        self.store = store
        steamCMDURL = store.loadSteamCMDURL()
        steamCMDLoginMode = store.loadSteamCMDLoginMode()
        steamUsername = store.loadSteamUsername()
    }

    func importWorkshop(url rawURL: String, fallbackFolderURL: URL? = nil) throws -> WallpaperContent {
        let importer = WallpaperEngineImporter()
        let result: WallpaperEngineImportResult
        if let fallbackFolderURL {
            result = try importer.importWorkshopItem(from: rawURL, fallbackFolderURL: fallbackFolderURL)
        } else {
            result = try importer.importWorkshopItem(from: rawURL)
        }
        return result.content.withSecurityScopedBookmarks()
    }

    func downloadWorkshop(url rawURL: String) async throws -> WallpaperContent {
        resetDownloadLog()
        let downloader = SteamCMDWorkshopDownloader(
            steamCMDURL: steamCMDURL,
            loginMode: steamCMDLoginMode,
            username: steamUsername
        )
        let folderURL = try await downloader.downloadWorkshopItem(from: rawURL) { @MainActor [weak self] logChunk in
            self?.appendDownloadLog(logChunk)
        }
        appendDownloadLog("[LivePaper] Importing downloaded wallpaper.\n")
        let result = try WallpaperEngineImporter().importWorkshopItem(from: rawURL, fallbackFolderURL: folderURL)
        appendDownloadLog("[LivePaper] Imported: \(result.title ?? result.content.displayName)\n")
        return result.content.withSecurityScopedBookmarks()
    }

    func setSteamCMDURL(_ url: URL) {
        steamCMDURL = url
        store.saveSteamCMDURL(url)
    }

    func clearDownloadLog() {
        steamDownloadLog = ""
    }

    private func resetDownloadLog() {
        steamDownloadLog = ""
    }

    private func appendDownloadLog(_ chunk: String) {
        steamDownloadLog += chunk

        let maxLogCharacterCount = 20_000
        if steamDownloadLog.count > maxLogCharacterCount {
            steamDownloadLog = String(steamDownloadLog.suffix(maxLogCharacterCount))
        }
    }
}
