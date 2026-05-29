import AppKit
import SwiftUI

struct WallpaperCard: View {
    let item: WallpaperGalleryItem
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WallpaperPreview(item: item, iconSize: 34)
                .frame(width: WallpaperCardMetrics.previewWidth, height: WallpaperCardMetrics.previewHeight)

            LinearGradient(
                colors: [
                    .black.opacity(0),
                    .black.opacity(0.36),
                    .black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 82)
            .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(cardDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: WallpaperCardMetrics.width, height: WallpaperCardMetrics.height, alignment: .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.045) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
        }
    }

    private var cardDescription: String {
        guard item.savedDisplayCount > 0 else {
            return item.subtitle
        }
        return "\(item.subtitle) · \(item.savedDisplayCount) saved"
    }
}

struct WallpaperPreview: View {
    let item: WallpaperGalleryItem
    let iconSize: CGFloat

    var body: some View {
        ZStack {
            fallbackBackground

            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: WallpaperCardMetrics.previewWidth, height: WallpaperCardMetrics.previewHeight)
                    .clipped()
            } else {
                Image(systemName: item.kind == .video ? "film.fill" : "globe")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(item.kind == .video ? .blue : .green)
            }
        }
        .frame(width: WallpaperCardMetrics.previewWidth, height: WallpaperCardMetrics.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .clipped()
    }

    private var fallbackBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(item.kind == .video ? Color.blue.opacity(0.14) : Color.green.opacity(0.14))
    }

    private var previewImage: NSImage? {
        guard let previewImageURL = item.previewImageURL, previewImageURL.isFileURL else {
            return nil
        }
        return NSImage(contentsOf: previewImageURL)
    }
}
