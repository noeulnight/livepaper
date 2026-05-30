import XCTest
@testable import LivePaper

final class AerialLockScreenExporterTests: XCTestCase {
    func testSupportsOnlyLocalVideoContent() {
        let exporter = AerialLockScreenExporter()

        XCTAssertTrue(exporter.supportsExport(.video(URL(fileURLWithPath: "/tmp/wallpaper.mov"))))
        XCTAssertFalse(exporter.supportsExport(.web(URL(fileURLWithPath: "/tmp/web/index.html"))))
        XCTAssertFalse(exporter.supportsExport(.webPage(URL(string: "https://example.com")!)))
    }

    func testSelectExportedAssetRunsStoreUpdateServiceCommand() throws {
        let targetDisplayID = DisplayID(uuid: "TARGET-DISPLAY")
        let otherDisplayID = DisplayID(uuid: "OTHER-DISPLAY")
        let store = try wallpaperStore(indexPlist: wallpaperIndexPlist(
            systemDefaultAssetID: "ORIGINAL-ASSET",
            targetDisplayID: targetDisplayID,
            otherDisplayID: otherDisplayID
        ))
        var serviceCommands: [[String]] = []
        let exporter = AerialLockScreenExporter(
            homeDirectory: store.homeDirectory,
            runServiceCommand: { serviceCommands.append($0) }
        )

        try exporter.selectExportedAsset(assetID: "NEW-ASSET", displayID: targetDisplayID)

        XCTAssertEqual(serviceCommands, [["Wallpaper", "WallpaperAgent", "WallpaperAerialsExtension"]])
    }

