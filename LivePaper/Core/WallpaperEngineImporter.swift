import Foundation

enum SteamWorkshopURLError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedURL
    case missingWorkshopID

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid Steam Workshop URL."
        case .unsupportedURL:
            return "Enter a steamcommunity.com Workshop file details URL."
        case .missingWorkshopID:
            return "Steam Workshop URL is missing an item id."
        }
    }
}

nonisolated struct SteamWorkshopURL: Equatable, Sendable {
    let itemID: String

    init(_ rawValue: String) throws {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SteamWorkshopURLError.invalidURL
        }
        try self.init(url: url)
    }

    init(url: URL) throws {
        guard let host = url.host()?.lowercased(),
              host == "steamcommunity.com" || host.hasSuffix(".steamcommunity.com") else {
            throw SteamWorkshopURLError.unsupportedURL
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2,
              ["sharedfiles", "workshop"].contains(pathComponents[0]),
              pathComponents[1] == "filedetails" else {
            throw SteamWorkshopURLError.unsupportedURL
        }

        guard let itemID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "id" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !itemID.isEmpty,
              itemID.allSatisfy(\.isNumber) else {
            throw SteamWorkshopURLError.missingWorkshopID
        }

        self.itemID = itemID
    }
}

enum WallpaperEngineImportError: LocalizedError {
    case itemNotDownloaded(String, URL)
    case itemIDMismatch(expected: String, selected: String)
    case missingProjectFile(URL)
    case unreadableProjectFile(URL)
    case missingWallpaperFile(URL)
    case unsupportedVideoFormat(URL)
    case unsupportedWallpaperType(String)
    case unsupportedPackageOnly

    var errorDescription: String? {
        switch self {
        case .itemNotDownloaded(let itemID, let expectedURL):
            return "Workshop item \(itemID) is not downloaded in Steam's local cache. Choose its item folder manually or subscribe/download it in Steam first. Expected folder: \(expectedURL.path)"
        case .itemIDMismatch(let expected, let selected):
            return "Selected folder does not match Workshop item \(expected). Selected item: \(selected)."
        case .missingProjectFile(let folderURL):
            return "Selected Workshop item has no project.json: \(folderURL.path)"
        case .unreadableProjectFile(let projectURL):
            return "Could not read Wallpaper Engine project file: \(projectURL.path)"
        case .missingWallpaperFile(let fileURL):
            return "Wallpaper Engine project points to a missing file: \(fileURL.path)"
        case .unsupportedVideoFormat(let fileURL):
            return "LivePaper can import Wallpaper Engine video wallpapers only when they are .mp4, .mov, or .m4v files: \(fileURL.lastPathComponent)"
        case .unsupportedWallpaperType(let type):
            return "LivePaper does not support Wallpaper Engine \(type) wallpapers yet. Import supports web and video wallpapers."
        case .unsupportedPackageOnly:
            return "LivePaper cannot import packaged Wallpaper Engine scene/application files yet. Import supports web and video wallpapers."
        }
    }
}

struct WallpaperEngineImportResult: Equatable, Sendable {
    let workshopID: String
    let title: String?
    let previewImageURL: URL?
    let content: WallpaperContent
}

struct WallpaperEngineMetadata: Equatable, Sendable {
    let workshopID: String?
    let title: String?
    let previewImageURL: URL?
    let sourceURL: URL?
}

struct WallpaperEngineImporter {
    private let fileManager: FileManager
    private let steamRootURL: URL

    init(
        fileManager: FileManager = .default,
        steamRootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam")
    ) {
        self.fileManager = fileManager
        self.steamRootURL = steamRootURL
    }

    func importWorkshopItem(from rawURL: String) throws -> WallpaperEngineImportResult {
        let workshopURL = try SteamWorkshopURL(rawURL)
        let folderURL = cachedItemFolderURL(for: workshopURL.itemID)

        guard fileManager.fileExists(atPath: folderURL.path) else {
            throw WallpaperEngineImportError.itemNotDownloaded(workshopURL.itemID, folderURL)
        }

        return try importWorkshopItem(id: workshopURL.itemID, folderURL: folderURL)
    }

    func importWorkshopItem(from rawURL: String, fallbackFolderURL: URL) throws -> WallpaperEngineImportResult {
        let workshopURL = try SteamWorkshopURL(rawURL)
        return try importWorkshopItem(id: workshopURL.itemID, folderURL: fallbackFolderURL)
    }

    func importWorkshopItem(id workshopID: String, folderURL: URL) throws -> WallpaperEngineImportResult {
        if folderURL.lastPathComponent != workshopID {
            throw WallpaperEngineImportError.itemIDMismatch(expected: workshopID, selected: folderURL.lastPathComponent)
        }

        let projectURL = folderURL.appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: projectURL.path) else {
            if containsPackageFile(in: folderURL) {
                throw WallpaperEngineImportError.unsupportedPackageOnly
            }
            throw WallpaperEngineImportError.missingProjectFile(folderURL)
        }

