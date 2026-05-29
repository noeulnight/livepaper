import AVFoundation
import Foundation
import ImageIO

struct WallpaperMetadata: Equatable, Sendable {
    let title: String?
    let previewImageURL: URL?
}

nonisolated enum WallpaperMetadataExtractor {
    static func localVideoMetadata(for url: URL) async -> WallpaperMetadata {
        let asset = AVURLAsset(url: url)
        async let title = localVideoTitle(for: asset, fallbackURL: url)
        async let previewImageURL = localVideoPreviewImageURL(for: asset, sourceURL: url)
        return WallpaperMetadata(title: await title, previewImageURL: await previewImageURL)
    }

    static func youTubeMetadata(for url: URL) async -> WallpaperMetadata? {
        guard YouTubeEmbedURL.videoID(from: url) != nil else {
            return nil
        }

        do {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.youtube.com"
            components.path = "/oembed"
            components.queryItems = [
                URLQueryItem(name: "url", value: url.absoluteString),
                URLQueryItem(name: "format", value: "json")
            ]

            guard let metadataURL = components.url else {
                return nil
            }

            let (data, _) = try await URLSession.shared.data(from: metadataURL)
            let response = try JSONDecoder().decode(YouTubeOEmbedResponse.self, from: data)
            let previewImageURL = try await cachedRemoteImageURL(from: response.thumbnailURL, sourceURL: url)
            return WallpaperMetadata(title: response.title, previewImageURL: previewImageURL)
        } catch {
            return nil
        }
    }

    private static func localVideoTitle(for asset: AVURLAsset, fallbackURL: URL) async -> String {
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata where item.commonKey?.rawValue == "title" {
                if let title = try? await item.load(.stringValue), let trimmed = title.nilIfBlank {
                    return trimmed
                }
            }
        }

        return fallbackURL.deletingPathExtension().lastPathComponent
    }

    private static func localVideoPreviewImageURL(for asset: AVURLAsset, sourceURL: URL) async -> URL? {
        await Task.detached(priority: .utility) {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 720)

            do {
                let image = try await generatedImage(from: generator, at: CMTime(seconds: 1, preferredTimescale: 600))
                let outputURL = try cacheURL(prefix: "video", sourceURL: sourceURL, fileExtension: "jpg")
                guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.jpeg" as CFString, 1, nil) else {
                    return nil
                }
                CGImageDestinationAddImage(destination, image, nil)
                return CGImageDestinationFinalize(destination) ? outputURL : nil
            } catch {
                return nil
            }
        }.value
    }

    private nonisolated static func generatedImage(from generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    private static func cachedRemoteImageURL(from url: URL?, sourceURL: URL) async throws -> URL? {
        guard let url else {
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let outputURL = try cacheURL(prefix: "youtube", sourceURL: sourceURL, fileExtension: url.pathExtension.nilIfBlank ?? "jpg")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    private nonisolated static func cacheURL(prefix: String, sourceURL: URL, fileExtension: String) throws -> URL {
        let directory = try metadataCacheDirectory()
        let encoded = Data(sourceURL.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent("\(prefix)-\(encoded).\(fileExtension)")
    }

    private nonisolated static func metadataCacheDirectory() throws -> URL {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = appSupportURL
            .appendingPathComponent("LivePaper")
            .appendingPathComponent("Metadata")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private nonisolated struct YouTubeOEmbedResponse: Decodable {
    let title: String?
    let thumbnailURL: URL?

    private enum CodingKeys: String, CodingKey {
        case title
        case thumbnailURL = "thumbnail_url"
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
