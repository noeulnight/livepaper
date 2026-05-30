import Foundation

@MainActor
final class WallpaperApplyCoordinator {
    var statusDidChange: ((WallpaperApplyStatus) -> Void)?

    private let lockScreenExporter: AerialLockScreenExporter
    private let screenSaverConfigurationStore: ScreenSaverConfigurationStore
    private let screenSaverInstaller: ScreenSaverInstaller

    private(set) var status = WallpaperApplyStatus.idle {
        didSet {
            statusDidChange?(status)
        }
    }

    init(
        lockScreenExporter: AerialLockScreenExporter? = nil,
        screenSaverConfigurationStore: ScreenSaverConfigurationStore? = nil,
        screenSaverInstaller: ScreenSaverInstaller? = nil
    ) {
        self.lockScreenExporter = lockScreenExporter ?? AerialLockScreenExporter()
        self.screenSaverConfigurationStore = screenSaverConfigurationStore ?? ScreenSaverConfigurationStore()
        self.screenSaverInstaller = screenSaverInstaller ?? ScreenSaverInstaller()
    }

    func canExportLockScreenWallpaper(_ content: WallpaperContent) -> Bool {
        lockScreenExporter.supportsExport(content)
    }

    func installScreenSaver() throws {
        try screenSaverInstaller.install()
    }

    func openScreenSaverSettings() {
        screenSaverInstaller.openScreenSaverSettings()
    }

    func updateStatus(
        content: WallpaperContent,
        displayCount: Int,
        desktop: WallpaperApplySurfaceStatus?,
        lockScreen: WallpaperApplySurfaceStatus?,
        screenSaver: WallpaperApplySurfaceStatus?
    ) {
        status = WallpaperApplyStatus(
            contentName: content.displayName,
            displayCount: displayCount,
            desktop: desktop ?? status.desktop,
            lockScreen: lockScreen ?? status.lockScreen,
            screenSaver: screenSaver ?? status.screenSaver
        )
    }

