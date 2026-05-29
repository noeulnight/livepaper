import Foundation

nonisolated enum YouTubeEmbedURL {
    static func normalizedURL(for url: URL) -> URL {
        guard let videoID = videoID(from: url) else {
            return url
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube-nocookie.com"
        components.path = "/embed/\(videoID)"
        components.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "mute", value: "1"),
            URLQueryItem(name: "loop", value: "1"),
            URLQueryItem(name: "playlist", value: videoID),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "controls", value: "0"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "origin", value: "https://www.youtube-nocookie.com"),
            URLQueryItem(name: "widget_referrer", value: "https://www.youtube-nocookie.com")
        ]

        return components.url ?? url
    }

    static func isEmbedURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else {
            return false
        }
        let isYouTubeHost = host == "youtube.com" ||
            host.hasSuffix(".youtube.com") ||
            host == "youtube-nocookie.com" ||
            host.hasSuffix(".youtube-nocookie.com")
        return isYouTubeHost && url.pathComponents.contains("embed")
    }

    static func videoID(from url: URL) -> String? {
        guard let host = url.host()?.lowercased() else {
            return nil
        }

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            return firstPathComponent(from: url)
        }

        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if pathComponents.first == "watch" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "v" }?
                .value
        }

        if ["shorts", "embed", "live"].contains(pathComponents.first), pathComponents.count >= 2 {
            return pathComponents[1]
        }

        return nil
    }

    private static func firstPathComponent(from url: URL) -> String? {
        url.pathComponents.first { $0 != "/" }
    }
}
