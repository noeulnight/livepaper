import AppKit
import SwiftUI

struct WallpaperDetailSheet: View {
    @Bindable var coordinator: WallpaperCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var presentedAlert: WallpaperDetailAlert?
    @State private var isDeleteHovered = false
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
                                Toggle(isOn: displayBinding(for: display.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(display.name)
                                            .font(.callout.weight(.medium))
                                        Text(display.frameDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .frame(height: 132, alignment: .topLeading)
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
                            await coordinator.applySelectedContent()
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
                    .disabled(coordinator.selectedDisplayIDs.isEmpty)
                    .opacity(coordinator.selectedDisplayIDs.isEmpty ? 0.55 : 1)
                    .focusable(false)

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
        if item.savedDisplayCount > 0 {
            return "\(item.subtitle) - \(item.savedDisplayCount) saved"
        }
        return item.subtitle
    }

    private func displayBinding(for id: DisplayID) -> Binding<Bool> {
        Binding {
            coordinator.selectedDisplayIDs.contains(id)
        } set: { isSelected in
            if isSelected {
                coordinator.selectedDisplayIDs.insert(id)
            } else {
                coordinator.selectedDisplayIDs.remove(id)
            }
        }
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