    func showProgressFrame(duration: ApplyProgressDuration) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: duration.nanoseconds)
    }

    func markStatusFailed(detail: String) {
        status.desktop = failIfApplying(status.desktop, detail: detail)
        status.lockScreen = failIfApplying(status.lockScreen, detail: detail)
        status.screenSaver = failIfApplying(status.screenSaver, detail: detail)
    }

    func lockScreenStatusBeforeExport(
        for content: WallpaperContent,
        applyAutomatically: Bool
    ) -> WallpaperApplySurfaceStatus {
        guard applyAutomatically else {
            return .init(state: .skipped, detail: "Auto off")
        }

        guard lockScreenExporter.supportsExport(content.resolvingSecurityScopedBookmarks()) else {
            return .init(state: .skipped, detail: "Video only")
        }

        return .init(state: .applying, detail: "Exporting")
    }

    func lockScreenStatusAfterExport(
        for content: WallpaperContent,
        applyAutomatically: Bool
    ) -> WallpaperApplySurfaceStatus {
        guard applyAutomatically else {
            return .init(state: .skipped, detail: "Auto off")
        }

        guard lockScreenExporter.supportsExport(content.resolvingSecurityScopedBookmarks()) else {
            return .init(state: .skipped, detail: "Video only")
        }

        return .init(state: .applied, detail: "Exported")
    }

    func settledVerifiedLockScreenStatus(
        for content: WallpaperContent,
        displayIDs: some Collection<DisplayID>,
        applyAutomatically: Bool,
        orderedDisplayIDs: (Set<DisplayID>) -> [DisplayID]
    ) async -> WallpaperApplySurfaceStatus {
        let firstStatus = verifiedLockScreenStatus(
            for: content,
            displayIDs: displayIDs,
            applyAutomatically: applyAutomatically,
            orderedDisplayIDs: orderedDisplayIDs
        )
        guard firstStatus.state == .failed else {
            return firstStatus
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        return verifiedLockScreenStatus(
            for: content,
            displayIDs: displayIDs,
            applyAutomatically: applyAutomatically,
            orderedDisplayIDs: orderedDisplayIDs
        )
    }

    func screenSaverStatusBeforeExport(for content: WallpaperContent) -> WallpaperApplySurfaceStatus {
        screenSaverConfigurationStore.supports(content.resolvingSecurityScopedBookmarks())
            ? .init(state: .applying, detail: "Updating")
            : .init(state: .skipped, detail: "Video only")
    }

    func screenSaverStatusAfterExport(for content: WallpaperContent) -> WallpaperApplySurfaceStatus {
        screenSaverConfigurationStore.supports(content.resolvingSecurityScopedBookmarks())
            ? .init(state: .applied, detail: "Updated")
            : .init(state: .skipped, detail: "Video only")
    }

    func refreshStatus(
        activeConfigs: [DisplayID: WallpaperConfig],
        savedConfigs: [DisplayID: SavedWallpaperConfig],
        availableDisplayIDs: Set<DisplayID>,
        applyAutomatically: Bool,
        orderedDisplayIDs: (Set<DisplayID>) -> [DisplayID]
    ) {
        let configs = Array(activeConfigs.values)
        let fallbackConfigs = savedConfigs
            .filter { availableDisplayIDs.contains($0.key) }
            .map { WallpaperRuntimeController.desiredConfig(from: $0.value) }
        let visibleConfigs = configs.isEmpty ? fallbackConfigs : configs
        guard let firstConfig = visibleConfigs.first else {
            status = .idle
            return
        }

        let matchingConfigs = visibleConfigs.filter {
            $0.content.galleryID == firstConfig.content.galleryID
        }
        status = WallpaperApplyStatus(
            contentName: firstConfig.content.displayName,
            displayCount: matchingConfigs.count,
            desktop: .init(state: .applied, detail: "Restored"),
            lockScreen: verifiedLockScreenStatus(
                for: firstConfig.content,
                displayIDs: matchingConfigs.map(\.displayID),
                applyAutomatically: applyAutomatically,
                orderedDisplayIDs: orderedDisplayIDs
            ),
            screenSaver: screenSaverStatusAfterExport(for: firstConfig.content)
        )
    }

    func exportLockScreenWallpaper(
        content: WallpaperContent,
        targetDisplayIDs: Set<DisplayID>,
        applyAutomatically: Bool,
        availableDisplayIDs: Set<DisplayID>,
        orderedDisplayIDs: (Set<DisplayID>) -> [DisplayID]
    ) async throws {
        let resolvedContent = content.resolvingSecurityScopedBookmarks()
        updateStatus(
            content: resolvedContent,
            displayCount: targetDisplayIDs.count,
            desktop: nil,
            lockScreen: .init(state: .applying, detail: "Exporting"),
            screenSaver: screenSaverConfigurationStore.supports(resolvedContent)
                ? .init(state: .applying, detail: "Updating")
                : .init(state: .skipped, detail: "Video only")
        )
        await showProgressFrame(duration: .primary)
        try screenSaverConfigurationStore.save(content: resolvedContent)
        try await lockScreenExporter.export(
            content: resolvedContent,
            displayIDs: lockScreenSelectionDisplayIDs(
                for: orderedDisplayIDs(targetDisplayIDs),
                availableDisplayIDs: availableDisplayIDs
            )
        )
        await showProgressFrame(duration: .verification)
        updateStatus(
            content: resolvedContent,
            displayCount: targetDisplayIDs.count,
            desktop: nil,
            lockScreen: await settledVerifiedLockScreenStatus(
                for: resolvedContent,
                displayIDs: targetDisplayIDs,
                applyAutomatically: applyAutomatically,
                orderedDisplayIDs: orderedDisplayIDs
            ),
            screenSaver: .init(state: .applied, detail: "Updated")
        )
    }

    func exportLockScreenWallpaperIfNeeded(
        for content: WallpaperContent,
        displayIDs: [DisplayID],
        applyAutomatically: Bool,
        availableDisplayIDs: Set<DisplayID>
    ) async throws {
        let resolvedContent = content.resolvingSecurityScopedBookmarks()
        if screenSaverConfigurationStore.supports(resolvedContent) {
            try screenSaverConfigurationStore.save(content: resolvedContent)
        }

        guard applyAutomatically else {
            return
        }

        guard lockScreenExporter.supportsExport(resolvedContent) else {
            return
        }

        try await lockScreenExporter.export(
            content: resolvedContent,
            displayIDs: lockScreenSelectionDisplayIDs(
                for: displayIDs,
                availableDisplayIDs: availableDisplayIDs
            )
        )
    }

    func syncLockScreenWallpapersIfNeeded(
        for savedConfigs: [DisplayID: SavedWallpaperConfig],
        applyAutomatically: Bool,
        availableDisplayIDs: Set<DisplayID>,
        orderedDisplayIDs: (Set<DisplayID>) -> [DisplayID]
    ) async throws {
        guard applyAutomatically else {
            return
        }

        let orderedIDs = orderedDisplayIDs(Set(savedConfigs.keys))
        var exportItems: [(displayID: DisplayID, content: WallpaperContent)] = []
        for displayID in orderedIDs {
            guard let config = savedConfigs[displayID] else {
                continue
            }

            let resolvedContent = config.content.resolvingSecurityScopedBookmarks()
            if screenSaverConfigurationStore.supports(resolvedContent) {
                try screenSaverConfigurationStore.save(content: resolvedContent)
            }

            guard lockScreenExporter.supportsExport(resolvedContent) else {
                continue
            }

            exportItems.append((displayID: displayID, content: resolvedContent))
        }

        guard !exportItems.isEmpty else {
            return
        }

        let exportDisplayIDs = exportItems.map(\.displayID)
        guard !lockScreenSelectionsMatch(savedConfigs, displayIDs: exportDisplayIDs) else {
            return
        }

        try await exportLockScreenItems(exportItems, availableDisplayIDs: availableDisplayIDs)
        await showProgressFrame(duration: .verification)

        guard lockScreenSelectionsMatch(savedConfigs, displayIDs: exportDisplayIDs) else {
            try await exportLockScreenItems(exportItems, availableDisplayIDs: availableDisplayIDs)
            await showProgressFrame(duration: .verification)
            guard lockScreenSelectionsMatch(savedConfigs, displayIDs: exportDisplayIDs) else {
                throw AerialLockScreenExportError.invalidWallpaperIndex(
                    FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
                )
            }
            return
        }
    }

    private func failIfApplying(
        _ surfaceStatus: WallpaperApplySurfaceStatus,
        detail: String
    ) -> WallpaperApplySurfaceStatus {
        surfaceStatus.state == .applying ? .init(state: .failed, detail: detail) : surfaceStatus
    }

    private func verifiedLockScreenStatus(
        for content: WallpaperContent,
        displayIDs: some Collection<DisplayID>,
        applyAutomatically: Bool,
        orderedDisplayIDs: (Set<DisplayID>) -> [DisplayID]
    ) -> WallpaperApplySurfaceStatus {
        guard applyAutomatically else {
            return .init(state: .skipped, detail: "Auto off")
        }

        let resolvedContent = content.resolvingSecurityScopedBookmarks()
        guard lockScreenExporter.supportsExport(resolvedContent) else {
            return .init(state: .skipped, detail: "Video only")
        }

        let orderedIDs = orderedDisplayIDs(Set(displayIDs))
        guard lockScreenExporter.isExportSelected(content: resolvedContent, displayIDs: orderedIDs) else {
            return .init(state: .failed, detail: "Not selected")
        }

        return .init(state: .applied, detail: "Exported")
    }

    private func lockScreenSelectionsMatch(
        _ savedConfigs: [DisplayID: SavedWallpaperConfig],
        displayIDs: [DisplayID]
    ) -> Bool {
        for displayID in displayIDs {
            guard let config = savedConfigs[displayID] else {
                continue
            }

            let resolvedContent = config.content.resolvingSecurityScopedBookmarks()
            guard lockScreenExporter.supportsExport(resolvedContent) else {
                continue
            }

            guard lockScreenExporter.isExportSelected(content: resolvedContent, displayIDs: [displayID]) else {
                return false
            }
        }

        return true
    }

    private func exportLockScreenItems(
        _ exportItems: [(displayID: DisplayID, content: WallpaperContent)],
        availableDisplayIDs: Set<DisplayID>
    ) async throws {
        guard let firstItem = exportItems.first else {
            return
        }

        let displayIDs = exportItems.map(\.displayID)
        if shouldUseGlobalLockScreenSelection(for: displayIDs, availableDisplayIDs: availableDisplayIDs),
           exportItems.allSatisfy({ $0.content.galleryID == firstItem.content.galleryID }) {
            try await lockScreenExporter.export(content: firstItem.content, displayIDs: [])
            return
        }

        try await lockScreenExporter.export(contentsByDisplayID: exportItems)
    }

    private func lockScreenSelectionDisplayIDs(
        for displayIDs: [DisplayID],
        availableDisplayIDs: Set<DisplayID>
    ) -> [DisplayID] {
        shouldUseGlobalLockScreenSelection(
            for: displayIDs,
            availableDisplayIDs: availableDisplayIDs
        ) ? [] : displayIDs
    }

    private func shouldUseGlobalLockScreenSelection(
        for displayIDs: [DisplayID],
        availableDisplayIDs: Set<DisplayID>
    ) -> Bool {
        !availableDisplayIDs.isEmpty && Set(displayIDs) == availableDisplayIDs
    }
}
