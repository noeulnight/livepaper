import AppKit
import SwiftUI

struct WallpaperDetailSheet: View {
    @Bindable var coordinator: WallpaperCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var presentedAlert: WallpaperDetailAlert?
    @State private var isDeleteHovered = false
    @State private var isExportingLockScreen = false
    @State private var selectedDisplayIDs: Set<DisplayID> = []
    let item: WallpaperGalleryItem

    var body: some View {
        ZStack {
            WallpaperDetailBackground(item: item)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.title2.weight(.bold))
                            .lineLimit(2)
                        Text(detailDescription)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(2)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .focusable(false)
                    .help("Close")
                }
                .padding(.top, 28)
                .padding(.horizontal, 26)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Displays")
                        .font(.headline)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(coordinator.displays) { display in
                                Button {
                                    toggleDisplaySelection(display.id)
                                } label: {
                                    WallpaperDetailDisplayRow(
                                        display: display,
                                        isSelected: selectedDisplayIDs.contains(display.id)
                                    )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .onHover { isHovered in
                                    if isHovered {
                                        DisplayHighlighter.shared.highlight(displayID: display.id, duration: nil)
                                    } else {
                                        DisplayHighlighter.shared.hide(displayID: display.id)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .frame(height: displayPanelHeight, alignment: .topLeading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.18))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await coordinator.applySelectedContent(to: selectedDisplayIDs)
                            if coordinator.lastError == nil {
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Apply This Wallpaper")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedDisplayIDs.isEmpty)
                    .opacity(selectedDisplayIDs.isEmpty ? 0.55 : 1)
                    .focusable(false)

                    if coordinator.canExportLockScreenWallpaper(galleryItemID: item.id) {
                        Button {
                            Task {
                                isExportingLockScreen = true
                                await coordinator.exportLockScreenWallpaper(galleryItemID: item.id)
                                isExportingLockScreen = false
                            }
                        } label: {
                            Image(systemName: isExportingLockScreen ? "hourglass" : "lock.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.borderless)
                        .background {
                            Circle()
                                .fill(Color.white.opacity(0.12))
                                .background(.regularMaterial, in: Circle())
                        }
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.16))
                        }
                        .disabled(isExportingLockScreen)
                        .opacity(isExportingLockScreen ? 0.6 : 1)
                        .contentShape(Circle())
                        .focusable(false)
                        .help("Export to Lock Screen")
                    }

                    Button(role: .destructive) {
                        presentedAlert = .deleteConfirmation
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isDeleteHovered ? .white : .red)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.borderless)
                    .background {
                        Circle()
                            .fill(isDeleteHovered ? Color.red.opacity(0.86) : Color.white.opacity(0.08))
                            .background(.regularMaterial, in: Circle())
                    }
                    .overlay {
                        Circle()
                            .stroke(isDeleteHovered ? Color.red.opacity(0.92) : Color.white.opacity(0.16))
                    }
                    .contentShape(Circle())
                    .onHover { isDeleteHovered = $0 }
                    .focusable(false)
                    .help("Delete wallpaper")
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 420, height: 640)
        .onAppear {
            refreshSelectedDisplays()
        }
        .onChange(of: item.id) { _, _ in
            refreshSelectedDisplays()
        }
        .onChange(of: coordinator.lastError) { _, error in
            guard let error else {
                return
            }
            presentedAlert = .error(error)
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .error(let message):
                Alert(
                    title: Text("LivePaper"),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) {
                        coordinator.clearLastError()
                    }
                )
            case .deleteConfirmation:
                Alert(
                    title: Text("Delete Wallpaper?"),
                    message: Text("This removes the wallpaper from the library and clears any saved display assignments for it."),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            await coordinator.deleteGalleryItem(id: item.id)
                            dismiss()
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var detailDescription: String {
        item.subtitle
    }

    private var displayPanelHeight: CGFloat {
        let rowsHeight = CGFloat(max(coordinator.displays.count, 1)) * 40
        return min(max(rowsHeight + 58, 126), 230)
    }

    private func toggleDisplaySelection(_ id: DisplayID) {
        if selectedDisplayIDs.contains(id) {
            selectedDisplayIDs.remove(id)
        } else {
            selectedDisplayIDs.insert(id)
        }
    }

    private func refreshSelectedDisplays() {
        coordinator.refreshDisplays()
        let availableDisplayIDs = Set(coordinator.displays.map(\.id))
        let savedDisplayIDs = coordinator.savedDisplayIDs(forGalleryItemID: item.id)
            .intersection(availableDisplayIDs)

        selectedDisplayIDs = savedDisplayIDs.isEmpty ? availableDisplayIDs : savedDisplayIDs
    }
}

private struct WallpaperDetailDisplayRow: View {
    let display: DisplayState
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "display")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 15)

            Text(display.name)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)

            Text("(\(display.frameDescription))")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white.opacity(0.68) : .white.opacity(0.54))

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor.opacity(0.95))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.16) : Color.black.opacity(0.24))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: isSelected ? Color.accentColor.opacity(0.18) : .clear, radius: 8, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

enum WallpaperDetailAlert: Identifiable {
    case error(String)
    case deleteConfirmation

    var id: String {
        switch self {
        case .error(let message):
            return "error-\(message)"
        case .deleteConfirmation:
            return "delete-confirmation"
        }
    }
}

struct WallpaperDetailBackground: View {
    let item: WallpaperGalleryItem

    var body: some View {
        ZStack {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackBackground
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.72),
                    .black.opacity(0.34),
                    .black.opacity(0.08),
                    .black.opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: 420, height: 640)
    }

    private var fallbackBackground: some View {
        ZStack {
            LinearGradient(
                colors: item.kind == .video
                    ? [Color.blue.opacity(0.34), Color.black, Color.indigo.opacity(0.28)]
                    : [Color.green.opacity(0.32), Color.black, Color.teal.opacity(0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: item.kind == .video ? "film.fill" : "globe")
                .font(.system(size: 74, weight: .medium))
                .foregroundStyle(.white.opacity(0.22))
        }
    }

    private var previewImage: NSImage? {
        guard let previewImageURL = item.previewImageURL, previewImageURL.isFileURL else {
            return nil
        }
        return NSImage(contentsOf: previewImageURL)
    }
}
