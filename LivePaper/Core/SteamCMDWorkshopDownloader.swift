import Foundation

enum SteamCMDDownloadError: LocalizedError {
    case steamCMDNotFound([String])
    case invalidSteamCMDURL(URL)
    case missingSteamUsername
    case commandFailed(status: Int32, log: String)
    case commandScriptDidNotRun(itemID: String, log: String)
    case notLoggedOn(String)
    case workshopDownloadFailed(itemID: String, log: String)
    case downloadedItemNotFound(itemID: String, log: String)

    var errorDescription: String? {
        switch self {
        case .steamCMDNotFound(let checkedPaths):
            let checkedPathList = checkedPaths.joined(separator: ", ")
            return "SteamCMD was not found. Choose the steamcmd executable manually or install it with Homebrew. Checked: \(checkedPathList)"
        case .invalidSteamCMDURL(let url):
            return "Selected SteamCMD path could not be run: \(url.path)"
        case .missingSteamUsername:
            return "Enter your Steam account name for Account Session mode. LivePaper only sends the username; sign in with steamcmd in Terminal first."
        case .commandFailed(let status, _):
            return "SteamCMD failed with exit code \(status). Check the SteamCMD log for details."
        case .commandScriptDidNotRun(let itemID, _):
            return "SteamCMD started, but the download command for Workshop item \(itemID) did not run. Check the SteamCMD log for details."
        case .notLoggedOn(let username):
            return "SteamCMD is not logged in as \(username). Run steamcmd login \(username) in Terminal, finish Steam Guard if prompted, then try again."
        case .workshopDownloadFailed(let itemID, _):
            return "SteamCMD could not download Workshop item \(itemID). Steam returned a download failure, which usually means anonymous download is not allowed for this item or it is unavailable. Subscribe/download it in Steam first, then try again."
        case .downloadedItemNotFound(let itemID, _):
            return "SteamCMD finished, but Workshop item \(itemID) was not found in the download folders. Check the SteamCMD log for details."
        }
    }
}

enum SteamCMDLoginMode: String, CaseIterable, Identifiable, Sendable {
    case anonymous
    case accountSession

    var id: Self { self }

    var title: String {
        switch self {
        case .anonymous:
            return "Anonymous"
        case .accountSession:
            return "Account Session"
        }
    }
}

