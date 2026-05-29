import AppKit
import Observation

@MainActor
@Observable
final class WallpaperCoordinator {
    private let runtime: WallpaperRuntime
    private let store: WallpaperSettingsStore
    private var savedConfigs: [DisplayID: SavedWallpaperConfig] = [:]
    private var library: [WallpaperContent] = []
    private var displayObserver: NSObjectProtocol?
    private var notificationObservers: [NSObjectProtocol] = []
    private var globalPauseReasons: Set<RuntimePauseReason> = []
    private var fullscreenDisplayIDs: Set<DisplayID> = []
    private var pausedDisplayIDs: Set<DisplayID> = []
    private var selectedContent: WallpaperContent?
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

    private(set) var displays: [DisplayState] = []
    private(set) var activeConfigs: [DisplayID: WallpaperConfig] = [:]
    private(set) var lastError: String?
    private(set) var steamDownloadLog = ""
    private(set) var selectedContentName: String?
    private(set) var selectedContentKind: WallpaperContent.Kind?
    var selectedGalleryItemID: WallpaperGalleryItem.ID? { selectedContent?.galleryID }
    var hasSavedWallpapers: Bool { !savedConfigs.isEmpty }
    var galleryItems: [WallpaperGalleryItem] {
        var seenIDs: Set<String> = []
        var items: [WallpaperGalleryItem] = []

        for content in library {
            let displayCount = savedConfigs.values.filter { $0.content.galleryID == content.galleryID }.count
            appendGalleryItem(for: content, displayCount: displayCount, to: &items, seenIDs: &seenIDs)
        }

        for savedConfig in savedConfigs.values.sorted(by: { $0.content.displayName < $1.content.displayName }) {
            let displayCount = savedConfigs.values.filter { $0.content.galleryID == savedConfig.content.galleryID }.count
            appendGalleryItem(for: savedConfig.content, displayCount: displayCount, to: &items, seenIDs: &seenIDs)
        }

        return items
    }

    var selectedDisplayIDs: Set<DisplayID> = []
    var scaleMode: ScaleMode = .fill
    var muted = false
    var volume = 1.0
    var pauseOnBattery = true
    var pauseOnFullscreen = true

    init(runtime: WallpaperRuntime? = nil, store: WallpaperSettingsStore? = nil) {
        self.runtime = runtime ?? InAppWallpaperRuntime()
        let resolvedStore = store ?? WallpaperSettingsStore()
        self.store = resolvedStore
        let preferences = resolvedStore.loadRuntimePreferences()
        scaleMode = preferences.scaleMode
        muted = preferences.muted
        volume = preferences.volume
        pauseOnBattery = preferences.pauseOnBattery
        pauseOnFullscreen = preferences.pauseOnFullscreen
        savedConfigs = resolvedStore.loadSavedConfigs()
        library = resolvedStore.loadLibrary()
        steamCMDURL = resolvedStore.loadSteamCMDURL()
        steamCMDLoginMode = resolvedStore.loadSteamCMDLoginMode()
        steamUsername = resolvedStore.loadSteamUsername()
        migrateSavedConfigsIntoLibrary()
        syncSteamMetadataFromLocalFiles()
        refreshDisplays()
        observeDisplayChanges()
        observeSystemPolicyChanges()
    }

