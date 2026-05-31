import Foundation

struct WallpaperEngineSceneAssetStore {
    let folderURL: URL
    let fileManager: FileManager
    let packages: [WallpaperEnginePackage]
    let directAssetPaths: Set<String>

    init(
        folderURL: URL,
        fileManager: FileManager = .default,
        packageParser: WallpaperEnginePackageParser = WallpaperEnginePackageParser()
    ) throws {
        self.folderURL = folderURL
        self.fileManager = fileManager
        self.directAssetPaths = Self.directAssetPaths(
            in: folderURL,
            fileManager: fileManager
        )

        let packageURLs = (try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        ))?
        .filter { $0.pathExtension.lowercased() == "pkg" }
        .sorted { lhs, rhs in
            Self.packagePriority(lhs.lastPathComponent) < Self.packagePriority(rhs.lastPathComponent)
        } ?? []

        self.packages = try packageURLs.map(packageParser.parsePackage)
    }

    var allAssetPaths: Set<String> {
        packages.reduce(into: directAssetPaths) { result, package in
            for entry in package.entries {
                result.insert(entry.path)
            }
        }
    }

    var packageEntryExtensionCounts: [String: Int] {
        packages.reduce(into: [:]) { counts, package in
            for entry in package.entries {
                let ext = entry.path.wallpaperEnginePathExtension
                counts[ext.isEmpty ? "<none>" : ".\(ext)", default: 0] += 1
            }
        }
    }

    func data(for path: String) -> Data? {
        let normalizedPath = path.normalizedWallpaperEnginePath
        let fileURL = folderURL.appendingPathComponent(normalizedPath)

        if fileManager.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL) {
            return data
        }

        for package in packages {
            if let data = package.data(for: normalizedPath) {
                return data
            }
        }

        return nil
    }

    func string(for path: String) -> String? {
        guard let data = data(for: path) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func jsonObject(for path: String) -> [String: Any]? {
        guard let data = data(for: path) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func directAssetPaths(in folderURL: URL, fileManager: FileManager) -> Set<String> {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths = Set<String>()
        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(
                of: folderURL.path + "/",
                with: ""
            )
            paths.insert(relativePath.normalizedWallpaperEnginePath)
        }
        return paths
    }

    private static func packagePriority(_ filename: String) -> Int {
        switch filename.lowercased() {
        case "scene.pkg":
            return 0
        case "gifscene.pkg":
            return 1
        default:
            return 2
        }
    }
}
