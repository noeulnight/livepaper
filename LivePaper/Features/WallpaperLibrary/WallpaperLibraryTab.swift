import SwiftUI

struct WallpaperLibraryTab: View {
    @Bindable var coordinator: WallpaperCoordinator
    @Binding var selectedGalleryItemID: WallpaperGalleryItem.ID?
    @Binding var isWallpaperDetailPresented: Bool
    @Binding var isAddWallpaperPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            wallpaperHeader
            wallpaperGallery
        }
    }

    private var wallpaperHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wallpapers")
                    .font(.largeTitle.bold())
                Text("\(coordinator.galleryItems.count) wallpaper\(coordinator.galleryItems.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer()

            Button {
                isAddWallpaperPresented = true
            } label: {
                Label("Add Wallpaper", systemImage: "plus.circle.fill")
            }
            .buttonStyle(GlassProminentButtonStyle())
            .focusable(false)
        }
    }

    private var wallpaperGallery: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: WallpaperCardMetrics.width,
                            maximum: WallpaperCardMetrics.width
                        ),
                        spacing: 16,
                        alignment: .top
                    )
                ],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(coordinator.galleryItems) { item in
                    Button {
                        selectGalleryItem(item)
                    } label: {
                        WallpaperCard(
                            item: item,
                            isSelected: selectedGalleryItemID == item.id || coordinator.selectedGalleryItemID == item.id
                        )
                    }
                    .frame(width: WallpaperCardMetrics.width, height: WallpaperCardMetrics.height)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(.top, 2)
            .padding(.trailing, 18)
            .padding(.bottom, LivePaperBottomTabMetrics.scrollContentTailPadding)
        }
        .overlay {
            if coordinator.galleryItems.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("No Wallpapers")
                        .font(.title3.weight(.semibold))
                    Text("Add a local video or web wallpaper to get started.")
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func selectGalleryItem(_ item: WallpaperGalleryItem) {
        selectedGalleryItemID = item.id
        coordinator.selectGalleryItem(id: item.id)
        coordinator.refreshDisplays()
        coordinator.selectedDisplayIDs = Set(coordinator.displays.map(\.id))
        isWallpaperDetailPresented = true
    }
}