    func testSelectExportedAssetUpdatesOnlyTargetDisplay() throws {
        let targetDisplayID = DisplayID(uuid: "TARGET-DISPLAY")
        let otherDisplayID = DisplayID(uuid: "OTHER-DISPLAY")
        let originalAssetID = "ORIGINAL-ASSET"
        let newAssetID = "NEW-ASSET"
        let context = try exporterContext(indexPlist: wallpaperIndexPlist(
            systemDefaultAssetID: originalAssetID,
            targetDisplayID: targetDisplayID,
            otherDisplayID: otherDisplayID
        ))

        try context.exporter.selectExportedAsset(assetID: newAssetID, displayID: targetDisplayID)

        let updated = try wallpaperIndex(at: context.indexURL)

        XCTAssertEqual(try assetID(in: updated, path: ["SystemDefault"], selectionKey: "Linked"), originalAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Displays", targetDisplayID.uuid], selectionKey: "Linked"), newAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Displays", otherDisplayID.uuid], selectionKey: "Linked"), originalAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Spaces", "SPACE-1", "Displays", targetDisplayID.uuid], selectionKey: "Linked"), newAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Spaces", "SPACE-1", "Displays", otherDisplayID.uuid], selectionKey: "Linked"), originalAssetID)
    }

    func testSelectExportedAssetPreservesDifferentAssetsPerDisplay() throws {
        let firstDisplayID = DisplayID(uuid: "FIRST-DISPLAY")
        let secondDisplayID = DisplayID(uuid: "SECOND-DISPLAY")
        let firstAssetID = "FIRST-ASSET"
        let secondAssetID = "SECOND-ASSET"
        let context = try exporterContext(indexPlist: wallpaperIndexPlist(
            systemDefaultAssetID: "ORIGINAL-ASSET",
            targetDisplayID: firstDisplayID,
            otherDisplayID: secondDisplayID
        ))

        try context.exporter.selectExportedAsset(assetID: firstAssetID, displayID: firstDisplayID)
        try context.exporter.selectExportedAsset(assetID: secondAssetID, displayID: secondDisplayID)

        let updated = try wallpaperIndex(at: context.indexURL)

        XCTAssertEqual(try assetID(in: updated, path: ["Displays", firstDisplayID.uuid], selectionKey: "Linked"), firstAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Displays", secondDisplayID.uuid], selectionKey: "Linked"), secondAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Spaces", "SPACE-1", "Displays", firstDisplayID.uuid], selectionKey: "Linked"), firstAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Spaces", "SPACE-1", "Displays", secondDisplayID.uuid], selectionKey: "Linked"), secondAssetID)
    }

    func testSelectExportedAssetsWritesDifferentDisplaysInOnePass() throws {
        let firstDisplayID = DisplayID(uuid: "FIRST-DISPLAY")
        let secondDisplayID = DisplayID(uuid: "SECOND-DISPLAY")
        let firstAssetID = "FIRST-ASSET"
        let secondAssetID = "SECOND-ASSET"
        let context = try exporterContext(indexPlist: wallpaperIndexPlist(
            systemDefaultAssetID: "ORIGINAL-ASSET",
            targetDisplayID: firstDisplayID,
            otherDisplayID: secondDisplayID
        ))

        try context.exporter.selectExportedAssets([
            (displayID: firstDisplayID, assetID: firstAssetID),
            (displayID: secondDisplayID, assetID: secondAssetID)
        ])

        let updated = try wallpaperIndex(at: context.indexURL)

        XCTAssertEqual(try assetID(in: updated, path: ["Displays", firstDisplayID.uuid], selectionKey: "Linked"), firstAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Displays", secondDisplayID.uuid], selectionKey: "Linked"), secondAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Spaces", "SPACE-1", "Displays", firstDisplayID.uuid], selectionKey: "Linked"), firstAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Spaces", "SPACE-1", "Displays", secondDisplayID.uuid], selectionKey: "Linked"), secondAssetID)
    }

    func testSelectExportedAssetUpdatesIdleWhenWallpaperAndLockScreenAreSeparate() throws {
        let displayID = DisplayID(uuid: "TARGET-DISPLAY")
        let originalAssetID = "ORIGINAL-ASSET"
        let desktopAssetID = "DESKTOP-ASSET"
        let newAssetID = "NEW-ASSET"
        let context = try exporterContext(indexPlist: [
            "Displays": [
                displayID.uuid: individualScope(idleAssetID: originalAssetID, desktopAssetID: desktopAssetID)
            ]
        ])

        try context.exporter.selectExportedAsset(assetID: newAssetID, displayID: displayID)

        let updated = try wallpaperIndex(at: context.indexURL)

        XCTAssertEqual(try assetID(in: updated, path: ["Displays", displayID.uuid], selectionKey: "Idle"), newAssetID)
        XCTAssertEqual(try assetID(in: updated, path: ["Displays", displayID.uuid], selectionKey: "Desktop"), desktopAssetID)
    }

    func testSelectExportedAssetUpdatesGlobalFallbackWhenNoDisplayScopesExist() throws {
        let displayID = DisplayID(uuid: "TARGET-DISPLAY")
        let originalAssetID = "ORIGINAL-ASSET"
        let newAssetID = "NEW-ASSET"
        let context = try exporterContext(indexPlist: [
            "SystemDefault": linkedScope(assetID: originalAssetID),
            "AllSpacesAndDisplays": linkedScope(assetID: originalAssetID),
            "Displays": [:],
            "Spaces": [:]
        ])

        try context.exporter.selectExportedAsset(assetID: newAssetID, displayID: displayID)

        let updated = try wallpaperIndex(at: context.indexURL)

        XCTAssertEqual(try assetID(in: updated, path: ["SystemDefault"], selectionKey: "Linked"), originalAssetID)
        XCTAssertTrue(isPlistNull(updated["AllSpacesAndDisplays"]))
        let displays = try XCTUnwrap(updated["Displays"] as? [String: Any])
        XCTAssertNotNil(displays[displayID.uuid])
        XCTAssertEqual(try assetID(in: updated, path: ["Displays", displayID.uuid], selectionKey: "Linked"), newAssetID)
        XCTAssertTrue(try encodedOptionValues(in: updated, path: ["Displays", displayID.uuid], selectionKey: "Linked").isEmpty)
    }

    func testIsExportSelectedAcceptsGlobalFallbackForDisplay() throws {
        let content = WallpaperContent.video(URL(fileURLWithPath: "/tmp/livepaper-selection.mov"))
        let assetID = stableAssetID(for: content)
        let displayID = DisplayID(uuid: "TARGET-DISPLAY")
        let context = try exporterContext(indexPlist: [
            "SystemDefault": linkedScope(assetID: assetID),
            "AllSpacesAndDisplays": linkedScope(assetID: assetID),
            "Displays": [:],
            "Spaces": [:]
        ])

        XCTAssertTrue(context.exporter.isExportSelected(content: content, displayIDs: [displayID]))
    }

    func testIsExportSelectedAcceptsSpaceDefaultForDisplay() throws {
        let content = WallpaperContent.video(URL(fileURLWithPath: "/tmp/livepaper-space-selection.mov"))
        let assetID = stableAssetID(for: content)
        let displayID = DisplayID(uuid: "TARGET-DISPLAY")
        let context = try exporterContext(indexPlist: [
            "SystemDefault": linkedScope(assetID: "OTHER-ASSET"),
            "AllSpacesAndDisplays": linkedScope(assetID: "OTHER-ASSET"),
            "Displays": [:],
            "Spaces": [
                "SPACE-1": [
                    "Default": linkedScope(assetID: assetID),
                    "Displays": [:]
                ]
            ]
        ])

        XCTAssertTrue(context.exporter.isExportSelected(content: content, displayIDs: [displayID]))
    }

    private func exporterContext(indexPlist: [String: Any]) throws -> (
        exporter: AerialLockScreenExporter,
        indexURL: URL
    ) {
        let store = try wallpaperStore(indexPlist: indexPlist)
        return (
            AerialLockScreenExporter(homeDirectory: store.homeDirectory, runServiceCommand: { _ in }),
            store.indexURL
        )
    }

    private func wallpaperStore(indexPlist: [String: Any]) throws -> (homeDirectory: URL, indexURL: URL) {
        let homeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeDirectory = homeDirectory
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        let indexURL = storeDirectory.appendingPathComponent("Index.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: indexPlist, format: .binary, options: 0)
        try data.write(to: indexURL)
        return (homeDirectory, indexURL)
    }

    private func wallpaperIndex(at indexURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: indexURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func wallpaperIndexPlist(
        systemDefaultAssetID: String,
        targetDisplayID: DisplayID,
        otherDisplayID: DisplayID
    ) -> [String: Any] {
        [
            "SystemDefault": linkedScope(assetID: systemDefaultAssetID),
            "AllSpacesAndDisplays": linkedScope(assetID: systemDefaultAssetID),
            "Displays": [
                targetDisplayID.uuid: linkedScope(assetID: systemDefaultAssetID),
                otherDisplayID.uuid: linkedScope(assetID: systemDefaultAssetID)
            ],
            "Spaces": [
                "SPACE-1": [
                    "Displays": [
                        targetDisplayID.uuid: linkedScope(assetID: systemDefaultAssetID),
                        otherDisplayID.uuid: linkedScope(assetID: systemDefaultAssetID)
                    ]
                ]
            ]
        ]
    }

    private func linkedScope(assetID: String) -> [String: Any] {
        [
            "Type": "linked",
            "Linked": selection(assetID: assetID)
        ]
    }

    private func individualScope(idleAssetID: String, desktopAssetID: String) -> [String: Any] {
        [
            "Type": "individual",
            "Desktop": selection(assetID: desktopAssetID),
            "Idle": selection(assetID: idleAssetID)
        ]
    }

    private func selection(assetID: String) -> [String: Any] {
        [
            "Content": [
                "Choices": [[
                    "Configuration": configurationData(assetID: assetID),
                    "Files": [],
                    "Provider": "com.apple.wallpaper.choice.aerials"
                ]]
            ]
        ]
    }

    private func configurationData(assetID: String) -> Data {
        try! PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )
    }

    private func stableAssetID(for content: WallpaperContent) -> String {
        let value: String
        if let steamWorkshopID = content.steamWorkshopID {
            value = "steam-\(steamWorkshopID)"
        } else {
            value = content.url.standardizedFileURL.path
        }

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

    private func assetID(in plist: [String: Any], path: [String], selectionKey: String) throws -> String {
        let choice = try choice(in: plist, path: path, selectionKey: selectionKey)
        let configurationData = try XCTUnwrap(choice["Configuration"] as? Data)
        let configuration = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: configurationData, format: nil) as? [String: Any]
        )
        return try XCTUnwrap(configuration["assetID"] as? String)
    }

    private func isPlistNull(_ value: Any?) -> Bool {
        guard let value else {
            return false
        }
        if value is NSNull {
            return true
        }
        return CFGetTypeID(value as CFTypeRef) == CFNullGetTypeID()
    }

    private func encodedOptionValues(
        in plist: [String: Any],
        path: [String],
        selectionKey: String
    ) throws -> [String: Any] {
        var value: Any = plist
        for key in path {
            value = try XCTUnwrap((value as? [String: Any])?[key])
        }
        let scope = try XCTUnwrap(value as? [String: Any])
        let selection = try XCTUnwrap(scope[selectionKey] as? [String: Any])
        let content = try XCTUnwrap(selection["Content"] as? [String: Any])
        let encoded = try XCTUnwrap(content["EncodedOptionValues"] as? Data)
        let decoded = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any]
        )
        return try XCTUnwrap(decoded["values"] as? [String: Any])
    }

    private func choice(in plist: [String: Any], path: [String], selectionKey: String) throws -> [String: Any] {
        var value: Any = plist
        for key in path {
            value = try XCTUnwrap((value as? [String: Any])?[key])
        }
        let scope = try XCTUnwrap(value as? [String: Any])
        let selection = try XCTUnwrap(scope[selectionKey] as? [String: Any])
        let content = try XCTUnwrap(selection["Content"] as? [String: Any])
        let choices = try XCTUnwrap(content["Choices"] as? [[String: Any]])
        return try XCTUnwrap(choices.first)
    }
}