actor SteamCMDWorkshopDownloader {
    typealias LogHandler = @Sendable (String) async -> Void

    private let appID = "431960"
    private let fileManager = FileManager.default
    private let explicitSteamCMDURL: URL?
    private let loginMode: SteamCMDLoginMode
    private let username: String?

    init(steamCMDURL: URL? = nil, loginMode: SteamCMDLoginMode = .anonymous, username: String? = nil) {
        self.explicitSteamCMDURL = steamCMDURL
        self.loginMode = loginMode
        self.username = username?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func downloadWorkshopItem(from rawURL: String, logHandler: LogHandler? = nil) async throws -> URL {
        await logHandler?("[LivePaper] Preparing Steam Workshop download.\n")
        let workshopURL = try SteamWorkshopURL(rawURL)
        await logHandler?("[LivePaper] Workshop item: \(workshopURL.itemID)\n")
        if loginMode == .accountSession, username?.isEmpty ?? true {
            throw SteamCMDDownloadError.missingSteamUsername
        }

        let didStartAccessing = explicitSteamCMDURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didStartAccessing {
                explicitSteamCMDURL?.stopAccessingSecurityScopedResource()
            }
        }

        let steamCMDInvocation = try await resolveSteamCMDInvocation()
        let downloadRootURL = try livePaperDownloadRootURL()
        let logURL = downloadRootURL.appendingPathComponent("steamcmd-\(workshopURL.itemID).log")
        await logHandler?("[LivePaper] SteamCMD: \(steamCMDInvocation.steamCMDURL.path)\n")
        await logHandler?("[LivePaper] Log file: \(logURL.path)\n")

        try fileManager.createDirectory(at: downloadRootURL, withIntermediateDirectories: true)
        fileManager.createFile(atPath: logURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: logURL)
        defer { outputHandle.closeFile() }

        let process = Process()
        process.executableURL = steamCMDInvocation.executableURL
        process.currentDirectoryURL = downloadRootURL
        process.arguments = steamCMDInvocation.argumentPrefix
        process.environment = steamCMDEnvironment(libraryDirectoryURL: steamCMDInvocation.libraryDirectoryURL)
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let terminationStream = processTerminationStream(process)
        try process.run()
        let outputTask = drainOutputPipe(outputPipe, to: outputHandle, logHandler: logHandler)

        await logHandler?("[LivePaper] SteamCMD started.\n")
        inputPipe.fileHandleForWriting.write(
            steamCMDInputScript(itemID: workshopURL.itemID, downloadRootURL: downloadRootURL)
                .data(using: .utf8) ?? Data()
        )
        inputPipe.fileHandleForWriting.closeFile()
        let terminationStatus = await processTerminationStatus(from: terminationStream, process: process)
        outputPipe.fileHandleForWriting.closeFile()
        _ = await outputTask.result
        outputHandle.synchronizeFile()
        await logHandler?("[LivePaper] SteamCMD exited with code \(terminationStatus).\n")

        let log = logExcerpt(from: logURL)
        guard terminationStatus == 0 else {
            throw SteamCMDDownloadError.commandFailed(status: terminationStatus, log: log)
        }

        if let folderURL = downloadedItemFolderURL(
            itemID: workshopURL.itemID,
            downloadRootURL: downloadRootURL,
            steamCMDURL: steamCMDInvocation.steamCMDURL
        ) {
            await logHandler?("[LivePaper] Download folder: \(folderURL.path)\n")
            return folderURL
        }

        if steamCMDLogIndicatesNotLoggedOn(log), let username {
            throw SteamCMDDownloadError.notLoggedOn(username)
        }

        if !steamCMDLogIndicatesDownloadCommandRan(log, itemID: workshopURL.itemID) {
            throw SteamCMDDownloadError.commandScriptDidNotRun(itemID: workshopURL.itemID, log: log)
        }

        if steamCMDLogIndicatesWorkshopFailure(log, itemID: workshopURL.itemID) {
            throw SteamCMDDownloadError.workshopDownloadFailed(itemID: workshopURL.itemID, log: log)
        }

        throw SteamCMDDownloadError.downloadedItemNotFound(itemID: workshopURL.itemID, log: log)
    }

    private func resolveSteamCMDInvocation() async throws -> SteamCMDInvocation {
        if let explicitSteamCMDURL {
            if let invocation = invocation(for: explicitSteamCMDCandidates(from: explicitSteamCMDURL)) {
                return invocation
            }
        }

        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = environmentPath
            .split(separator: ":")
            .map(String.init)
            .map { URL(fileURLWithPath: $0).appendingPathComponent("steamcmd") }

        let candidates = await shellSteamCMDCandidates() + [
            URL(fileURLWithPath: "/opt/homebrew/bin/steamcmd"),
            URL(fileURLWithPath: "/usr/local/bin/steamcmd"),
            URL(fileURLWithPath: "/usr/bin/steamcmd")
        ] + pathCandidates + caskSteamCMDCandidates()

        if let invocation = invocation(for: candidates) {
            return invocation
        }

        if let explicitSteamCMDURL {
            throw SteamCMDDownloadError.invalidSteamCMDURL(explicitSteamCMDURL)
        }
        throw SteamCMDDownloadError.steamCMDNotFound(candidates.map(\.path))
    }

    private func livePaperDownloadRootURL() throws -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupportURL
            .appendingPathComponent("LivePaper")
            .appendingPathComponent("SteamCMD")
    }

    private func steamCMDEnvironment(libraryDirectoryURL: URL?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let knownPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = environment["PATH"], !currentPath.isEmpty {
            environment["PATH"] = "\(knownPaths):\(currentPath)"
        } else {
            environment["PATH"] = knownPaths
        }

        if let libraryDirectoryURL {
            environment["DYLD_LIBRARY_PATH"] = libraryDirectoryURL.path
            environment["DYLD_FRAMEWORK_PATH"] = libraryDirectoryURL.path
        }
        return environment
    }

    private func caskSteamCMDCandidates() -> [URL] {
        var candidates: [URL] = []
        let caskRootURLs = [
            URL(fileURLWithPath: "/opt/homebrew/Caskroom/steamcmd"),
            URL(fileURLWithPath: "/usr/local/Caskroom/steamcmd")
        ]

        for caskRootURL in caskRootURLs {
            guard let versions = try? fileManager.contentsOfDirectory(at: caskRootURL, includingPropertiesForKeys: nil) else {
                continue
            }

            for versionURL in versions {
                candidates.append(versionURL.appendingPathComponent("MacOS/steamcmd"))
                candidates.append(versionURL.appendingPathComponent("MacOS/steamcmd.sh"))
                candidates.append(versionURL.appendingPathComponent("steamcmd.wrapper.sh"))
            }
        }

        return candidates
    }

    private func shellSteamCMDCandidates() async -> [URL] {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", steamCMDFinderScript]
        process.environment = steamCMDEnvironment(libraryDirectoryURL: nil)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            let terminationStream = processTerminationStream(process)
            try process.run()
            let outputTask = drainOutputPipe(outputPipe, collectOutput: true)
            let errorTask = drainOutputPipe(errorPipe)
            let terminationStatus = await processTerminationStatus(from: terminationStream, process: process)
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            guard terminationStatus == 0 else {
                return []
            }
            let data = await outputTask.value
            _ = await errorTask.value
            return String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
        } catch {
            return []
        }
    }

    private func drainOutputPipe(
        _ pipe: Pipe,
        to outputHandle: FileHandle? = nil,
        logHandler: LogHandler? = nil,
        collectOutput: Bool = false
    ) -> Task<Data, Never> {
        Task.detached(priority: .utility) {
            var collectedData = Data()

            while true {
                let data = pipe.fileHandleForReading.readData(ofLength: 32 * 1024)
                if data.isEmpty {
                    break
                }

                if collectOutput {
                    collectedData.append(data)
                }
                outputHandle?.write(data)

                if let logHandler, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    await logHandler(text)
                }
            }

            return collectedData
        }
    }

    private func processTerminationStream(_ process: Process) -> AsyncStream<Int32> {
        AsyncStream { continuation in
            process.terminationHandler = { process in
                continuation.yield(process.terminationStatus)
                continuation.finish()
            }
        }
    }

    private func processTerminationStatus(from stream: AsyncStream<Int32>, process: Process) async -> Int32 {
        for await status in stream {
            return status
        }
        return process.terminationStatus
    }

    private var steamCMDFinderScript: String {
        """
        set +e
        p="$(command -v steamcmd 2>/dev/null || true)"
        if [ -n "$p" ]; then
          printf '%s\\n' "$p"
          rp="$(/usr/bin/readlink "$p" 2>/dev/null || true)"
          if [ -n "$rp" ]; then
            case "$rp" in
              /*) printf '%s\\n' "$rp" ;;
              *) printf '%s\\n' "$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$rp" ;;
            esac
          fi
        fi
        for root in /opt/homebrew/Caskroom/steamcmd /usr/local/Caskroom/steamcmd; do
          if [ -d "$root" ]; then
            /usr/bin/find "$root" -path '*/MacOS/steamcmd' -type f -perm +111 -print 2>/dev/null
            /usr/bin/find "$root" -path '*/MacOS/steamcmd.sh' -type f -print 2>/dev/null
            /usr/bin/find "$root" -name 'steamcmd.wrapper.sh' -type f -print 2>/dev/null
          fi
        done
        """
    }

    private func explicitSteamCMDCandidates(from selectedURL: URL) -> [URL] {
        orderedUnique(
            preferredSteamCMDCandidates(for: selectedURL) +
                preferredSteamCMDCandidates(for: selectedURL.resolvingSymlinksInPath()) +
                [selectedURL, selectedURL.resolvingSymlinksInPath()]
        )
    }

    private func preferredSteamCMDCandidates(for url: URL) -> [URL] {
        let fileName = url.lastPathComponent

        if fileName == "steamcmd.wrapper.sh" {
            let versionURL = url.deletingLastPathComponent()
            return [
                versionURL.appendingPathComponent("MacOS/steamcmd"),
                versionURL.appendingPathComponent("MacOS/steamcmd.sh"),
                url
            ]
        }

        if fileName == "steamcmd.sh" {
            let macOSURL = url.deletingLastPathComponent()
            return [
                macOSURL.appendingPathComponent("steamcmd"),
                url
            ]
        }

        return [url]
    }

    private func invocation(for candidates: [URL]) -> SteamCMDInvocation? {
        let expandedCandidates = orderedUnique(
            candidates.flatMap { candidate in
                preferredSteamCMDCandidates(for: candidate) +
                    preferredSteamCMDCandidates(for: candidate.resolvingSymlinksInPath()) +
                    [candidate, candidate.resolvingSymlinksInPath()]
            }
        )

        for candidate in expandedCandidates {
            if candidate.pathExtension == "sh", fileManager.fileExists(atPath: candidate.path) {
                return SteamCMDInvocation(
                    executableURL: URL(fileURLWithPath: "/bin/bash"),
                    argumentPrefix: [candidate.path],
                    steamCMDURL: candidate,
                    libraryDirectoryURL: nil
                )
            }

            if fileManager.isExecutableFile(atPath: candidate.path) {
                return SteamCMDInvocation(
                    executableURL: candidate,
                    argumentPrefix: [],
                    steamCMDURL: candidate,
                    libraryDirectoryURL: candidate.lastPathComponent == "steamcmd" ? candidate.deletingLastPathComponent() : nil
                )
            }
        }
        return nil
    }

    private func orderedUnique(_ urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        var uniqueURLs: [URL] = []

        for url in urls where seenPaths.insert(url.path).inserted {
            uniqueURLs.append(url)
        }

        return uniqueURLs
    }

    private func downloadedItemFolderURL(itemID: String, downloadRootURL: URL, steamCMDURL: URL) -> URL? {
        let relativePath = "steamapps/workshop/content/\(appID)/\(itemID)"
        let candidates = [
            downloadRootURL.appendingPathComponent(relativePath),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Steam")
                .appendingPathComponent(relativePath),
            steamCMDURL.resolvingSymlinksInPath()
                .deletingLastPathComponent()
                .appendingPathComponent(relativePath)
        ]

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func steamCMDInputScript(itemID: String, downloadRootURL: URL) -> String {
        let loginCommand: String
        switch loginMode {
        case .anonymous:
            loginCommand = "login anonymous\n"
        case .accountSession:
            guard let username else { return "quit\n" }
            loginCommand = "login \(steamCMDEscapedToken(username))\n"
        }

        return """
        @ShutdownOnFailedCommand 1
        force_install_dir "\(steamCMDEscaped(downloadRootURL.path))"
        \(loginCommand)workshop_download_item \(appID) \(itemID)
        quit

        """
    }

    private func steamCMDEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func steamCMDEscapedToken(_ value: String) -> String {
        if value.contains(" ") || value.contains("\"") || value.contains("\\") {
            return "\"\(steamCMDEscaped(value))\""
        }
        return value
    }

    private func steamCMDLogIndicatesDownloadCommandRan(_ log: String, itemID: String) -> Bool {
        log.contains("workshop_download_item") ||
            log.contains("Downloading item \(itemID)") ||
            log.contains("Downloaded item \(itemID)") ||
            log.contains("ERROR! Download item \(itemID)")
    }

    private func steamCMDLogIndicatesWorkshopFailure(_ log: String, itemID: String) -> Bool {
        log.contains("ERROR! Download item \(itemID) failed") ||
            log.contains("ERROR! Download item") ||
            log.contains("failed (Failure)")
    }

    private func steamCMDLogIndicatesNotLoggedOn(_ log: String) -> Bool {
        log.contains("ERROR! Not logged on") || log.contains("Not logged on")
    }

    private func logExcerpt(from logURL: URL) -> String {
        guard let data = try? Data(contentsOf: logURL), !data.isEmpty else {
            return ""
        }

        let suffix = data.suffix(3_000)
        return String(decoding: suffix, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SteamCMDInvocation {
    let executableURL: URL
    let argumentPrefix: [String]
    let steamCMDURL: URL
    let libraryDirectoryURL: URL?
}
