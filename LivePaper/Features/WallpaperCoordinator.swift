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
    private let loginItemController: LoginItemController
    private let lockScreenExporter: AerialLockScreenExporter
    private let screenSaverConfigurationStore: ScreenSaverConfigurationStore
    private let screenSaverInstaller: ScreenSaverInstaller

    private var savedConfigs: [DisplayID: SavedWallpaperConfig]
    private var displayObserver: NSObjectProtocol?

    private(set) var lastError: String?
    private(set) var displays: [DisplayState] = []
    private(set) var activeConfigs: [DisplayID: WallpaperConfig] = [:]
    private(set) var pausedDisplayIDs: Set<DisplayID> = []
    private(set) var steamDownloadLog = ""
    private(set) var selectedContentName: String?
    private(set) var selectedContentKind: WallpaperContent.Kind?
    private(set) var selectedGalleryItemID: WallpaperGalleryItem.ID?
    private(set) var hasSavedWallpapers = false
    private(set) var galleryItems: [WallpaperGalleryItem] = []
    private(set) var loginItemStatus: LoginItemStatus
    private(set) var shouldShowFirstLaunchIntro = false
    private(set) var isScreenSaverInstalled = false

    var selectedDisplayIDs: Set<DisplayID> = [] {
        didSet {
            displaySelection.selectedDisplayIDs = selectedDisplayIDs
        }
    }

    var scaleMode: ScaleMode = .fill
    var muted = false
    var volume = 1.0
    var pauseOnBattery = true
    var pauseOnFullscreen = true
    var muteOnFullscreen = false
    var applyLockScreenAutomatically = true

    var audioDisplayID: DisplayID? {
        didSet {
            displaySelection.audioDisplayID = audioDisplayID
        }
    }

    var steamCMDLoginMode: SteamCMDLoginMode = .anonymous {
        didSet {
            steamController.steamCMDLoginMode = steamCMDLoginMode
        }
    }

    var steamUsername = "" {
        didSet {
            steamController.steamUsername = steamUsername
        }
    }

    init(
        runtime: WallpaperRuntime? = nil,
        store: WallpaperSettingsStore? = nil,
        loginItemController: LoginItemController? = nil
    ) {
        let resolvedStore = store ?? WallpaperSettingsStore()
        let resolvedRuntime = runtime ?? InAppWallpaperRuntime()
        let resolvedLoginItemController = loginItemController ?? LoginItemController()
        let loadedSavedConfigs = resolvedStore.loadSavedConfigs()
        let loadedPreferences = resolvedStore.loadRuntimePreferences()

        self.store = resolvedStore
        self.savedConfigs = loadedSavedConfigs
        self.libraryModel = WallpaperLibraryModel(store: resolvedStore, savedConfigs: loadedSavedConfigs)
        self.displaySelection = DisplaySelectionModel()
        self.runtimeController = WallpaperRuntimeController(runtime: resolvedRuntime)
        self.policyController = RuntimePolicyController()
        self.steamController = SteamWorkshopController(store: resolvedStore)
        self.loginItemController = resolvedLoginItemController
        self.lockScreenExporter = AerialLockScreenExporter()
        self.screenSaverConfigurationStore = ScreenSaverConfigurationStore()
        self.screenSaverInstaller = ScreenSaverInstaller()
        self.loginItemStatus = resolvedLoginItemController.status()

        scaleMode = loadedPreferences.scaleMode
        muted = loadedPreferences.muted
        volume = loadedPreferences.volume
        displaySelection.audioDisplayID = loadedPreferences.audioDisplayID
        pauseOnBattery = loadedPreferences.pauseOnBattery
        pauseOnFullscreen = loadedPreferences.pauseOnFullscreen
        muteOnFullscreen = loadedPreferences.muteOnFullscreen
        applyLockScreenAutomatically = loadedPreferences.applyLockScreenAutomatically
        steamCMDLoginMode = steamController.steamCMDLoginMode
        steamUsername = steamController.steamUsername

        libraryModel.syncSteamMetadataFromLocalFiles(savedConfigs: &savedConfigs)
        syncLibraryState()
        shouldShowFirstLaunchIntro = resolvedStore.shouldShowFirstLaunchIntro(
            hasExistingWallpapers: !galleryItems.isEmpty || !loadedSavedConfigs.isEmpty
        )
        syncSteamState()
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
        syncDisplaySelectionState()
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

    func completeFirstLaunchIntro() {
        store.markFirstLaunchIntroCompleted()
        shouldShowFirstLaunchIntro = false
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
            let content = try await steamController.downloadWorkshop(url: rawURL) { [weak self] in
                self?.syncSteamState()
            }
            syncSteamState()
            select(content: content, addToLibrary: true)
            return nil
        } catch {
            syncSteamState()
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
        syncSteamState()
    }

    func clearLastError() {
        lastError = nil
    }

    func syncSteamMetadata() {
        libraryModel.syncSteamMetadataFromLocalFiles(savedConfigs: &savedConfigs)
        syncLibraryState()
        lastError = nil
    }

    func refreshLoginItemStatus() {
        loginItemStatus = loginItemController.status()
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try loginItemController.setEnabled(isEnabled)
            refreshLoginItemStatus()
            lastError = nil
        } catch {
            refreshLoginItemStatus()
            lastError = error.localizedDescription
        }
    }

    func selectGalleryItem(id: WallpaperGalleryItem.ID) {
        libraryModel.selectGalleryItem(id: id, savedConfigs: savedConfigs)
        syncLibraryState()
        lastError = nil
    }

    func canExportLockScreenWallpaper(galleryItemID: WallpaperGalleryItem.ID) -> Bool {
        guard let content = libraryModel.content(forGalleryItemID: galleryItemID, savedConfigs: savedConfigs) else {
            return false
        }
        return lockScreenExporter.supportsExport(content)
    }

    func exportLockScreenWallpaper(galleryItemID: WallpaperGalleryItem.ID) async {
        guard let content = libraryModel.content(forGalleryItemID: galleryItemID, savedConfigs: savedConfigs) else {
            lastError = "Choose a wallpaper first."
            return
        }

        do {
            let resolvedContent = content.resolvingSecurityScopedBookmarks()
            try screenSaverConfigurationStore.save(content: resolvedContent)
            try await lockScreenExporter.export(content: resolvedContent)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func installScreenSaver() {
        do {
            try screenSaverInstaller.install()
            isScreenSaverInstalled = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openScreenSaverSettings() {
        screenSaverInstaller.openScreenSaverSettings()
    }

    func applySelectedContent() async {
        await applySelectedContent(to: selectedDisplayIDs)
    }

    func applySelectedContent(to targetDisplayIDs: Set<DisplayID>) async {
        refreshDisplays()
        saveRuntimePreferences()
        let availableDisplayIDs = Set(displays.map(\.id))
        let targetIDs = targetDisplayIDs.intersection(availableDisplayIDs)

        do {
            guard let content = libraryModel.selectedContent else {
                lastError = "Choose content first."
                return
            }

            guard !targetIDs.isEmpty else {
                lastError = "Choose at least one display."
                return
            }

            selectedDisplayIDs = targetIDs

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
            syncLibraryState()
            await refreshRuntimePolicy()
            try await exportLockScreenWallpaperIfNeeded(for: content)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func savedDisplayIDs(forGalleryItemID id: WallpaperGalleryItem.ID) -> Set<DisplayID> {
        Set(savedConfigs.compactMap { displayID, config in
            config.content.galleryID == id ? displayID : nil
        })
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

    func isDisplayPaused(_ displayID: DisplayID) -> Bool {
        pausedDisplayIDs.contains(displayID)
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

    func pauseDisplay(_ displayID: DisplayID) async {
        guard activeConfigs[displayID] != nil else {
            return
        }

        await runtimeController.pause(displayID: displayID)
        syncRuntimeState()
        lastError = nil
    }

    func resumeDisplay(_ displayID: DisplayID) async {
        guard activeConfigs[displayID] != nil else {
            return
        }

        runtimeController.removePausedDisplay(displayID)
        await refreshActiveRuntimeConfigs()
    }

    func pauseAll() async {
        for displayID in displaySelection.orderedDisplayIDs(from: Set(activeConfigs.keys)) {
            await runtimeController.pause(displayID: displayID)
        }
        syncRuntimeState()
        lastError = nil
    }

    func resumeAll() async {
        for displayID in activeConfigs.keys {
            runtimeController.removePausedDisplay(displayID)
        }
        await refreshActiveRuntimeConfigs()
    }

    func stopDisplay(displayID: DisplayID) async {
        await runtimeController.stop(displayID: displayID)
        syncRuntimeState()
        updatePeriodicRuntimePolicyRefresh()
        lastError = nil
    }

    func stopAll() async {
        await runtimeController.stopAll()
        syncRuntimeState()
        updatePeriodicRuntimePolicyRefresh()
    }

    func forgetSavedWallpapers() async {
        await stopAll()
        savedConfigs.removeAll()
        store.removeAllConfigs()
        syncLibraryState()
    }

    func deleteGalleryItem(id: WallpaperGalleryItem.ID) async {
        let displayIDsToStop = activeConfigs
            .filter { $0.value.content.galleryID == id }
            .map(\.key)
        for displayID in displayIDsToStop {
            await runtimeController.stop(displayID: displayID)
        }
        syncRuntimeState()
        await refreshActiveRuntimeConfigs()

        libraryModel.deleteGalleryItem(id: id, savedConfigs: &savedConfigs)
        syncLibraryState()
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
            syncLibraryState()
            await refreshRuntimePolicy()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func syncDisplaySelectionState() {
        displays = displaySelection.displays
        selectedDisplayIDs = displaySelection.selectedDisplayIDs
        audioDisplayID = displaySelection.audioDisplayID
    }

    private func syncLibraryState() {
        selectedContentName = libraryModel.selectedContentName
        selectedContentKind = libraryModel.selectedContentKind
        selectedGalleryItemID = libraryModel.selectedGalleryItemID
        hasSavedWallpapers = !savedConfigs.isEmpty
        galleryItems = libraryModel.galleryItems(savedConfigs: savedConfigs)
    }

    private func syncRuntimeState() {
        activeConfigs = runtimeController.activeConfigs
        pausedDisplayIDs = runtimeController.pausedDisplayIDs
    }

    private func syncSteamState() {
        steamDownloadLog = steamController.steamDownloadLog
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
                muteOnFullscreen: muteOnFullscreen,
                applyLockScreenAutomatically: applyLockScreenAutomatically
            )
        )
    }

    private func exportLockScreenWallpaperIfNeeded(for content: WallpaperContent) async throws {
        let resolvedContent = content.resolvingSecurityScopedBookmarks()
        if screenSaverConfigurationStore.supports(resolvedContent) {
            try screenSaverConfigurationStore.save(content: resolvedContent)
        }

        guard applyLockScreenAutomatically else {
            return
        }

        guard lockScreenExporter.supportsExport(resolvedContent) else {
            return
        }

        try await lockScreenExporter.export(content: resolvedContent)
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
            syncLibraryState()
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
        syncRuntimeState()
        savedConfigs.removeValue(forKey: displayID)
        store.save(configs: savedConfigs)
        syncLibraryState()

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
        policyController.refreshDetectedPolicyState()

        let audioOwnerID = displaySelection.audioOwnerID(
            activeDisplayIDs: Set(desiredConfigs.keys),
            muted: muted
        )
        let pausedDisplayIDs = Set(desiredConfigs.compactMap { displayID, config in
            policyController.pauseReasons(for: displayID, config: config).isEmpty ? nil : displayID
        })

        try await runtimeController.applyRuntimeConfigs(
            desiredConfigs,
            audioOwnerID: audioOwnerID,
            fullscreenDisplayIDs: policyController.fullscreenDisplayIDs,
            pausedDisplayIDs: pausedDisplayIDs,
            orderedDisplayIDs: displaySelection.orderedDisplayIDs
        )
        syncRuntimeState()
        updatePeriodicRuntimePolicyRefresh()
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
        syncLibraryState()
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
        syncRuntimeState()

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

    private func updatePeriodicRuntimePolicyRefresh() {
        policyController.updatePeriodicRefresh(isActive: !activeConfigs.isEmpty) { [weak self] in
            guard let self else { return }
            await self.refreshRuntimePolicy()
        }
    }

    private func applyRuntimePolicy() async {
        let activeDisplayIDs = Set(activeConfigs.keys)
        runtimeController.intersectPausedDisplays(with: activeDisplayIDs)
        let audioOwnerID = displaySelection.audioOwnerID(activeDisplayIDs: activeDisplayIDs, muted: muted)

        for (displayID, config) in activeConfigs {
            let shouldPause = !policyController.pauseReasons(for: displayID, config: config).isEmpty

            if shouldPause {
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
