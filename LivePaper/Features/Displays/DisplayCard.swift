import SwiftUI

struct DisplayCard: View {
    let display: DisplayState
    let wallpaperItem: WallpaperGalleryItem?
    let description: String
    @Binding var isEnabled: Bool
    let isAudioDisplay: Bool
    let audioSystemImage: String
    let audioAction: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            DisplayWallpaperPreview(item: wallpaperItem)

            LinearGradient(
                colors: [
                    .black.opacity(0.72),
                    .black.opacity(0.16),
                    .black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.top, 13)
                .padding(.horizontal, 14)

                Spacer(minLength: 0)

                HStack(alignment: .center) {
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .focusable(false)
                        .help(isEnabled ? "Stop this display" : "Start this display")

                    Spacer()

                    Button(action: audioAction) {
                        Image(systemName: audioSystemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isAudioDisplay ? .white : .white.opacity(0.62))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(isAudioDisplay ? Color.accentColor : Color.black.opacity(0.34))
                            )
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(isAudioDisplay ? 0.24 : 0.16))
                            }
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Use this display for wallpaper audio")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .frame(width: DisplayCardMetrics.width, height: DisplayCardMetrics.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isEnabled ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.14), lineWidth: isEnabled ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
    }
}

struct DisplayWallpaperPreview: View {
    let item: WallpaperGalleryItem?

    var body: some View {
        ZStack {
            if let item {
                WallpaperPreview(item: item, iconSize: 38)
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.black.opacity(0.68),
                        Color.blue.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "display")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
        .frame(width: DisplayCardMetrics.width, height: DisplayCardMetrics.height)
    }
}
