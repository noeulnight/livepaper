import AppKit
import Foundation

enum MusicPlaybackState: String, Equatable, Sendable {
    case playing
    case paused
    case stopped
    case unavailable
}

struct NowPlayingAlbumSnapshot: Equatable, Sendable {
    let source: WallpaperContent.MusicSource
    let playbackState: MusicPlaybackState
    let trackID: String
    let trackTitle: String
    let artistName: String
    let albumTitle: String
    let artworkURL: URL?
    let artworkFileURL: URL?
    let playbackPosition: TimeInterval?
    let playbackDuration: TimeInterval?

    var identity: String {
        [
            source.rawValue,
            trackID,
            trackTitle,
            artistName,
            albumTitle,
            artworkURL?.absoluteString ?? "",
            artworkFileURL?.path ?? ""
        ].joined(separator: "|")
    }

    var progressFraction: CGFloat? {
        guard let playbackPosition,
              let playbackDuration,
              playbackDuration > 0 else {
            return nil
        }
        return CGFloat(min(max(playbackPosition / playbackDuration, 0), 1))
    }

    var playbackPositionText: String? {
        Self.formattedPlaybackTime(playbackPosition)
    }

    var playbackDurationText: String? {
        Self.formattedPlaybackTime(playbackDuration)
    }

    static func formattedPlaybackTime(_ value: TimeInterval?) -> String? {
        guard let value,
              value.isFinite,
              value >= 0 else {
            return nil
        }

        let seconds = Int(value.rounded(.down))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

protocol NowPlayingAlbumProviding {
    var source: WallpaperContent.MusicSource { get }
    func currentAlbum() async -> NowPlayingAlbumSnapshot?
}

enum MusicNowPlayingScriptParser {
    static let separator = "\u{1F}"

    static func parse(
        _ output: String,
        source: WallpaperContent.MusicSource,
        artworkFileURL: URL? = nil
    ) -> NowPlayingAlbumSnapshot? {
        let fields = output.components(separatedBy: separator)
        guard fields.count >= 6 else {
            return nil
        }

        let state = playbackState(from: fields[0])
        let artworkValue = fields[5].nilIfBlank
        let resolvedArtworkFileURL: URL?
        if let artworkFileURL, !artworkFileURL.path.isEmpty, FileManager.default.fileExists(atPath: artworkFileURL.path) {
            resolvedArtworkFileURL = artworkFileURL
        } else if let artworkValue, artworkValue.hasPrefix("/") {
            resolvedArtworkFileURL = URL(fileURLWithPath: artworkValue)
        } else {
            resolvedArtworkFileURL = nil
        }

        let artworkURL: URL?
        if let artworkValue, !artworkValue.hasPrefix("/") {
            artworkURL = URL(string: artworkValue)
        } else {
            artworkURL = nil
        }
        let playbackPosition = timeInterval(from: fields[safe: 6])
        let playbackDuration = timeInterval(from: fields[safe: 7])

        return NowPlayingAlbumSnapshot(
            source: source,
            playbackState: state,
            trackID: fields[1].nilIfBlank ?? "\(fields[2])|\(fields[3])|\(fields[4])",
            trackTitle: fields[2].nilIfBlank ?? "Not Playing",
            artistName: fields[3].nilIfBlank ?? "Waiting for playback",
            albumTitle: fields[4].nilIfBlank ?? "Music Sync",
            artworkURL: artworkURL,
            artworkFileURL: resolvedArtworkFileURL,
            playbackPosition: playbackPosition,
            playbackDuration: playbackDuration
        )
    }

    private static func playbackState(from value: String) -> MusicPlaybackState {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "playing":
            return .playing
        case "paused":
            return .paused
        case "stopped":
            return .stopped
        default:
            return .unavailable
        }
    }

    private static func timeInterval(from value: String?) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return TimeInterval(value.replacingOccurrences(of: ",", with: "."))
    }
}

@MainActor
final class AppleScriptNowPlayingProvider: NowPlayingAlbumProviding {
    let source: WallpaperContent.MusicSource
    private let artworkCacheURL: URL

