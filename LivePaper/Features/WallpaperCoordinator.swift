import AppKit
import Observation

@MainActor
@Observable
final class WallpaperCoordinator {
    private let store: WallpaperSettingsStore
    private let libraryModel: WallpaperLibraryModel
    private let displaySelection: DisplaySelectionModel
    private let runtimeController: WallpaperRuntimeController
    private let policyController: RuntimePolicyController
    private let steamController: SteamWorkshopController

    private var savedConfigs: [DisplayID: SavedWallpaperConfig]
    private var displayObserver: NSObjectProtocol?

    private(set) var lastError: String?

    var selectedDisplayIDs: Set<DisplayID> {
        get { displaySelection.selectedDisplayIDs }
        set { displaySelection.selectedDisplayIDs = newValue }
    }

    var displays: [DisplayState] { displaySelection.displays }
    var activeConfigs: [DisplayID: WallpaperConfig] { runtimeController.activeConfigs }
    var steamDownloadLog: String { steamController.steamDownloadLog }
    var selectedContentName: String? { libraryModel.selectedContentName }
    var selectedContentKind: WallpaperContent.Kind? { libraryModel.selectedContentKind }
    var selectedGalleryItemID: WallpaperGalleryItem.ID? { libraryModel.selectedGalleryItemID }
    var hasSavedWallpapers: Bool { !savedConfigs.isEmpty }
    var galleryItems: [WallpaperGalleryItem] { libraryModel.galleryItems(savedConfigs: savedConfigs) }

    var scaleMode: ScaleMode = .fill
    var muted = false
    var volume = 1.0
    var pauseOnBattery = true
    var pauseOnFullscreen = true
    var muteOnFullscreen = false

    var audioDisplayID: DisplayID? {
        get { displaySelection.audioDisplayID }
        set { displaySelection.audioDisplayID = newValue }
    }

    var steamCMDLoginMode: SteamCMDLoginMode {
        get { steamController.steamCMDLoginMode }
        set { steamController.steamCMDLoginMode = newValue }
    }

    var steamUsername: String {
        get { steamController.steamUsername }
        set { steamController.steamUsername = newValue }
    }

    init(runtime: WallpaperRuntime? = nil, store: WallpaperSettingsStore? = nil) {
        let resolvedStore = store ?? WallpaperSettingsStore()
        let resolvedRuntime = runtime ?? InAppWallpaperRuntime()
        let loadedSavedConfigs = resolvedStore.loadSavedConfigs()
        let loadedPreferences = resolvedStore.loadRuntimePreferences()

        self.store = resolvedStore
        self.savedConfigs = loadedSavedConfigs
        self.libraryModel = WallpaperLibraryModel(store: resolvedStore, savedConfigs: loadedSavedConfigs)
        self.displaySelection = DisplaySelectionModel()
        self.runtimeController = WallpaperRuntimeController(runtime: resolvedRuntime)
        self.policyController = RuntimePolicyController()
        self.steamController = SteamWorkshopController(store: resolvedStore)

        scaleMode = loadedPreferences.scaleMode
        muted = loadedPreferences.muted
        volume = loadedPreferences.volume
        displaySelection.audioDisplayID = loadedPreferences.audioDisplayID
        pauseOnBattery = loadedPreferences.pauseOnBattery
        pauseOnFullscreen = loadedPreferences.pauseOnFullscreen
        muteOnFullscreen = loadedPreferences.muteOnFullscreen

        libraryModel.syncSteamMetadataFromLocalFiles(savedConfigs: &savedConfigs)
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
        policyController.shutdown()
    }

    func refreshDisplays() {
        displaySelection.refreshDisplays()
    }

    func selectVideo(url: URL) {
        select(content: .video(url).withSecurityScopedBookmarks(), addToLibrary: true)
    }

    func selectVideo(url: URL, title: String?, previewImageURL: URL?) {
        select(
            content: WallpaperContent
                .video(url)
                .withSecurityScopedBookmarks()
                .withMetadata(title: title, previewImageURL: previewImageURL),
            addToLibrary: true
        )
    }

    func selectWebPage(url: URL) {
        select(content: .webPage(url), addToLibrary: true)
    }

