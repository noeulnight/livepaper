import AppIntents

// MARK: - Shortcuts profile switching
//
// These App Intents live in the main app target. Each intent records a profile
// activation, and the already-running app's `WallpaperProfileController` monitor
// applies it through the existing runtime path. This reuses the apply/restore
// pipeline and shares the same profiles created in Settings > Wallpaper Profiles.

/// A LivePaper wallpaper profile, surfaced as a Shortcuts parameter.
struct LivePaperWallpaperProfileEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "LivePaper Wallpaper"
    static let defaultQuery = LivePaperWallpaperProfileQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Provides profile entities to Shortcuts from the same storage LivePaper writes.
struct LivePaperWallpaperProfileQuery: EntityStringQuery {
    func entities(for identifiers: [LivePaperWallpaperProfileEntity.ID]) async throws -> [LivePaperWallpaperProfileEntity] {
        allEntities().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [LivePaperWallpaperProfileEntity] {
        allEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [LivePaperWallpaperProfileEntity] {
        allEntities()
    }

    private func allEntities() -> [LivePaperWallpaperProfileEntity] {
        WallpaperProfileStore.loadProfiles().map {
            LivePaperWallpaperProfileEntity(id: $0.id, name: $0.name)
        }
    }
}

/// Shortcut action: apply a LivePaper wallpaper profile.
struct ApplyLivePaperWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Set LivePaper Wallpaper"
    static let description = IntentDescription("Switch the desktop to a LivePaper wallpaper profile.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Profile")
    var profile: LivePaperWallpaperProfileEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Set LivePaper wallpaper to \(\.$profile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WallpaperProfileStore.saveActivation(
            WallpaperProfileActivation(profileID: profile.id)
        )
        return .result(dialog: "Applying \(profile.name)")
    }
}

/// Shortcut action: restore the wallpapers shown before a profile was applied.
struct RestoreLivePaperWallpaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Restore LivePaper Wallpaper"
    static let description = IntentDescription("Restore the wallpapers shown before a LivePaper profile was applied.")
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WallpaperProfileStore.saveActivation(
            WallpaperProfileActivation(profileID: nil)
        )
        return .result(dialog: "Restoring previous wallpaper")
    }
}

/// Registers the always-available shortcut phrases for Spotlight / Siri.
struct LivePaperShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyLivePaperWallpaperIntent(),
            phrases: [
                "Set \(.applicationName) wallpaper",
                "Apply \(.applicationName) wallpaper"
            ],
            shortTitle: "Set Wallpaper",
            systemImageName: "photo.on.rectangle.angled"
        )
        AppShortcut(
            intent: RestoreLivePaperWallpaperIntent(),
            phrases: [
                "Restore \(.applicationName) wallpaper"
            ],
            shortTitle: "Restore Wallpaper",
            systemImageName: "arrow.uturn.backward"
        )
    }
}
