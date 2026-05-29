import AppKit
import WebKit

@MainActor
final class WebWallpaperController {
    private var webView: WKWebView?

    func start(config: WallpaperConfig, in contentView: NSView) {
        stop()

        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: contentView.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.allowsBackForwardNavigationGestures = false
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        contentView.addSubview(webView)

        load(config: config, in: webView)
        self.webView = webView
    }

    func pause() {
        webView?.isHidden = true
    }

    func resume() {
        webView?.isHidden = false
    }

    func apply(config: WallpaperConfig) {
        guard let webView else {
            return
        }
        load(config: config, in: webView)
    }

    func stop() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    private func load(config: WallpaperConfig, in webView: WKWebView) {
        let url = config.content.url

        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: config.content.readAccessURL ?? url.deletingLastPathComponent())
        } else if YouTubeEmbedURL.isEmbedURL(url) {
            webView.loadHTMLString(youtubeEmbedHTML(for: url, config: config), baseURL: URL(string: "https://www.youtube-nocookie.com"))
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    private func youtubeEmbedHTML(for url: URL, config: WallpaperConfig) -> String {
        let src = htmlEscaped(youtubeURL(url, muted: config.muted).absoluteString)
        let volume = Int(max(0, min(config.volume, 1)) * 100)
        let muteCommand = config.muted ? "event.target.mute();" : "event.target.unMute();"
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            html, body {
              width: 100%;
              height: 100%;
              margin: 0;
              overflow: hidden;
              background: #000;
            }
            iframe {
              position: fixed;
              inset: 0;
              width: 100vw;
              height: 100vh;
              border: 0;
            }
          </style>
        </head>
        <body>
          <script src="https://www.youtube.com/iframe_api"></script>
          <iframe
            id="player"
            src="\(src)"
            allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
            referrerpolicy="strict-origin-when-cross-origin"
            allowfullscreen>
          </iframe>
          <script>
            function onYouTubeIframeAPIReady() {
              new YT.Player("player", {
                events: {
                  onReady: function(event) {
                    event.target.setVolume(\(volume));
                    \(muteCommand)
                    event.target.playVideo();
                  },
                  onStateChange: function(event) {
                    if (event.data === YT.PlayerState.ENDED) {
                      event.target.playVideo();
                    }
                  }
                }
              });
            }
          </script>
        </body>
        </html>
        """
    }

    private func youtubeURL(_ url: URL, muted: Bool) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "mute" }
        queryItems.append(URLQueryItem(name: "mute", value: muted ? "1" : "0"))
        components.queryItems = queryItems
        return components.url ?? url
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
