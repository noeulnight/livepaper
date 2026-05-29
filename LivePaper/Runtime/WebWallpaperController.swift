import AppKit
import WebKit

@MainActor
final class WebWallpaperController {
    private var webView: WKWebView?
    private var loadedURL: URL?
    private var currentConfig: WallpaperConfig?

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
        self.currentConfig = config
    }

    func pause() {
        webView?.isHidden = true
        webView?.evaluateJavaScript(WebWallpaperPlaybackScript.pauseScript)
    }

    func resume() {
        webView?.isHidden = false
        guard let currentConfig else {
            return
        }
        webView?.evaluateJavaScript(WebWallpaperPlaybackScript.resumeScript(shouldResumeYouTube: YouTubeEmbedURL.isEmbedURL(currentConfig.content.url)))
    }

    func apply(config: WallpaperConfig) {
        guard let webView else {
            return
        }
        currentConfig = config
        guard loadedURL != config.content.url else {
            applyPlaybackSettings(config: config, in: webView)
            return
        }
        load(config: config, in: webView)
    }

    func stop() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        loadedURL = nil
        currentConfig = nil
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
        loadedURL = url
    }

    private func applyPlaybackSettings(config: WallpaperConfig, in webView: WKWebView) {
        guard YouTubeEmbedURL.isEmbedURL(config.content.url) else {
            return
        }

        let volume = Int(max(0, min(config.volume, 1)) * 100)
        let muteCommand = config.muted ? "player.mute();" : "player.unMute();"
        let script = """
        if (typeof player !== "undefined" && player && typeof player.setVolume === "function") {
          player.setVolume(\(volume));
          \(muteCommand)
        }
        """
        webView.evaluateJavaScript(script)
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
                  window.player = new YT.Player("player", {
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

enum WebWallpaperPlaybackScript {
    static let pauseScript = """
    (function() {
      if (typeof player !== "undefined" && player && typeof player.pauseVideo === "function") {
        player.pauseVideo();
      }
      document.querySelectorAll("video, audio").forEach(function(element) {
        if (typeof element.pause === "function") {
          element.dataset.livePaperPaused = element.paused ? "false" : "true";
          element.pause();
        }
      });
    })();
    """

    static func resumeScript(shouldResumeYouTube: Bool) -> String {
        let youtubeCommand = shouldResumeYouTube ? """
          if (typeof player !== "undefined" && player && typeof player.playVideo === "function") {
            player.playVideo();
          }
        """ : ""

        return """
        (function() {
        \(youtubeCommand)
          document.querySelectorAll("video, audio").forEach(function(element) {
            if (element.dataset.livePaperPaused === "true" && typeof element.play === "function") {
              element.play().catch(function() {});
            }
          });
        })();
        """
    }
}
