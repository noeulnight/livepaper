import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

enum AerialLockScreenExportError: LocalizedError {
    case unsupportedContent
    case missingManifest(URL)
    case invalidManifest(URL)
    case invalidWallpaperIndex(URL)
    case videoExportUnavailable
    case videoExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedContent:
            return "Lock Screen export supports local video wallpapers only."
        case .missingManifest(let url):
            return "Apple Aerial manifest was not found: \(url.path)"
        case .invalidManifest(let url):
            return "Apple Aerial manifest could not be updated: \(url.path)"
        case .invalidWallpaperIndex(let url):
            return "macOS wallpaper settings could not be updated: \(url.path)"
        case .videoExportUnavailable:
            return "This video cannot be converted to a Lock Screen wallpaper."
        case .videoExportFailed(let message):
            return "Video export failed: \(message)"
        }
    }
}

struct AerialLockScreenExporter {
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(fileManager: FileManager = .default, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func supportsExport(_ content: WallpaperContent) -> Bool {
        content.kind == .video && content.url.isFileURL
    }

    func export(content: WallpaperContent) async throws {
        guard supportsExport(content) else {
            throw AerialLockScreenExportError.unsupportedContent
        }

        let sourceURL = content.url.resolvingSymlinksInPath()
        let assetID = stableAssetID(for: content)
        let title = content.displayName
        let aerialsURL = wallpaperSupportURL.appendingPathComponent("aerials")
        let manifestURL = aerialsURL.appendingPathComponent("manifest/entries.json")
        let videosURL = aerialsURL.appendingPathComponent("videos")
        let thumbnailsURL = aerialsURL.appendingPathComponent("thumbnails")
        let outputVideoURL = videosURL.appendingPathComponent("\(assetID).mov")
        let outputThumbnailURL = thumbnailsURL.appendingPathComponent("\(assetID).png")

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw AerialLockScreenExportError.missingManifest(manifestURL)
        }

        try fileManager.createDirectory(at: videosURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
        try await writeMOV(from: sourceURL, to: outputVideoURL)
        try await writeThumbnail(from: outputVideoURL, fallback: content.previewImageURL, to: outputThumbnailURL)
        try upsertManifestAsset(
            manifestURL: manifestURL,
            assetID: assetID,
            title: title,
            videoURL: outputVideoURL,
            thumbnailURL: outputThumbnailURL
        )
        try selectAerialAsset(assetID)
        restartWallpaperAgent()
    }

    private var wallpaperSupportURL: URL {
        homeDirectory.appendingPathComponent("Library/Application Support/com.apple.wallpaper")
    }

    private var wallpaperIndexURL: URL {
        wallpaperSupportURL.appendingPathComponent("Store/Index.plist")
    }

    private func stableAssetID(for content: WallpaperContent) -> String {
        if let steamWorkshopID = content.steamWorkshopID {
            return uuidString(from: "steam-\(steamWorkshopID)")
        }
        return uuidString(from: content.url.standardizedFileURL.path)
    }

    private func uuidString(from value: String) -> String {
        let namespace = UUID(uuidString: "4D4E366C-6B06-476A-85C4-2D21A7DAB001")!
        var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes.append(contentsOf: value.utf8)
        let digest = fnv1a64(bytes)
        return String(format: "4D4E366C-%04X-%04X-%04X-%012llX",
                      UInt16((digest >> 48) & 0xffff),
                      UInt16((digest >> 32) & 0xffff),
                      UInt16((digest >> 16) & 0xffff),
                      digest & 0x0000ffffffffffff)
    }

    private func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    private func writeMOV(from sourceURL: URL, to outputURL: URL) async throws {
        try removeExistingFile(at: outputURL)

        if sourceURL.pathExtension.lowercased() == "mov" {
            try fileManager.copyItem(at: sourceURL, to: outputURL)
            return
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw AerialLockScreenExportError.videoExportUnavailable
        }

        export.outputURL = outputURL
        export.outputFileType = .mov
        export.shouldOptimizeForNetworkUse = false
        await export.export()

        guard export.status == .completed else {
            try? removeExistingFile(at: outputURL)
            let message = export.error?.localizedDescription ?? "Unknown export error"
            throw AerialLockScreenExportError.videoExportFailed(message)
        }
    }

    private func writeThumbnail(from videoURL: URL, fallback: URL?, to outputURL: URL) async throws {
        try removeExistingFile(at: outputURL)

        if let fallback, fallback.isFileURL, fileManager.fileExists(atPath: fallback.path),
           let source = CGImageSourceCreateWithURL(fallback as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
           writePNG(image, to: outputURL) {
            return
        }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        let image = try await generatedImage(from: generator, at: CMTime(seconds: 1, preferredTimescale: 600))
        guard writePNG(image, to: outputURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func generatedImage(from generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    private func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private func upsertManifestAsset(
        manifestURL: URL,
        assetID: String,
        title: String,
        videoURL: URL,
        thumbnailURL: URL
    ) throws {
        let backupURL = try backup(url: manifestURL)
        do {
            let data = try Data(contentsOf: manifestURL)
            guard var manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var assets = manifest["assets"] as? [[String: Any]],
                  var categories = manifest["categories"] as? [[String: Any]] else {
                throw AerialLockScreenExportError.invalidManifest(manifestURL)
            }

            let categoryID = "4D4E366C-0000-4000-8000-000000000001"
            let subcategoryID = "4D4E366C-0000-4000-8000-000000000002"
            let asset: [String: Any] = [
                "accessibilityLabel": title,
                "categories": [categoryID],
                "id": assetID,
                "includeInShuffle": true,
                "localizedNameKey": title,
                "pointsOfInterest": ["0": "LIVEPAPER_\(assetID.suffix(6))_0"],
                "preferredOrder": 0,
                "previewImage": thumbnailURL.absoluteString,
                "shotID": "LIVEPAPER_\(assetID.suffix(6))",
                "showInTopLevel": true,
                "subcategories": [subcategoryID],
                "url-4K-SDR-240FPS": videoURL.absoluteString
            ]

            assets.removeAll { ($0["id"] as? String) == assetID }
            assets.insert(asset, at: 0)
            manifest["assets"] = assets

            let category: [String: Any] = [
                "id": categoryID,
                "localizedDescriptionKey": "LivePaper",
                "localizedNameKey": "LivePaper",
                "preferredOrder": 0,
                "previewImage": thumbnailURL.absoluteString,
                "representativeAssetID": assetID,
                "subcategories": [[
                    "id": subcategoryID,
                    "localizedDescriptionKey": "LivePaper",
                    "localizedNameKey": "LivePaper",
                    "preferredOrder": 0,
                    "previewImage": thumbnailURL.absoluteString,
                    "representativeAssetID": assetID
                ]]
            ]
            categories.removeAll { ($0["id"] as? String) == categoryID }
            categories.insert(category, at: 0)
            manifest["categories"] = categories

            let output = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: manifestURL, options: .atomic)
        } catch {
            try? fileManager.copyItem(at: backupURL, to: manifestURL)
            throw error
        }
    }

    private func selectAerialAsset(_ assetID: String) throws {
        let indexURL = wallpaperIndexURL
        let backupURL = try backup(url: indexURL)
        do {
            let data = try Data(contentsOf: indexURL)
            guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw AerialLockScreenExportError.invalidWallpaperIndex(indexURL)
            }

            try setDesktopAerialAsset(assetID, in: &plist, scope: "SystemDefault")
            try setDesktopAerialAsset(assetID, in: &plist, scope: "AllSpacesAndDisplays")

            let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try output.write(to: indexURL, options: Data.WritingOptions.atomic)
        } catch {
            try? fileManager.copyItem(at: backupURL, to: indexURL)
            throw error
        }
    }

    private func setDesktopAerialAsset(_ assetID: String, in plist: inout [String: Any], scope: String) throws {
        var scopeValue = plist[scope] as? [String: Any] ?? ["Type": "individual"]
        var desktop = scopeValue["Desktop"] as? [String: Any] ?? [:]
        var content = desktop["Content"] as? [String: Any] ?? [:]
        content["Choices"] = [[
            "Configuration": try PropertyListSerialization.data(fromPropertyList: ["assetID": assetID], format: .binary, options: 0),
            "Files": [],
            "Provider": "com.apple.wallpaper.choice.aerials"
        ]]
        desktop["Content"] = content
        desktop["LastSet"] = Date()
        desktop["LastUse"] = Date()
        scopeValue["Desktop"] = desktop
        plist[scope] = scopeValue
    }

    private func backup(url: URL) throws -> URL {
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).livepaper-backup")
        try removeExistingFile(at: backupURL)
        try fileManager.copyItem(at: url, to: backupURL)
        return backupURL
    }

    private func removeExistingFile(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func restartWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        try? process.run()
    }
}
