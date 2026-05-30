import Foundation

@MainActor
final class WallpaperLibraryModel {
    private let store: WallpaperSettingsStore

    private(set) var library: [WallpaperContent]
    private(set) var selectedContent: WallpaperContent?
    private(set) var selectedContentName: String?
    private(set) var selectedContentKind: WallpaperContent.Kind?

    init(store: WallpaperSettingsStore, savedConfigs: [DisplayID: SavedWallpaperConfig]) {
        self.store = store
        self.library = store.loadLibrary()
        migrateSavedConfigsIntoLibrary(savedConfigs)
        syncSteamMetadataFromLocalFiles(savedConfigs: savedConfigs)
    }

    var selectedGalleryItemID: WallpaperGalleryItem.ID? {
        selectedContent?.galleryID
    }

    func galleryItems(savedConfigs: [DisplayID: SavedWallpaperConfig]) -> [WallpaperGalleryItem] {
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

    func select(content: WallpaperContent, addToLibrary: Bool) {
        if addToLibrary {
            addLibraryItem(content)
        }

        selectedContent = content
        selectedContentName = content.displayName
        selectedContentKind = content.kind
    }

    func selectGalleryItem(id: WallpaperGalleryItem.ID, savedConfigs: [DisplayID: SavedWallpaperConfig]) {
        guard let content = (library + savedConfigs.values.map(\.content))
            .first(where: { $0.galleryID == id }) else {
            return
        }

        select(content: content, addToLibrary: false)
    }

    func content(forGalleryItemID id: WallpaperGalleryItem.ID, savedConfigs: [DisplayID: SavedWallpaperConfig]) -> WallpaperContent? {
        (library + savedConfigs.values.map(\.content))
            .first { $0.galleryID == id }
    }

    func deleteGalleryItem(id: WallpaperGalleryItem.ID, savedConfigs: inout [DisplayID: SavedWallpaperConfig]) {
        library.removeAll { $0.galleryID == id }
        savedConfigs = savedConfigs.filter { $0.value.content.galleryID != id }
        store.save(library: library)
        store.save(configs: savedConfigs)

        if selectedContent?.galleryID == id {
            selectedContent = nil
            selectedContentName = nil
            selectedContentKind = nil
        }
    }

    func syncSteamMetadataFromLocalFiles(savedConfigs: inout [DisplayID: SavedWallpaperConfig]) {
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
                pauseOnFullscreen: config.pauseOnFullscreen,
                muteOnFullscreen: config.muteOnFullscreen,
                musicStyle: config.musicStyle
            )
            didChangeConfigs = true
        }

        if let selectedContent {
            self.selectedContent = importer.synchronizedSteamMetadata(for: selectedContent)
            selectedContentName = self.selectedContent?.displayName
            selectedContentKind = self.selectedContent?.kind
        }

        if didChangeLibrary {
            store.save(library: library)
        }
        if didChangeConfigs {
            store.save(configs: savedConfigs)
        }
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

    private func migrateSavedConfigsIntoLibrary(_ savedConfigs: [DisplayID: SavedWallpaperConfig]) {
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

    private func syncSteamMetadataFromLocalFiles(savedConfigs: [DisplayID: SavedWallpaperConfig]) {
        var mutableSavedConfigs = savedConfigs
        syncSteamMetadataFromLocalFiles(savedConfigs: &mutableSavedConfigs)
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
}
