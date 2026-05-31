import Foundation

enum WallpaperEnginePackageError: LocalizedError, Equatable {
    case unreadablePackage(URL)
    case invalidHeader(String)
    case invalidFileRange(path: String, offset: UInt32, length: UInt32)

    var errorDescription: String? {
        switch self {
        case .unreadablePackage(let url):
            return "Could not read Wallpaper Engine package: \(url.path)"
        case .invalidHeader(let header):
            return "Wallpaper Engine package has an invalid header: \(header)"
        case .invalidFileRange(let path, let offset, let length):
            return "Wallpaper Engine package entry \(path) points outside the package payload at offset \(offset), length \(length)."
        }
    }
}

struct WallpaperEnginePackageEntry: Equatable, Sendable {
    let path: String
    let offset: UInt32
    let length: UInt32
}

struct WallpaperEnginePackage: Sendable {
    let url: URL
    let header: String
    let entries: [WallpaperEnginePackageEntry]

    private let data: Data
    private let payloadOffset: Int
    private let entriesByPath: [String: WallpaperEnginePackageEntry]

    init(url: URL, data: Data) throws {
        var reader = WallpaperEngineBinaryReader(data: data)
        let header = try reader.readLengthPrefixedString()

        guard header.hasPrefix("PKGV") else {
            throw WallpaperEnginePackageError.invalidHeader(header)
        }

        let fileCount = try reader.readUInt32()
        var entries: [WallpaperEnginePackageEntry] = []
        entries.reserveCapacity(Int(fileCount))

        for _ in 0..<fileCount {
            entries.append(
                WallpaperEnginePackageEntry(
                    path: try reader.readLengthPrefixedString().normalizedWallpaperEnginePath,
                    offset: try reader.readUInt32(),
                    length: try reader.readUInt32()
                )
            )
        }

        let payloadOffset = reader.offset
        for entry in entries {
            let absoluteOffset = payloadOffset + Int(entry.offset)
            guard absoluteOffset >= payloadOffset,
                  absoluteOffset + Int(entry.length) <= data.count else {
                throw WallpaperEnginePackageError.invalidFileRange(
                    path: entry.path,
                    offset: entry.offset,
                    length: entry.length
                )
            }
        }

        self.url = url
        self.header = header
        self.entries = entries
        self.data = data
        self.payloadOffset = payloadOffset
        self.entriesByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
    }

    func contains(_ path: String) -> Bool {
        entriesByPath[path.normalizedWallpaperEnginePath] != nil
    }

    func data(for path: String) -> Data? {
        guard let entry = entriesByPath[path.normalizedWallpaperEnginePath] else {
            return nil
        }

        let start = payloadOffset + Int(entry.offset)
        let end = start + Int(entry.length)
        return data.subdata(in: start..<end)
    }
}

struct WallpaperEnginePackageParser {
    func parsePackage(at url: URL) throws -> WallpaperEnginePackage {
        do {
            return try WallpaperEnginePackage(url: url, data: Data(contentsOf: url))
        } catch let error as WallpaperEnginePackageError {
            throw error
        } catch {
            throw WallpaperEnginePackageError.unreadablePackage(url)
        }
    }
}

extension String {
    var normalizedWallpaperEnginePath: String {
        var value = replacingOccurrences(of: "\\", with: "/")

        while value.hasPrefix("/") {
            value.removeFirst()
        }

        return value
    }

    var wallpaperEnginePathExtension: String {
        (self as NSString).pathExtension.lowercased()
    }
}
