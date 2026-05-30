import AppKit
import Foundation

enum ScreenSaverInstallError: LocalizedError {
    case bundledSaverNotFound

    var errorDescription: String? {
        switch self {
        case .bundledSaverNotFound:
            return "LivePaper Screen Saver is missing from the app bundle."
        }
    }
}

struct ScreenSaverInstaller {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func install() throws {
        guard let sourceURL = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("LivePaperScreenSaver.saver"),
              fileManager.fileExists(atPath: sourceURL.path) else {
            throw ScreenSaverInstallError.bundledSaverNotFound
        }

        let destinationDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers")
        let destinationURL = destinationDirectory.appendingPathComponent("LivePaperScreenSaver.saver")

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func openScreenSaverSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
