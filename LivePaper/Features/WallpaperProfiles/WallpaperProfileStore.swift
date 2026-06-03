import Foundation

// MARK: - Models
//
// The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and the Shortcuts
// App Intents entity query runs off the main actor, so the store helpers below are
// `nonisolated`.

/// A user-defined LivePaper wallpaper profile.
struct WallpaperProfile: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var name: String
    /// LivePaper gallery item id (`"<kind>:<url>"`) for the wallpaper to apply.
    var galleryItemID: String
    /// Cached wallpaper title shown inside LivePaper and Shortcuts.
    var wallpaperTitle: String
    /// Optional target display UUIDs. Empty means "active displays, else all".
    var displayUUIDs: [String]
    /// Whether deactivating the profile restores the previous runtime wallpapers.
    var restoresPreviousWallpapers: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        galleryItemID: String,
        wallpaperTitle: String,
        displayUUIDs: [String] = [],
        restoresPreviousWallpapers: Bool = true
    ) {
        self.id = id
        self.name = name
        self.galleryItemID = galleryItemID
        self.wallpaperTitle = wallpaperTitle
        self.displayUUIDs = displayUUIDs
        self.restoresPreviousWallpapers = restoresPreviousWallpapers
    }
}

/// The latest profile activation written by the Shortcuts App Intent.
///
/// `profileID == nil` means "restore the previous wallpapers".
struct WallpaperProfileActivation: Codable, Equatable, Sendable {
    var profileID: String?
    /// Monotonically increasing counter used to deduplicate already-handled events.
    var revision: Int

    init(profileID: String?, revision: Int = 0) {
        self.profileID = profileID
        self.revision = revision
    }
}

// MARK: - Persistence

/// Persistence helper backed by the app's `UserDefaults`, shared by the app and
/// the Shortcuts App Intents.
enum WallpaperProfileStore {
    private nonisolated static let profilesKey = "wallpaper.profiles"
    private nonisolated static let activationKey = "wallpaper.activation"

    private nonisolated static var defaults: UserDefaults { .standard }

    // MARK: Profiles

    nonisolated static func loadProfiles() -> [WallpaperProfile] {
        loadProfiles(from: defaults)
    }

    nonisolated static func loadProfiles(from defaults: UserDefaults) -> [WallpaperProfile] {
        guard let data = defaults.data(forKey: profilesKey),
              let profiles = try? JSONDecoder().decode([WallpaperProfile].self, from: data) else {
            return []
        }
        return sortedByName(profiles)
    }

    nonisolated static func saveProfiles(_ profiles: [WallpaperProfile], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(sortedByName(profiles)) else {
            return
        }
        defaults.set(data, forKey: profilesKey)
    }

    // MARK: Activation

    nonisolated static func saveActivation(_ activation: WallpaperProfileActivation) {
        saveActivation(activation, to: defaults)
    }

    nonisolated static func loadActivation(from defaults: UserDefaults) -> WallpaperProfileActivation? {
        guard let data = defaults.data(forKey: activationKey),
              let activation = try? JSONDecoder().decode(WallpaperProfileActivation.self, from: data) else {
            return nil
        }
        return activation
    }

    /// Persists a new activation, assigning it the next revision.
    @discardableResult
    nonisolated static func saveActivation(
        _ activation: WallpaperProfileActivation,
        to defaults: UserDefaults
    ) -> WallpaperProfileActivation {
        let nextRevision = (loadActivation(from: defaults)?.revision ?? 0) + 1
        let stamped = WallpaperProfileActivation(profileID: activation.profileID, revision: nextRevision)
        if let data = try? JSONEncoder().encode(stamped) {
            defaults.set(data, forKey: activationKey)
        }
        return stamped
    }

    private nonisolated static func sortedByName(_ profiles: [WallpaperProfile]) -> [WallpaperProfile] {
        profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