        let project = try readProject(at: projectURL)
        let type = project.type.lowercased()
        let wallpaperFileURL = folderURL.appendingPathComponent(project.normalizedFile)
        let metadata = metadata(for: project, folderURL: folderURL, workshopID: workshopID)

        guard fileManager.fileExists(atPath: wallpaperFileURL.path) else {
            throw WallpaperEngineImportError.missingWallpaperFile(wallpaperFileURL)
        }

        switch type {
        case "web":
            return WallpaperEngineImportResult(
                workshopID: workshopID,
                title: project.title,
                previewImageURL: metadata.previewImageURL,
                content: WallpaperContent
                    .web(wallpaperFileURL, readAccessURL: folderURL)
                    .withMetadata(
                        title: metadata.title,
                        previewImageURL: metadata.previewImageURL,
                        sourceURL: metadata.sourceURL,
                        steamWorkshopID: metadata.workshopID
                    )
            )
        case "video":
            guard ["mp4", "mov", "m4v"].contains(wallpaperFileURL.pathExtension.lowercased()) else {
                throw WallpaperEngineImportError.unsupportedVideoFormat(wallpaperFileURL)
            }
            return WallpaperEngineImportResult(
                workshopID: workshopID,
                title: project.title,
                previewImageURL: metadata.previewImageURL,
                content: WallpaperContent
                    .video(wallpaperFileURL)
                    .withMetadata(
                        title: metadata.title,
                        previewImageURL: metadata.previewImageURL,
                        sourceURL: metadata.sourceURL,
                        steamWorkshopID: metadata.workshopID
                    )
            )
        default:
            throw WallpaperEngineImportError.unsupportedWallpaperType(type)
        }
    }

    func synchronizedSteamMetadata(for content: WallpaperContent) -> WallpaperContent {
        guard let folderURL = workshopFolderURL(for: content),
              let metadata = try? metadata(in: folderURL, workshopID: content.steamWorkshopID) else {
            return content
        }

        return content.withMetadata(
            title: metadata.title,
            previewImageURL: metadata.previewImageURL,
            sourceURL: metadata.sourceURL,
            steamWorkshopID: metadata.workshopID
        )
    }

    private func cachedItemFolderURL(for workshopID: String) -> URL {
        steamRootURL
            .appendingPathComponent("steamapps/workshop/content/431960")
            .appendingPathComponent(workshopID)
    }

    private func readProject(at projectURL: URL) throws -> WallpaperEngineProject {
        do {
            let data = try Data(contentsOf: projectURL)
            return try JSONDecoder().decode(WallpaperEngineProject.self, from: data)
        } catch {
            throw WallpaperEngineImportError.unreadableProjectFile(projectURL)
        }
    }

    private func containsPackageFile(in folderURL: URL) -> Bool {
        guard let files = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return false
        }
        return files.contains { $0.pathExtension.lowercased() == "pkg" }
    }

    private func metadata(in folderURL: URL, workshopID: String?) throws -> WallpaperEngineMetadata {
        let project = try readProject(at: folderURL.appendingPathComponent("project.json"))
        return metadata(for: project, folderURL: folderURL, workshopID: workshopID ?? folderURL.lastPathComponent)
    }

    private func metadata(
        for project: WallpaperEngineProject,
        folderURL: URL,
        workshopID: String?
    ) -> WallpaperEngineMetadata {
        WallpaperEngineMetadata(
            workshopID: workshopID,
            title: project.title,
            previewImageURL: previewImageURL(for: project, folderURL: folderURL),
            sourceURL: workshopID.flatMap(steamWorkshopSourceURL)
        )
    }

    private func previewImageURL(for project: WallpaperEngineProject, folderURL: URL) -> URL? {
        let candidates = ([project.normalizedPreview].compactMap { $0 } + [
            "preview.jpg",
            "preview.jpeg",
            "preview.png",
            "preview.gif"
        ])
        .map { folderURL.appendingPathComponent($0) }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func workshopFolderURL(for content: WallpaperContent) -> URL? {
        if let readAccessURL = content.readAccessURL,
           directoryExists(at: readAccessURL),
           fileManager.fileExists(atPath: readAccessURL.appendingPathComponent("project.json").path) {
            return readAccessURL
        }

        let startURL = content.url.isFileURL ? content.url.deletingLastPathComponent() : content.url
        return ancestorFolderWithProjectFile(startingAt: startURL)
    }

    private func ancestorFolderWithProjectFile(startingAt url: URL) -> URL? {
        var candidate = url

        for _ in 0..<6 {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("project.json").path) {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }

        return nil
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func steamWorkshopSourceURL(for workshopID: String) -> URL? {
        URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(workshopID)")
    }
}

private struct WallpaperEngineProject: Decodable {
    let file: String
    let preview: String?
    let title: String?
    let type: String

    var normalizedFile: String {
        file.replacingOccurrences(of: "\\", with: "/")
    }

    var normalizedPreview: String? {
        preview?.replacingOccurrences(of: "\\", with: "/")
    }
}
