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
    private static let plistNullSentinel = Date(timeIntervalSinceReferenceDate: -7_777_777_777)

    private let fileManager: FileManager
    private let homeDirectory: URL
    private let runServiceCommand: ([String]) -> Void

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        runServiceCommand: @escaping ([String]) -> Void = AerialLockScreenExporter.runKillall
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.runServiceCommand = runServiceCommand
    }

    func supportsExport(_ content: WallpaperContent) -> Bool {
        content.kind == .video && content.url.isFileURL
    }

    func export(content: WallpaperContent, displayID: DisplayID? = nil) async throws {
        if let displayID {
            try await export(content: content, displayIDs: [displayID])
            return
        }

        try await export(content: content, displayIDs: [])
    }

    func export(content: WallpaperContent, displayIDs: [DisplayID]) async throws {
        guard supportsExport(content) else {
            throw AerialLockScreenExportError.unsupportedContent
        }

        let assetID = try await prepareExportedAsset(content)
        if displayIDs.isEmpty {
            try selectAerialAsset(assetID, displayIDs: nil)
        } else {
            try selectAerialAsset(assetID, displayIDs: displayIDs)
        }
        restartWallpaperAgent()
    }

    func export(contentsByDisplayID: [(displayID: DisplayID, content: WallpaperContent)]) async throws {
        let supportedItems = contentsByDisplayID.filter { supportsExport($0.content) }
        guard supportedItems.count == contentsByDisplayID.count else {
            throw AerialLockScreenExportError.unsupportedContent
        }

        var assetSelections: [(displayID: DisplayID, assetID: String)] = []
        for item in supportedItems {
            let assetID = try await prepareExportedAsset(item.content)
            assetSelections.append((displayID: item.displayID, assetID: assetID))
        }

        guard !assetSelections.isEmpty else {
            return
        }

        try selectAerialAssets(assetSelections)
        restartWallpaperAgent()
    }

    private func prepareExportedAsset(_ content: WallpaperContent) async throws -> String {
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
        return assetID
    }

    func selectExportedAsset(assetID: String, displayID: DisplayID?) throws {
        try selectAerialAsset(assetID, displayIDs: displayID.map { [$0] })
    }

    func selectExportedAssets(_ assetSelections: [(displayID: DisplayID, assetID: String)]) throws {
        try selectAerialAssets(assetSelections)
    }

    func isExportSelected(content: WallpaperContent, displayIDs: [DisplayID]) -> Bool {
        let assetID = stableAssetID(for: content)

        guard
            let data = try? Data(contentsOf: wallpaperIndexURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return false
        }

        guard !displayIDs.isEmpty else {
            return plistContainsAerialAsset(assetID, in: plist)
        }

        return displayIDs.allSatisfy { displayID in
            plistContainsAerialAsset(assetID, for: displayID, in: plist)
        }
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
        if canReuseGeneratedFile(at: outputURL, dependencyURLs: [sourceURL]) {
            return
        }

        try removeExistingFile(at: outputURL)

        if sourceURL.pathExtension.lowercased() == "mov" {
            try fileManager.copyItem(at: sourceURL, to: outputURL)
            return
        }

        let asset = AVURLAsset(url: sourceURL)
        if let passthroughExport = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough),
           passthroughExport.supportedFileTypes.contains(.mov) {
            do {
                try await runExport(passthroughExport, outputURL: outputURL)
                return
            } catch {
                try? removeExistingFile(at: outputURL)
            }
        }

        try await transcodeMOV(from: asset, to: outputURL)
    }

    private func transcodeMOV(from asset: AVURLAsset, to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first
        guard
            let sourceVideoTrack,
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AerialLockScreenExportError.videoExportUnavailable
        }

        let duration = try await asset.load(.duration)
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        var presetName = AVAssetExportPresetHighestQuality
        for candidatePreset in [
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPresetHighestQuality
        ] {
            let isCompatible = await AVAssetExportSession.compatibility(
                ofExportPreset: candidatePreset,
                with: composition,
                outputFileType: .mov
            )
            if isCompatible {
                presetName = candidatePreset
                break
            }
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw AerialLockScreenExportError.videoExportUnavailable
        }

        try await runExport(export, outputURL: outputURL)
    }

    private func runExport(_ export: AVAssetExportSession, outputURL: URL) async throws {
        export.shouldOptimizeForNetworkUse = false
        do {
            try await export.export(to: outputURL, as: .mov)
        } catch {
            try? removeExistingFile(at: outputURL)
            throw AerialLockScreenExportError.videoExportFailed(error.localizedDescription)
        }
    }

    private func writeThumbnail(from videoURL: URL, fallback: URL?, to outputURL: URL) async throws {
        let fileFallbackURL = fallback.flatMap { url in
            url.isFileURL && fileManager.fileExists(atPath: url.path) ? url : nil
        }
        if canReuseGeneratedFile(at: outputURL, dependencyURLs: [videoURL, fileFallbackURL].compactMap({ $0 })) {
            return
        }

        try removeExistingFile(at: outputURL)

        if let fallback = fileFallbackURL,
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
            restoreBackup(from: backupURL, to: manifestURL)
            throw error
        }
    }

    private func selectAerialAsset(_ assetID: String, displayIDs: [DisplayID]?) throws {
        try updateWallpaperIndex { plist in
            if let displayIDs {
                try materializeDisplayScopesIfNeeded(for: displayIDs, in: &plist)

                for displayID in displayIDs {
                    try setDisplayAerialAsset(assetID, displayID: displayID, in: &plist)
                }
            } else {
                try setLockScreenAerialAsset(assetID, in: &plist, scope: "SystemDefault")
                try setLockScreenAerialAsset(assetID, in: &plist, scope: "AllSpacesAndDisplays")
            }
        }
    }

    private func selectAerialAssets(_ assetSelections: [(displayID: DisplayID, assetID: String)]) throws {
        try updateWallpaperIndex { plist in
            let displayIDs = assetSelections.map(\.displayID)
            try materializeDisplayScopesIfNeeded(for: displayIDs, in: &plist)
            for selection in assetSelections {
                try setDisplayAerialAsset(selection.assetID, displayID: selection.displayID, in: &plist)
            }
        }
    }

    private func updateWallpaperIndex(_ update: (inout [String: Any]) throws -> Void) throws {
        let indexURL = wallpaperIndexURL
        let backupURL = try backup(url: indexURL)
        do {
            stopWallpaperServicesBeforeStoreUpdate()
            let data = try Data(contentsOf: indexURL)
            guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw AerialLockScreenExportError.invalidWallpaperIndex(indexURL)
            }

            try update(&plist)
            let output = try encodedWallpaperIndex(plist)
            try output.write(to: indexURL, options: Data.WritingOptions.atomic)
        } catch {
            restoreBackup(from: backupURL, to: indexURL)
            throw error
        }
    }

    private func materializeDisplayScopesIfNeeded(for displayIDs: [DisplayID], in plist: inout [String: Any]) throws {
        guard !displayIDs.isEmpty else {
            return
        }

        var displays = plist["Displays"] as? [String: Any] ?? [:]
        let templateScope = displayScopeTemplate(from: plist)
        var didMaterializeDisplayScope = false
        for displayID in displayIDs where displays[displayID.uuid] == nil {
            displays[displayID.uuid] = templateScope
            didMaterializeDisplayScope = true
        }
        plist["Displays"] = displays

        if didMaterializeDisplayScope {
            plist["AllSpacesAndDisplays"] = plistNull()
        }
    }

    private func displayScopeTemplate(from plist: [String: Any]) -> [String: Any] {
        if let systemDefault = plist["SystemDefault"] as? [String: Any] {
            return systemDefault
        }

        if let allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any] {
            return allSpaces
        }

        return [
            "Type": "linked",
            "Linked": [
                "Content": [
                    "Choices": [[
                        "Configuration": Data(),
                        "Files": [],
                        "Provider": "default"
                    ]]
                ]
            ]
        ]
    }

    private func setDisplayAerialAsset(_ assetID: String, displayID: DisplayID, in plist: inout [String: Any]) throws {
        let key = displayID.uuid
        var displays = plist["Displays"] as? [String: Any] ?? [:]
        var displayScope = displays[key] as? [String: Any] ?? ["Type": "individual"]
        try setLockScreenAerialAsset(assetID, in: &displayScope)
        displays[key] = displayScope
        plist["Displays"] = displays

        guard var spaces = plist["Spaces"] as? [String: Any] else {
            return
        }

        for spaceKey in spaces.keys {
            guard var space = spaces[spaceKey] as? [String: Any] else {
                continue
            }
            var spaceDisplays = space["Displays"] as? [String: Any] ?? [:]
            var spaceDisplayScope = spaceDisplays[key] as? [String: Any] ?? ["Type": "individual"]
            try setLockScreenAerialAsset(assetID, in: &spaceDisplayScope)
            spaceDisplays[key] = spaceDisplayScope
            space["Displays"] = spaceDisplays
            spaces[spaceKey] = space
        }

        plist["Spaces"] = spaces
    }

    private func setLockScreenAerialAsset(_ assetID: String, in plist: inout [String: Any], scope: String) throws {
        var scopeValue = plist[scope] as? [String: Any] ?? ["Type": "individual"]
        try setLockScreenAerialAsset(assetID, in: &scopeValue)
        plist[scope] = scopeValue
    }

    private func setLockScreenAerialAsset(_ assetID: String, in scopeValue: inout [String: Any]) throws {
        let selectionKey = lockScreenSelectionKey(in: scopeValue)
        var selection = scopeValue[selectionKey] as? [String: Any] ?? [:]
        var content = selection["Content"] as? [String: Any] ?? [:]
        content["Choices"] = [[
            "Configuration": try PropertyListSerialization.data(fromPropertyList: ["assetID": assetID], format: .binary, options: 0),
            "Files": [],
            "Provider": "com.apple.wallpaper.choice.aerials"
        ]]
        content["EncodedOptionValues"] = try encodedOptionValues()
        content["Shuffle"] = plistNull()
        selection["Content"] = content
        selection["LastSet"] = Date()
        selection["LastUse"] = Date()
        scopeValue[selectionKey] = selection
    }

    private func plistNull() -> Any {
        Self.plistNullSentinel
    }

    private func encodedWallpaperIndex(_ plist: [String: Any]) throws -> Data {
        let normalizedPlist = replacePlistNullsWithSentinel(in: plist)
        var data = try PropertyListSerialization.data(fromPropertyList: normalizedPlist, format: .binary, options: 0)
        try patchPlistNullSentinels(in: &data)
        return data
    }

    private func replacePlistNullsWithSentinel(in value: Any) -> Any {
        if isPlistNull(value) {
            return Self.plistNullSentinel
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues { replacePlistNullsWithSentinel(in: $0) }
        }

        if let array = value as? [Any] {
            return array.map { replacePlistNullsWithSentinel(in: $0) }
        }

        return value
    }

    private func isPlistNull(_ value: Any) -> Bool {
        if value is NSNull {
            return true
        }

        return CFGetTypeID(value as CFTypeRef) == CFNullGetTypeID()
    }

    private func patchPlistNullSentinels(in data: inout Data) throws {
        guard data.count >= 40, Data(data.prefix(8)) == Data("bplist00".utf8) else {
            throw AerialLockScreenExportError.invalidWallpaperIndex(wallpaperIndexURL)
        }

        let trailerStart = data.count - 32
        let offsetIntSize = Int(data[trailerStart + 6])
        let objectCount = Int(readBigEndianUInt(in: data, at: trailerStart + 8, byteCount: 8))
        let offsetTableOffset = Int(readBigEndianUInt(in: data, at: trailerStart + 24, byteCount: 8))
        let sentinelBits = Self.plistNullSentinel.timeIntervalSinceReferenceDate.bitPattern

        guard offsetIntSize > 0, objectCount >= 0, offsetTableOffset < data.count else {
            throw AerialLockScreenExportError.invalidWallpaperIndex(wallpaperIndexURL)
        }

        for objectIndex in 0..<objectCount {
            let offsetEntry = offsetTableOffset + objectIndex * offsetIntSize
            guard offsetEntry + offsetIntSize <= data.count else {
                throw AerialLockScreenExportError.invalidWallpaperIndex(wallpaperIndexURL)
            }

            let objectOffset = Int(readBigEndianUInt(in: data, at: offsetEntry, byteCount: offsetIntSize))
            guard objectOffset + 9 <= data.count else {
                throw AerialLockScreenExportError.invalidWallpaperIndex(wallpaperIndexURL)
            }

            guard data[objectOffset] == 0x33 else {
                continue
            }

            let dateBits = readBigEndianUInt(in: data, at: objectOffset + 1, byteCount: 8)
            if dateBits == sentinelBits {
                data[objectOffset] = 0x00
            }
        }
    }

    private func readBigEndianUInt(in data: Data, at offset: Int, byteCount: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<byteCount {
            value = (value << 8) | UInt64(data[offset + index])
        }
        return value
    }

    private func encodedOptionValues() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: ["values": [:]],
            format: .binary,
            options: 0
        )
    }

    private func lockScreenSelectionKey(in scopeValue: [String: Any]) -> String {
        if scopeValue["Linked"] != nil || (scopeValue["Type"] as? String) == "linked" {
            return "Linked"
        }

        if scopeValue["Idle"] != nil {
            return "Idle"
        }

        if scopeValue["Desktop"] != nil {
            return "Desktop"
        }

        return "Idle"
    }

    private func scopeContainsAerialAsset(_ assetID: String, in scopeValue: [String: Any]?) -> Bool {
        guard let scopeValue else {
            return false
        }

        return ["Linked", "Idle", "Desktop"].contains { key in
            selectionContainsAerialAsset(assetID, in: scopeValue[key] as? [String: Any])
        }
    }

    private func selectionContainsAerialAsset(_ assetID: String, in selection: [String: Any]?) -> Bool {
        guard
            let selection,
            let content = selection["Content"] as? [String: Any],
            let choices = content["Choices"] as? [[String: Any]]
        else {
            return false
        }

        return choices.contains { choice in
            guard choice["Provider"] as? String == "com.apple.wallpaper.choice.aerials" else {
                return false
            }

            if let configuration = choice["Configuration"] as? Data,
               let decoded = try? PropertyListSerialization.propertyList(from: configuration, format: nil) as? [String: Any],
               decoded["assetID"] as? String == assetID {
                return true
            }

            return false
        }
    }

    private func plistContainsAerialAsset(_ assetID: String, in plist: [String: Any]) -> Bool {
        if scopeContainsAerialAsset(assetID, in: plist["SystemDefault"] as? [String: Any]) ||
            scopeContainsAerialAsset(assetID, in: plist["AllSpacesAndDisplays"] as? [String: Any]) {
            return true
        }

        guard let spaces = plist["Spaces"] as? [String: Any] else {
            return false
        }

        return spaces.values.contains { spaceValue in
            guard let space = spaceValue as? [String: Any] else {
                return false
            }

            if scopeContainsAerialAsset(assetID, in: space["Default"] as? [String: Any]) ||
                scopeContainsAerialAsset(assetID, in: space) {
                return true
            }

            guard let displays = space["Displays"] as? [String: Any] else {
                return false
            }
            return displays.values.contains { scopeContainsAerialAsset(assetID, in: $0 as? [String: Any]) }
        }
    }

    private func plistContainsAerialAsset(_ assetID: String, for displayID: DisplayID, in plist: [String: Any]) -> Bool {
        if let displays = plist["Displays"] as? [String: Any],
           scopeContainsAerialAsset(assetID, in: displays[displayID.uuid] as? [String: Any]) {
            return true
        }

        if spaceContainsAerialAsset(assetID, displayID: displayID, in: plist["Spaces"] as? [String: Any]) {
            return true
        }

        return scopeContainsAerialAsset(assetID, in: plist["AllSpacesAndDisplays"] as? [String: Any]) ||
            scopeContainsAerialAsset(assetID, in: plist["SystemDefault"] as? [String: Any])
    }

    private func spaceContainsAerialAsset(
        _ assetID: String,
        displayID: DisplayID,
        in spaces: [String: Any]?
    ) -> Bool {
        guard let spaces else {
            return false
        }

        return spaces.values.contains { spaceValue in
            guard let space = spaceValue as? [String: Any] else {
                return false
            }

            if let displays = space["Displays"] as? [String: Any],
               scopeContainsAerialAsset(assetID, in: displays[displayID.uuid] as? [String: Any]) {
                return true
            }

            return scopeContainsAerialAsset(assetID, in: space["Default"] as? [String: Any])
        }
    }

    private func canReuseGeneratedFile(at outputURL: URL, dependencyURLs: [URL]) -> Bool {
        guard
            fileManager.fileExists(atPath: outputURL.path),
            let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path),
            let fileSize = attributes[.size] as? NSNumber,
            fileSize.int64Value > 0,
            let outputDate = attributes[.modificationDate] as? Date
        else {
            return false
        }

        for dependencyURL in dependencyURLs {
            guard
                let dependencyAttributes = try? fileManager.attributesOfItem(atPath: dependencyURL.path),
                let dependencyDate = dependencyAttributes[.modificationDate] as? Date
            else {
                continue
            }

            if outputDate < dependencyDate {
                return false
            }
        }

        return true
    }

    private func backup(url: URL) throws -> URL {
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).livepaper-backup")
        try removeExistingFile(at: backupURL)
        try fileManager.copyItem(at: url, to: backupURL)
        return backupURL
    }

    private func restoreBackup(from backupURL: URL, to url: URL) {
        try? removeExistingFile(at: url)
        try? fileManager.copyItem(at: backupURL, to: url)
    }

    private func removeExistingFile(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func stopWallpaperServicesBeforeStoreUpdate() {
        runServiceCommand(["Wallpaper", "WallpaperAgent", "WallpaperAerialsExtension"])
    }

    private func restartWallpaperAgent() {
        runServiceCommand(["WallpaperAgent"])
    }

    nonisolated private static func runKillall(_ processNames: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = processNames
        try? process.run()
        process.waitUntilExit()
    }
}
