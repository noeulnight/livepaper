import Foundation

/// App-side profile state and activation policy for shortcut-driven wallpapers.
///
/// This intentionally keeps profile-specific snapshot/activation state OUT of
/// `WallpaperCoordinator`. The coordinator stays the UI-facing composition layer
/// and runtime bridge; this controller owns profiles, the pre-apply snapshot, the
/// currently active profile, activation revision deduplication, and target display
/// resolution. It never touches `NSWindow`/runtime sessions directly — it works
/// with value types (`WallpaperConfig`, `DisplayID`) and calls back to the
/// coordinator for actual runtime application.
@MainActor
final class WallpaperProfileController {
    /// Opaque token describing one profile apply, used to preserve the original
    /// previous snapshot across profile-to-profile switches.
    struct ApplyTransition {
        let profileID: String
    }

    private(set) var profiles: [WallpaperProfile] = []

    /// Runtime configs captured the first time a profile is applied, kept
    /// intact across subsequent profile switches until the profile is deactivated.
    private var preProfileConfigs: [DisplayID: WallpaperConfig]?
    /// The profile currently driving the wallpaper, if any.
    private var activeProfileID: String?
    /// Last activation revision already handled, for deduplication.
    private var lastActivationRevision = 0

    private var monitorTask: Task<Void, Never>?
    private var handleActivation: ((WallpaperProfileActivation) async -> Void)?

    /// Backing storage (injectable for tests).
    private let defaults: UserDefaults

    private static let pollInterval: Duration = .seconds(1)

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? .standard
        self.profiles = WallpaperProfileStore.loadProfiles(from: self.defaults)
    }

    // MARK: - Profiles

    /// Reloads profiles, pruning any whose gallery item no longer exists.
    @discardableResult
    func refreshProfiles(validGalleryItemIDs: Set<String>) -> [WallpaperProfile] {
        let loaded = WallpaperProfileStore.loadProfiles(from: defaults)
        let pruned = loaded.filter { validGalleryItemIDs.contains($0.galleryItemID) }
        if pruned.count != loaded.count {
            WallpaperProfileStore.saveProfiles(pruned, to: defaults)
        }
        profiles = pruned
        return pruned
    }

    @discardableResult
    func createProfile(
        name: String,
        galleryItemID: String,
        wallpaperTitle: String,
        displayUUIDs: [String] = [],
        restoresPreviousWallpapers: Bool
    ) -> WallpaperProfile {
        let profile = WallpaperProfile(
            name: name,
            galleryItemID: galleryItemID,
            wallpaperTitle: wallpaperTitle,
            displayUUIDs: displayUUIDs,
            restoresPreviousWallpapers: restoresPreviousWallpapers
        )
        profiles.append(profile)
        WallpaperProfileStore.saveProfiles(profiles, to: defaults)
        profiles = WallpaperProfileStore.loadProfiles(from: defaults)
        return profile
    }

    func deleteProfile(id: String) {
        profiles.removeAll { $0.id == id }
        WallpaperProfileStore.saveProfiles(profiles, to: defaults)
        profiles = WallpaperProfileStore.loadProfiles(from: defaults)
        if activeProfileID == id {
            activeProfileID = nil
        }
    }

    func profile(id: String) -> WallpaperProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: - Activation Monitoring

    func startMonitoring(handleActivation: @escaping (WallpaperProfileActivation) async -> Void) {
        guard monitorTask == nil else {
            return
        }
        setActivationHandler(handleActivation)
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.consumePendingActivation()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        handleActivation = nil
    }

    func setActivationHandler(_ handler: @escaping (WallpaperProfileActivation) async -> Void) {
        handleActivation = handler
    }

    /// Handles the latest activation exactly once per revision. Each new revision
    /// (the profile applied or restored) is delivered to the handler a single time.
    func consumePendingActivation() async {
        guard let activation = WallpaperProfileStore.loadActivation(from: defaults),
              activation.revision != lastActivationRevision else {
            return
        }
        lastActivationRevision = activation.revision
        await handleActivation?(activation)
    }

    // MARK: - Apply / Restore Policy

    /// Prepares an apply transition, snapshotting the previous configs the first
    /// time a profile takes over (and preserving that snapshot across switches).
    func prepareApplyTransition(
        profileID: String,
        currentConfigs: [DisplayID: WallpaperConfig]
    ) -> ApplyTransition {
        if preProfileConfigs == nil {
            preProfileConfigs = currentConfigs
        }
        return ApplyTransition(profileID: profileID)
    }

    func markApplied(_ transition: ApplyTransition) {
        activeProfileID = transition.profileID
    }

    /// Returns the configs to restore when a profile is deactivated, or `nil` to do nothing.
    /// Always clears the snapshot and active profile after being asked.
    func restorationConfigsForDeactivation() -> [DisplayID: WallpaperConfig]? {
        let snapshot = preProfileConfigs
        let endingProfileID = activeProfileID
        preProfileConfigs = nil
        activeProfileID = nil

        guard let endingProfileID,
              let profile = profiles.first(where: { $0.id == endingProfileID }),
              profile.restoresPreviousWallpapers else {
            return nil
        }
        return snapshot
    }

    // MARK: - Target Displays

    /// Resolves which displays a profile should apply to.
    ///
    /// - Profile `displayUUIDs` (intersected with available displays) when set.
    /// - Otherwise the currently active displays.
    /// - Otherwise all available displays.
    func targetDisplayIDs(
        for profile: WallpaperProfile,
        displays: [DisplayID],
        activeDisplayIDs: Set<DisplayID>
    ) -> Set<DisplayID> {
        let available = Set(displays)

        if !profile.displayUUIDs.isEmpty {
            let requested = Set(profile.displayUUIDs.map(DisplayID.init(uuid:)))
            let resolved = requested.intersection(available)
            if !resolved.isEmpty {
                return resolved
            }
        }

        let activeAvailable = activeDisplayIDs.intersection(available)
        if !activeAvailable.isEmpty {
            return activeAvailable
        }

        return available
    }

}