    func shutdown() async {
        await stopAll()

        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
            self.displayObserver = nil
        }
        notificationObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        notificationObservers.removeAll()
    }

    func refreshDisplays() {
        displays = NSScreen.screens.compactMap(DisplayState.init(screen:))
        selectedDisplayIDs.formIntersection(Set(displays.map(\.id)))

        if selectedDisplayIDs.isEmpty, let firstDisplay = displays.first {
            selectedDisplayIDs = [firstDisplay.id]
        }
    }

    func selectVideo(url: URL) {
        select(content: .video(url), addToLibrary: true)
    }

    func selectWebPage(url: URL) {
        select(content: .webPage(url), addToLibrary: true)
    }

    func selectWebFolder(url: URL) {
        let indexURL = url.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            lastError = "Choose a folder containing index.html."
            return
        }

        select(content: .web(indexURL, readAccessURL: url), addToLibrary: true)
    }

    @discardableResult
    func importSteamWorkshop(url rawURL: String, fallbackFolderURL: URL? = nil) -> Error? {
        do {
            let importer = WallpaperEngineImporter()
            let result: WallpaperEngineImportResult
            if let fallbackFolderURL {
                result = try importer.importWorkshopItem(from: rawURL, fallbackFolderURL: fallbackFolderURL)
            } else {
                result = try importer.importWorkshopItem(from: rawURL)
            }
            select(content: result.content, addToLibrary: true)
            return nil
        } catch {
            lastError = error.localizedDescription
            return error
        }
    }

    @discardableResult
    func downloadSteamWorkshop(url rawURL: String) async -> Error? {
        resetSteamDownloadLog()
        do {
            let downloader = SteamCMDWorkshopDownloader(
                steamCMDURL: steamCMDURL,
                loginMode: steamCMDLoginMode,
                username: steamUsername
            )
            let folderURL = try await downloader.downloadWorkshopItem(from: rawURL) { [weak self] logChunk in
                await MainActor.run {
                    self?.appendSteamDownloadLog(logChunk)
                }
            }
            appendSteamDownloadLog("[LivePaper] Importing downloaded wallpaper.\n")
            let result = try WallpaperEngineImporter().importWorkshopItem(from: rawURL, fallbackFolderURL: folderURL)
            select(content: result.content, addToLibrary: true)
            appendSteamDownloadLog("[LivePaper] Imported: \(result.title ?? result.content.displayName)\n")
            return nil
        } catch {
            lastError = error.localizedDescription
            return error
        }
    }

    func setSteamCMDURL(_ url: URL) {
        steamCMDURL = url
        store.saveSteamCMDURL(url)
        lastError = nil
    }

    func clearSteamDownloadLog() {
        steamDownloadLog = ""
    }

    func syncSteamMetadata() {
        syncSteamMetadataFromLocalFiles()
        if let selectedContent {
            selectedContentName = selectedContent.displayName
            selectedContentKind = selectedContent.kind
        }
        lastError = nil
    }

    func selectGalleryItem(id: WallpaperGalleryItem.ID) {
        guard let content = (library + savedConfigs.values.map(\.content))
            .first(where: { $0.galleryID == id }) else {
            return
        }

        select(content: content, addToLibrary: false)
    }

    func applySelectedContent() async {
        refreshDisplays()
        saveRuntimePreferences()
        let targetIDs = selectedDisplayIDs.isEmpty ? Set(displays.map(\.id)) : selectedDisplayIDs

        do {
            guard let content = selectedContent else {
                lastError = "Choose content first."
                return
            }

            for displayID in targetIDs {
                let config = WallpaperConfig(
                    displayID: displayID,
                    content: content,
                    scaleMode: scaleMode,
                    volume: volume,
                    muted: muted,
                    pauseOnBattery: pauseOnBattery,
                    pauseOnFullscreen: pauseOnFullscreen
                )
                try await runtime.update(config: config)
                activeConfigs[displayID] = config
                pausedDisplayIDs.remove(displayID)
                savedConfigs[displayID] = SavedWallpaperConfig(
                    displayID: displayID,
                    content: content,
                    scaleMode: scaleMode,
                    volume: volume,
                    muted: muted,
                    pauseOnBattery: pauseOnBattery,
                    pauseOnFullscreen: pauseOnFullscreen
                )
            }
            store.save(configs: savedConfigs)
            await refreshRuntimePolicy()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restoreSavedWallpapers() async {
        refreshDisplays()
        let availableIDs = Set(displays.map(\.id))
        let targetConfigs = savedConfigs.filter { availableIDs.contains($0.key) }

        do {
            for (displayID, savedConfig) in targetConfigs {
                let config = WallpaperConfig(
                    displayID: displayID,
                    content: savedConfig.content,
                    scaleMode: savedConfig.scaleMode,
                    volume: savedConfig.volume,
                    muted: savedConfig.muted,
                    pauseOnBattery: savedConfig.pauseOnBattery,
                    pauseOnFullscreen: savedConfig.pauseOnFullscreen
                )
                try await runtime.update(config: config)
                activeConfigs[displayID] = config
                pausedDisplayIDs.remove(displayID)
            }
            await refreshRuntimePolicy()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopAll() async {
        await runtime.stopAll()
        activeConfigs.removeAll()
        pausedDisplayIDs.removeAll()
    }

    func forgetSavedWallpapers() async {
        await stopAll()
        savedConfigs.removeAll()
        store.removeAllConfigs()
    }

    func updateRuntimePreferences() async {
        saveRuntimePreferences()

        do {
            for (displayID, activeConfig) in activeConfigs {
                let config = WallpaperConfig(
                    displayID: displayID,
                    content: activeConfig.content,
                    scaleMode: scaleMode,
                    volume: volume,
                    muted: muted,
                    pauseOnBattery: pauseOnBattery,
                    pauseOnFullscreen: pauseOnFullscreen
                )
                try await runtime.update(config: config)
                activeConfigs[displayID] = config

                if savedConfigs[displayID] != nil {
                    savedConfigs[displayID] = SavedWallpaperConfig(
                        displayID: displayID,
                        content: activeConfig.content,
                        scaleMode: scaleMode,
                        volume: volume,
                        muted: muted,
                        pauseOnBattery: pauseOnBattery,
                        pauseOnFullscreen: pauseOnFullscreen
                    )
                }
            }
            store.save(configs: savedConfigs)
            await refreshRuntimePolicy()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func saveRuntimePreferences() {
        store.saveRuntimePreferences(
            RuntimePreferences(
                scaleMode: scaleMode,
                muted: muted,
                volume: volume,
                pauseOnBattery: pauseOnBattery,
                pauseOnFullscreen: pauseOnFullscreen
            )
        )
    }

    private func resetSteamDownloadLog() {
        steamDownloadLog = ""
        lastError = nil
    }

    private func appendSteamDownloadLog(_ chunk: String) {
        steamDownloadLog += chunk

        let maxLogCharacterCount = 20_000
        if steamDownloadLog.count > maxLogCharacterCount {
            steamDownloadLog = String(steamDownloadLog.suffix(maxLogCharacterCount))
        }
    }

    private func select(content: WallpaperContent, addToLibrary: Bool) {
        if addToLibrary {
            addLibraryItem(content)
        }

        selectedContent = content
        selectedContentName = content.displayName
        selectedContentKind = content.kind
        lastError = nil
    }

    private func addLibraryItem(_ content: WallpaperContent) {
        if let existingIndex = library.firstIndex(where: { $0.galleryID == content.galleryID }) {
            let mergedContent = library[existingIndex].mergingMetadata(from: content)
            if mergedContent != library[existingIndex] {
                library[existingIndex] = mergedContent
                store.save(library: library)
            }
            return
        }

        library.insert(content, at: 0)
        store.save(library: library)
    }

    private func migrateSavedConfigsIntoLibrary() {
        let savedContents = savedConfigs.values
            .map(\.content)
            .sorted { $0.displayName < $1.displayName }
        var didChange = false

        for content in savedContents where !library.contains(where: { $0.galleryID == content.galleryID }) {
            library.append(content)
            didChange = true
        }

        if didChange {
            store.save(library: library)
        }
    }

    private func syncSteamMetadataFromLocalFiles() {
        let importer = WallpaperEngineImporter()
        var didChangeLibrary = false
        var didChangeConfigs = false

        library = library.map { content in
            let syncedContent = importer.synchronizedSteamMetadata(for: content)
            didChangeLibrary = didChangeLibrary || syncedContent != content
            return syncedContent
        }

        for (displayID, config) in savedConfigs {
            let syncedContent = importer.synchronizedSteamMetadata(for: config.content)
            guard syncedContent != config.content else {
                continue
            }

            savedConfigs[displayID] = SavedWallpaperConfig(
                displayID: config.displayID,
                content: syncedContent,
                scaleMode: config.scaleMode,
                volume: config.volume,
                muted: config.muted,
                pauseOnBattery: config.pauseOnBattery,
                pauseOnFullscreen: config.pauseOnFullscreen
            )
            didChangeConfigs = true
        }

        if let selectedContent {
            self.selectedContent = importer.synchronizedSteamMetadata(for: selectedContent)
        }

        if didChangeLibrary {
            store.save(library: library)
        }
        if didChangeConfigs {
            store.save(configs: savedConfigs)
        }
    }

    private func appendGalleryItem(
        for content: WallpaperContent,
        displayCount: Int,
        to items: inout [WallpaperGalleryItem],
        seenIDs: inout Set<String>
    ) {
        guard seenIDs.insert(content.galleryID).inserted else {
            return
        }

        items.append(
            WallpaperGalleryItem(
                id: content.galleryID,
                title: content.displayName,
                kind: content.kind,
                url: content.url,
                previewImageURL: content.previewImageURL,
                sourceURL: content.sourceURL,
                steamWorkshopID: content.steamWorkshopID,
                savedDisplayCount: displayCount
            )
        )
    }

    private func observeDisplayChanges() {
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reconcileDisplays()
            }
        }
    }

    private func observeSystemPolicyChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        notificationObservers = [
            workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.setGlobalPauseReason(.systemSleep, isActive: true)
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.setGlobalPauseReason(.systemSleep, isActive: false)
                    await self?.refreshRuntimePolicy()
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.setGlobalPauseReason(.screenSleep, isActive: true)
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.setGlobalPauseReason(.screenSleep, isActive: false)
                    await self?.refreshRuntimePolicy()
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.setGlobalPauseReason(.locked, isActive: true)
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.setGlobalPauseReason(.locked, isActive: false)
                    await self?.refreshRuntimePolicy()
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshRuntimePolicy()
                }
            }
        ]
    }

    private func reconcileDisplays() async {
        let previousDisplayIDs = Set(displays.map(\.id))
        refreshDisplays()
        let currentDisplayIDs = Set(displays.map(\.id))
        let removedDisplayIDs = previousDisplayIDs.subtracting(currentDisplayIDs)

        for displayID in removedDisplayIDs {
            await runtime.stop(displayID: displayID)
            activeConfigs.removeValue(forKey: displayID)
            pausedDisplayIDs.remove(displayID)
        }

        await restoreSavedWallpapersForReappearedDisplays()
        await refreshRuntimePolicy()
    }

    private func restoreSavedWallpapersForReappearedDisplays() async {
        let activeDisplayIDs = Set(activeConfigs.keys)
        let availableDisplayIDs = Set(displays.map(\.id))
        let restoreDisplayIDs = Set(savedConfigs.keys)
            .intersection(availableDisplayIDs)
            .subtracting(activeDisplayIDs)

        for displayID in restoreDisplayIDs {
            guard let savedConfig = savedConfigs[displayID] else {
                continue
            }

            do {
                let config = WallpaperConfig(
                    displayID: displayID,
                    content: savedConfig.content,
                    scaleMode: savedConfig.scaleMode,
                    volume: savedConfig.volume,
                    muted: savedConfig.muted,
                    pauseOnBattery: savedConfig.pauseOnBattery,
                    pauseOnFullscreen: savedConfig.pauseOnFullscreen
                )
                try await runtime.update(config: config)
                activeConfigs[displayID] = config
                pausedDisplayIDs.remove(displayID)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func setGlobalPauseReason(_ reason: RuntimePauseReason, isActive: Bool) async {
        if isActive {
            globalPauseReasons.insert(reason)
        } else {
            globalPauseReasons.remove(reason)
        }

        await applyRuntimePolicy()
    }

    private func refreshRuntimePolicy() async {
        fullscreenDisplayIDs = FullscreenWindowDetector.coveredDisplayIDs()

        if SystemPowerState.isOnBatteryPower {
            globalPauseReasons.insert(.battery)
        } else {
            globalPauseReasons.remove(.battery)
        }

        await applyRuntimePolicy()
    }

    private func applyRuntimePolicy() async {
        let activeDisplayIDs = Set(activeConfigs.keys)
        pausedDisplayIDs.formIntersection(activeDisplayIDs)

        for (displayID, config) in activeConfigs {
            let shouldPause = !pauseReasons(for: displayID, config: config).isEmpty

            if shouldPause, !pausedDisplayIDs.contains(displayID) {
                await runtime.pause(displayID: displayID)
                pausedDisplayIDs.insert(displayID)
            } else if !shouldPause, pausedDisplayIDs.contains(displayID) {
                await runtime.resume(displayID: displayID)
                pausedDisplayIDs.remove(displayID)
            }
        }
    }

    private func pauseReasons(for displayID: DisplayID, config: WallpaperConfig) -> Set<RuntimePauseReason> {
        var reasons = globalPauseReasons

        if globalPauseReasons.contains(.battery), !config.pauseOnBattery {
            reasons.remove(.battery)
        }

        if fullscreenDisplayIDs.contains(displayID), config.pauseOnFullscreen {
            reasons.insert(.fullscreen)
        }

        return reasons
    }
}

struct DisplayState: Identifiable, Hashable, Sendable {
    let id: DisplayID
    let name: String
    let frameDescription: String

    init?(screen: NSScreen) {
        guard let id = screen.livePaperDisplayID else {
            return nil
        }
        self.id = id
        self.name = screen.localizedName
        self.frameDescription = "\(Int(screen.frame.width)) x \(Int(screen.frame.height))"
    }
}

struct WallpaperGalleryItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kind: WallpaperContent.Kind
    let url: URL
    let previewImageURL: URL?
    let sourceURL: URL?
    let steamWorkshopID: String?
    let savedDisplayCount: Int

    var subtitle: String {
        let mediaType: String
        switch kind {
        case .video:
            mediaType = "Video"
        case .web:
            mediaType = url.isFileURL ? "Web folder" : "Web page"
        }

        if steamWorkshopID != nil {
            return "Steam Workshop - \(mediaType)"
        }
        return mediaType
    }
}

private extension WallpaperContent {
    var galleryID: String {
        "\(kind.rawValue):\(url.absoluteString)"
    }
}