    init(source: WallpaperContent.MusicSource) {
        self.source = source
        self.artworkCacheURL = Self.artworkCacheURL(for: source)
    }

    func currentAlbum() async -> NowPlayingAlbumSnapshot? {
        guard isSourceApplicationRunning else {
            return unavailableSnapshot
        }

        try? FileManager.default.createDirectory(
            at: artworkCacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let output = execute(script: scriptSource)
        return output.flatMap {
            MusicNowPlayingScriptParser.parse($0, source: source, artworkFileURL: artworkCacheURL)
        } ?? unavailableSnapshot
    }

    private var isSourceApplicationRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == source.bundleIdentifier
        }
    }

    private var unavailableSnapshot: NowPlayingAlbumSnapshot {
        NowPlayingAlbumSnapshot(
            source: source,
            playbackState: .unavailable,
            trackID: "",
            trackTitle: "Music Sync",
            artistName: "Waiting for playback",
            albumTitle: "Music Sync",
            artworkURL: nil,
            artworkFileURL: nil,
            playbackPosition: nil,
            playbackDuration: nil
        )
    }

    private var scriptSource: String {
        switch source {
        case .appleMusic:
            return appleMusicScript
        case .spotify:
            return spotifyScript
        }
    }

    private var appleMusicScript: String {
        let artworkPath = Self.appleScriptEscaped(artworkCacheURL.path)
        return """
        set d to ASCII character 31
        tell application id "\(source.bundleIdentifier)"
            if player state is stopped then return "stopped" & d & "" & d & "" & d & "" & d & "" & d & ""
            set currentTrack to current track
            set trackID to ""
            try
                set trackID to persistent ID of currentTrack as text
            on error
                try
                    set trackID to database ID of currentTrack as text
                end try
            end try
            set artworkPath to "\(artworkPath)"
            try
                if (count of artworks of currentTrack) > 0 then
                    set artworkData to raw data of artwork 1 of currentTrack
                    set artworkFile to open for access (POSIX file artworkPath) with write permission
                    set eof artworkFile to 0
                    write artworkData to artworkFile
                    close access artworkFile
                else
                    set artworkPath to ""
                end if
            on error
                try
                    close access (POSIX file artworkPath)
                end try
                set artworkPath to ""
            end try
            set playbackPosition to 0
            set playbackDuration to 0
            try
                set playbackPosition to player position as real
            end try
            try
                set playbackDuration to duration of currentTrack as real
            end try
            return (player state as text) & d & trackID & d & (name of currentTrack as text) & d & (artist of currentTrack as text) & d & (album of currentTrack as text) & d & artworkPath & d & (playbackPosition as text) & d & (playbackDuration as text)
        end tell
        """
    }

    private var spotifyScript: String {
        """
        set d to ASCII character 31
        tell application id "\(source.bundleIdentifier)"
            if player state is stopped then return "stopped" & d & "" & d & "" & d & "" & d & "" & d & ""
            set currentTrack to current track
            set playbackPosition to 0
            set playbackDuration to 0
            try
                set playbackPosition to player position as real
            end try
            try
                set playbackDuration to (duration of currentTrack as real) / 1000
            end try
            return (player state as text) & d & (id of currentTrack as text) & d & (name of currentTrack as text) & d & (artist of currentTrack as text) & d & (album of currentTrack as text) & d & (artwork url of currentTrack as text) & d & (playbackPosition as text) & d & (playbackDuration as text)
        end tell
        """
    }

    private func execute(script source: String) -> String? {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let result = script.executeAndReturnError(&errorInfo).stringValue,
              errorInfo == nil else {
            return nil
        }
        return result
    }

    private static func artworkCacheURL(for source: WallpaperContent.MusicSource) -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("LivePaper", isDirectory: true)
            .appendingPathComponent("MusicArtwork", isDirectory: true)
            .appendingPathComponent("\(source.rawValue)-current-artwork")
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