    func selectWebPage(url: URL, title: String?, previewImageURL: URL?) {
        select(
            content: WallpaperContent
                .webPage(url)
                .withMetadata(title: title, previewImageURL: previewImageURL, sourceURL: url),
            addToLibrary: true
        )
    }

    func selectWebFolder(url: URL) {
        let indexURL = url.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            lastError = "Choose a folder containing index.html."
            return
        }

        select(content: WallpaperContent.web(indexURL, readAccessURL: url).withSecurityScopedBookmarks(), addToLibrary: true)
    }

    @discardableResult
    func importSteamWorkshop(url rawURL: String, fallbackFolderURL: URL? = nil) -> Error? {
        do {
            select(content: try steamController.importWorkshop(url: rawURL, fallbackFolderURL: fallbackFolderURL), addToLibrary: true)
            return nil
        } catch {
            lastError = error.localizedDescription
            return error
        }
    }

    @discardableResult
    func downloadSteamWorkshop(url rawURL: String) async -> Error? {
        do {
            select(content: try await steamController.downloadWorkshop(url: rawURL), addToLibrary: true)
            return nil
        } catch {
            lastError = error.localizedDescription
            return error
        }
    }

    func setSteamCMDURL(_ url: URL) {
        steamController.setSteamCMDURL(url)
        lastError = nil
    }

    func clearSteamDownloadLog() {
        steamController.clearDownloadLog()
    }

    func clearLastError() {
        lastError = nil
    }

    func syncSteamMetadata() {
        libraryModel.syncSteamMetadataFromLocalFiles(savedConfigs: &savedConfigs)
        lastError = nil
    }

    func selectGalleryItem(id: WallpaperGalleryItem.ID) {
        libraryModel.selectGalleryItem(id: id, savedConfigs: savedConfigs)
        lastError = nil
    }

    func applySelectedContent() async {
        refreshDisplays()
        saveRuntimePreferences()
        let targetIDs = selectedDisplayIDs.isEmpty ? Set(displays.map(\.id)) : selectedDisplayIDs

        do {
            guard let content = libraryModel.selectedContent else {
                lastError = "Choose content first."
                return
            }

            var updatedConfigs = activeConfigs
            let orderedTargetIDs = displaySelection.orderedDisplayIDs(from: targetIDs)

            for displayID in orderedTargetIDs {
                let config = desiredConfig(displayID: displayID, content: content)
                updatedConfigs[displayID] = config
                runtimeController.removePausedDisplay(displayID)
                savedConfigs[displayID] = WallpaperRuntimeController.savedConfig(from: config)
            }

            try await applyRuntimeConfigs(updatedConfigs)
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
            var updatedConfigs = activeConfigs
            for displayID in displaySelection.orderedDisplayIDs(from: Set(targetConfigs.keys)) {
                guard let savedConfig = targetConfigs[displayID] else {
                    continue
                }
                updatedConfigs[displayID] = WallpaperRuntimeController.desiredConfig(from: savedConfig)
                runtimeController.removePausedDisplay(displayID)
            }

            try await applyRuntimeConfigs(updatedConfigs)
            await refreshRuntimePolicy()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setDisplayEnabled(displayID: DisplayID, isEnabled: Bool) async {
        refreshDisplays()

        guard displays.contains(where: { $0.id == displayID }) else {
            lastError = "Display not found."
            return
        }

        if isEnabled {
            await enableDisplay(displayID)
        } else {
            await disableDisplay(displayID)
        }
    }

    func setAudioDisplay(_ displayID: DisplayID) async {
        refreshDisplays()

        guard displays.contains(where: { $0.id == displayID }) else {
            lastError = "Display not found."
            return
        }

        audioDisplayID = displayID
        saveRuntimePreferences()
        await refreshActiveRuntimeConfigs()
    }

    func isDisplayEnabled(_ displayID: DisplayID) -> Bool {
        activeConfigs[displayID] != nil
    }

    func activeContentName(for displayID: DisplayID) -> String? {
        activeConfigs[displayID]?.content.displayName
    }

    func savedContentName(for displayID: DisplayID) -> String? {
        savedConfigs[displayID]?.content.displayName
    }

    func displayWallpaperItem(for displayID: DisplayID) -> WallpaperGalleryItem? {
        let content = activeConfigs[displayID]?.content ?? savedConfigs[displayID]?.content
        guard let content else {
            return nil
        }

        return WallpaperGalleryItem(
            id: content.galleryID,
            title: content.displayName,
            kind: content.kind,
            url: content.url,
            previewImageURL: content.previewImageURL,
            sourceURL: content.sourceURL,
            steamWorkshopID: content.steamWorkshopID,
            savedDisplayCount: savedConfigs.values.filter { $0.content.galleryID == content.galleryID }.count
        )
    }

    func stopAll() async {
        await runtimeController.stopAll()
    }

    func forgetSavedWallpapers() async {
        await stopAll()
        savedConfigs.removeAll()
        store.removeAllConfigs()
    }

    func deleteGalleryItem(id: WallpaperGalleryItem.ID) async {
        let displayIDsToStop = activeConfigs
            .filter { $0.value.content.galleryID == id }
            .map(\.key)
        for displayID in displayIDsToStop {
            await runtimeController.stop(displayID: displayID)
        }
        await refreshActiveRuntimeConfigs()

        libraryModel.deleteGalleryItem(id: id, savedConfigs: &savedConfigs)
        lastError = nil
    }

    func updateRuntimePreferences() async {
        saveRuntimePreferences()

        do {
            var updatedConfigs = activeConfigs
            for (displayID, activeConfig) in activeConfigs {
                let config = desiredConfig(displayID: displayID, content: activeConfig.content)
                updatedConfigs[displayID] = config

                if savedConfigs[displayID] != nil {
                    savedConfigs[displayID] = WallpaperRuntimeController.savedConfig(from: config)
                }
            }

            try await applyRuntimeConfigs(updatedConfigs)
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
                audioDisplayID: audioDisplayID,
                pauseOnBattery: pauseOnBattery,
                pauseOnFullscreen: pauseOnFullscreen,
                muteOnFullscreen: muteOnFullscreen
            )
        )
    }

    private func enableDisplay(_ displayID: DisplayID) async {
        guard activeConfigs[displayID] == nil else {
            lastError = nil
            return
        }

        let config: WallpaperConfig
        if let savedConfig = savedConfigs[displayID] {
            config = WallpaperRuntimeController.desiredConfig(from: savedConfig)
        } else if let selectedContent = libraryModel.selectedContent {
            config = desiredConfig(displayID: displayID, content: selectedContent)
            savedConfigs[displayID] = WallpaperRuntimeController.savedConfig(from: config)
            store.save(configs: savedConfigs)
        } else {
            lastError = "Choose a wallpaper first."
            return
        }

        do {
            var updatedConfigs = activeConfigs
            updatedConfigs[displayID] = config
            runtimeController.removePausedDisplay(displayID)
            try await applyRuntimeConfigs(updatedConfigs)
            await refreshRuntimePolicy()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func disableDisplay(_ displayID: DisplayID) async {
        await runtimeController.stop(displayID: displayID)
        savedConfigs.removeValue(forKey: displayID)
        store.save(configs: savedConfigs)

        if audioDisplayID == displayID {
            audioDisplayID = displaySelection.fallbackAudioDisplayID(activeDisplayIDs: Set(activeConfigs.keys))
            saveRuntimePreferences()
        }

        await refreshActiveRuntimeConfigs()
    }

    private func desiredConfig(displayID: DisplayID, content: WallpaperContent) -> WallpaperConfig {
        WallpaperRuntimeController.desiredConfig(
            displayID: displayID,
            content: content,
            scaleMode: scaleMode,
            volume: volume,
            muted: muted,
            pauseOnBattery: pauseOnBattery,
            pauseOnFullscreen: pauseOnFullscreen,
            muteOnFullscreen: muteOnFullscreen
        )
    }

    private func applyRuntimeConfigs(_ desiredConfigs: [DisplayID: WallpaperConfig]) async throws {
        let audioOwnerID = displaySelection.audioOwnerID(
            activeDisplayIDs: Set(desiredConfigs.keys),
            muted: muted
        )
        try await runtimeController.applyRuntimeConfigs(
            desiredConfigs,
            audioOwnerID: audioOwnerID,
            fullscreenDisplayIDs: policyController.fullscreenDisplayIDs,
            orderedDisplayIDs: displaySelection.orderedDisplayIDs
        )
    }

    private func refreshActiveRuntimeConfigs() async {
        do {
            try await applyRuntimeConfigs(activeConfigs)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func runtimeConfig(from config: WallpaperConfig, audioOwnerID: DisplayID?) -> WallpaperConfig {
        WallpaperRuntimeController.runtimeConfig(
            from: config,
            audioOwnerID: audioOwnerID,
            fullscreenDisplayIDs: policyController.fullscreenDisplayIDs
        )
    }

    private func select(content: WallpaperContent, addToLibrary: Bool) {
        libraryModel.select(content: content, addToLibrary: addToLibrary)
        lastError = nil
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
        policyController.observeSystemPolicyChanges(
            refreshPolicy: { [weak self] in
                guard let self else { return }
                await self.refreshRuntimePolicy()
            },
            setGlobalPauseReason: { [weak self] reason, isActive in
                guard let self else { return }
                await self.setGlobalPauseReason(reason, isActive: isActive)
            },
            scheduleDelayedRefresh: { [weak self] in
                self?.scheduleDelayedRuntimePolicyRefresh()
            }
        )
    }

    private func reconcileDisplays() async {
        let previousDisplayIDs = Set(displays.map(\.id))
        refreshDisplays()
        let currentDisplayIDs = Set(displays.map(\.id))
        let removedDisplayIDs = previousDisplayIDs.subtracting(currentDisplayIDs)

        for displayID in removedDisplayIDs {
            await runtimeController.stop(displayID: displayID)
        }

        await restoreSavedWallpapersForReappearedDisplays()
        await refreshActiveRuntimeConfigs()
        await refreshRuntimePolicy()
    }

    private func restoreSavedWallpapersForReappearedDisplays() async {
        let activeDisplayIDs = Set(activeConfigs.keys)
        let availableDisplayIDs = Set(displays.map(\.id))
        let restoreDisplayIDs = Set(savedConfigs.keys)
            .intersection(availableDisplayIDs)
            .subtracting(activeDisplayIDs)

        guard !restoreDisplayIDs.isEmpty else {
            return
        }

        var updatedConfigs = activeConfigs
        for displayID in displaySelection.orderedDisplayIDs(from: restoreDisplayIDs) {
            guard let savedConfig = savedConfigs[displayID] else {
                continue
            }

            updatedConfigs[displayID] = WallpaperRuntimeController.desiredConfig(from: savedConfig)
            runtimeController.removePausedDisplay(displayID)
        }

        do {
            try await applyRuntimeConfigs(updatedConfigs)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func setGlobalPauseReason(_ reason: RuntimePauseReason, isActive: Bool) async {
        policyController.setGlobalPauseReason(reason, isActive: isActive)
        await applyRuntimePolicy()
    }

    private func refreshRuntimePolicy() async {
        policyController.refreshDetectedPolicyState()
        await applyRuntimePolicy()
    }

    private func scheduleDelayedRuntimePolicyRefresh() {
        policyController.scheduleDelayedRefresh { [weak self] in
            await self?.refreshRuntimePolicy()
        }
    }

    private func applyRuntimePolicy() async {
        let activeDisplayIDs = Set(activeConfigs.keys)
        runtimeController.intersectPausedDisplays(with: activeDisplayIDs)
        let audioOwnerID = displaySelection.audioOwnerID(activeDisplayIDs: activeDisplayIDs, muted: muted)

        for (displayID, config) in activeConfigs {
            let shouldPause = !policyController.pauseReasons(for: displayID, config: config).isEmpty

            if shouldPause, !runtimeController.pausedDisplayIDs.contains(displayID) {
                await runtimeController.pause(displayID: displayID)
            } else if !shouldPause {
                do {
                    try await runtimeController.update(config: runtimeConfig(from: config, audioOwnerID: audioOwnerID))
                    runtimeController.removePausedDisplay(displayID)
                } catch {
                    lastError = error.localizedDescription
                }
            }
        }
    }
}
