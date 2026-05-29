import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AddWallpaperMode: String, CaseIterable, Identifiable {
    case localVideo
    case webURL
    case steamWorkshop

    var id: Self { self }

    var title: String {
        switch self {
        case .localVideo:
            return "Local"
        case .steamWorkshop:
            return "Steam Workshop"
        case .webURL:
            return "Web"
        }
    }

    var systemImage: String {
        switch self {
        case .localVideo:
            return "film"
        case .steamWorkshop:
            return "shippingbox"
        case .webURL:
            return "link"
        }
    }

    var primaryActionTitle: String {
        "Create Wallpaper"
    }

}

struct AddWallpaperSheet: View {
    @Bindable var coordinator: WallpaperCoordinator
    @Binding var selectedGalleryItemID: WallpaperGalleryItem.ID?
    @Environment(\.dismiss) private var dismiss
    @State private var webAddress = ""
    @State private var steamWorkshopAddress = ""
    @State private var errorMessage: String?
    @State private var errorAlert: AlertMessage?
    @State private var isSteamCMDDownloading = false
    @State private var selectedAddMode: AddWallpaperMode = .localVideo
    @State private var isLocalVideoDropTargeted = false
    @State private var selectedLocalVideoURL: URL?
    @State private var draftWallpaperTitle = ""
    @State private var draftPreviewImageURL: URL?
    @State private var isMetadataLoading = false
    @State private var metadataRequestID = 0
    @State private var metadataSourceURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                Text("Add Wallpaper")
                    .font(.largeTitle.bold())

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .focusable(false)
                .help("Close")
            }

            Picker("Wallpaper source", selection: $selectedAddMode) {
                ForEach(AddWallpaperMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Group {
                switch selectedAddMode {
                case .localVideo:
                    localVideoContent
                case .steamWorkshop:
                    ScrollView(showsIndicators: false) {
                        steamWorkshopContent
                    }
                case .webURL:
                    webURLContent
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .frame(height: 300, alignment: .top)

            Spacer(minLength: 0)

            Button {
                performPrimaryAction()
            } label: {
                Text(primaryActionTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(primaryActionDisabled)
            .opacity(primaryActionDisabled ? 0.55 : 1)
            .focusable(false)
        }
        .padding(24)
        .frame(width: 360, height: 560)
        .onChange(of: selectedAddMode) { _, _ in
            errorMessage = nil
            resetDraftMetadata()
        }
        .onChange(of: errorMessage) { _, message in
            guard let message else {
                return
            }
            errorAlert = AlertMessage(message: message)
        }
        .alert(item: $errorAlert) { alert in
            Alert(
                title: Text("LivePaper"),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    errorMessage = nil
                    coordinator.clearLastError()
                }
            )
        }
        .onChange(of: webAddress) { _, _ in
            scheduleYouTubeMetadataExtraction()
        }
    }

    private var localVideoContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                chooseVideo()
            } label: {
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        Text(localVideoDropTitle)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text(localVideoDropSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isLocalVideoDropTargeted ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(isLocalVideoDropTargeted ? Color.accentColor : Color.white.opacity(0.18), lineWidth: 1.5)
                }
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isLocalVideoDropTargeted) { providers in
                handleVideoDrop(providers)
            }

            metadataEditor
        }
    }

    private var localVideoDropTitle: String {
        selectedLocalVideoURL?.lastPathComponent ?? "Drop or click this section to select video"
    }

    private var localVideoDropSubtitle: String {
        selectedLocalVideoURL == nil
            ? "Supported formats: .mp4, .mov, .m4v, .mkv"
            : "Click Create Wallpaper to add it to your library."
    }

    private var steamWorkshopContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workshop URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("https://steamcommunity.com/sharedfiles/filedetails/?id=123456789", text: $steamWorkshopAddress)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Account Mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Account Mode", selection: $coordinator.steamCMDLoginMode) {
                    ForEach(SteamCMDLoginMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if coordinator.steamCMDLoginMode == .accountSession {
                TextField("Steam account username", text: $coordinator.steamUsername)
                    .textFieldStyle(.roundedBorder)
            }

            if isSteamCMDDownloading || !coordinator.steamDownloadLog.isEmpty {
                steamDownloadLogView
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, 2)
    }

    private var webURLContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("https://example.com", text: $webAddress)
                    .textFieldStyle(.roundedBorder)
            }

            Text("YouTube links and regular web pages can be added as web wallpapers. YouTube URLs are automatically converted to an embeddable player.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            metadataEditor
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var metadataEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                metadataPreview

                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Wallpaper title", text: $draftWallpaperTitle)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if isMetadataLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                    Text("Extracting metadata...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var metadataPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))

            if let image = draftPreviewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 78, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: selectedAddMode == .localVideo ? "film" : "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 78, height: 44)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.12))
        }
    }

    private var draftPreviewImage: NSImage? {
        guard let draftPreviewImageURL, draftPreviewImageURL.isFileURL else {
            return nil
        }
        return NSImage(contentsOf: draftPreviewImageURL)
    }

    private var primaryActionTitle: String {
        if selectedAddMode == .steamWorkshop, isSteamCMDDownloading {
            return "Downloading"
        }
        return selectedAddMode.primaryActionTitle
    }

    private var primaryActionDisabled: Bool {
        switch selectedAddMode {
        case .localVideo:
            return selectedLocalVideoURL == nil
        case .steamWorkshop:
            return false
        case .webURL:
            return false
        }
    }

    private func performPrimaryAction() {
        switch selectedAddMode {
        case .localVideo:
            createLocalVideoWallpaper()
        case .steamWorkshop:
            guard !isSteamCMDDownloading else {
                return
            }
            Task {
                await downloadSteamWorkshop()
            }
        case .webURL:
            addURL()
        }
    }

    private var steamDownloadLogView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("SteamCMD Log", systemImage: isSteamCMDDownloading ? "arrow.down.circle" : "terminal")
                    .font(.caption.weight(.semibold))

                if isSteamCMDDownloading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                }

                Spacer()

                Button {
                    coordinator.clearSteamDownloadLog()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .focusable(false)
                .help("Clear SteamCMD log")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(coordinator.steamDownloadLog.isEmpty ? "Waiting for SteamCMD output..." : coordinator.steamDownloadLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)

                    Color.clear
                        .frame(height: 1)
                        .id("steam-log-bottom")
                }
                .frame(height: 118)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18))
                }
                .onChange(of: coordinator.steamDownloadLog) { _, _ in
                    proxy.scrollTo("steam-log-bottom", anchor: .bottom)
                }
            }
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.title = "Choose Video"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .movie,
            .video,
            .mpeg4Movie,
            .quickTimeMovie,
            UTType(filenameExtension: "m4v") ?? .movie,
            UTType(filenameExtension: "mkv") ?? .movie
        ]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        selectedLocalVideoURL = url
        errorMessage = nil
        loadLocalVideoMetadata(for: url)
    }

    private func createLocalVideoWallpaper() {
        guard let selectedLocalVideoURL else {
            chooseVideo()
            return
        }

        coordinator.selectVideo(url: selectedLocalVideoURL, title: draftWallpaperTitle, previewImageURL: draftPreviewImageURL)
        selectedGalleryItemID = coordinator.selectedGalleryItemID
        dismiss()
    }

    private func selectDroppedVideo(url: URL) {
        guard isSupportedVideoURL(url) else {
            errorMessage = "Drop a supported video file: .mp4, .mov, .m4v, or .mkv."
            return
        }

        selectedLocalVideoURL = url
        errorMessage = nil
        loadLocalVideoMetadata(for: url)
    }

    private func handleVideoDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }

            guard let url else {
                return
            }

            Task { @MainActor in
                selectDroppedVideo(url: url)
            }
        }

        return true
    }

    private func isSupportedVideoURL(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let supportedExtensions = Set(["mp4", "mov", "m4v", "mkv"])
        if supportedExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return contentType.conforms(to: .movie) || contentType.conforms(to: .video)
    }

    private func downloadSteamWorkshop() async {
        guard steamWorkshopURLIsValid(steamWorkshopAddress) else {
            errorMessage = "Enter a valid Steam Workshop URL before downloading."
            return
        }

        errorMessage = nil
        isSteamCMDDownloading = true
        let error = await coordinator.downloadSteamWorkshop(url: steamWorkshopAddress)
        isSteamCMDDownloading = false

        if shouldChooseSteamCMDAfterDownloadError(error), chooseSteamCMD() {
            await downloadSteamWorkshop()
            return
        }

        finishImportIfNeeded()
    }

    private func shouldChooseSteamCMDAfterDownloadError(_ error: Error?) -> Bool {
        guard let downloadError = error as? SteamCMDDownloadError else {
            return false
        }

        switch downloadError {
        case .steamCMDNotFound, .invalidSteamCMDURL:
            return true
        case .commandFailed(let status, let log):
            return status == 126 || log.contains("Operation not permitted")
        case .missingSteamUsername, .commandScriptDidNotRun, .notLoggedOn, .workshopDownloadFailed, .downloadedItemNotFound:
            return false
        }
    }

    @discardableResult
    private func chooseSteamCMD() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose SteamCMD"
        panel.message = "Choose the real steamcmd executable, usually Caskroom/steamcmd/<version>/MacOS/steamcmd."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = steamCMDPickerDirectoryURL()

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        coordinator.setSteamCMDURL(url)
        errorMessage = nil
        return true
    }

    private func steamCMDPickerDirectoryURL() -> URL {
        let caskRootURLs = [
            URL(fileURLWithPath: "/opt/homebrew/Caskroom/steamcmd"),
            URL(fileURLWithPath: "/usr/local/Caskroom/steamcmd")
        ]

        for caskRootURL in caskRootURLs {
            guard let versions = try? FileManager.default.contentsOfDirectory(at: caskRootURL, includingPropertiesForKeys: nil),
                  let latestVersionURL = versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else {
                continue
            }

            let macOSURL = latestVersionURL.appendingPathComponent("MacOS")
            if FileManager.default.fileExists(atPath: macOSURL.appendingPathComponent("steamcmd").path) {
                return macOSURL
            }
        }

        return URL(fileURLWithPath: "/opt/homebrew/bin")
    }

    private func addURL() {
        guard let url = URL(string: webAddress),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            errorMessage = "Enter a valid http or https URL."
            return
        }

        Task {
            if YouTubeEmbedURL.videoID(from: url) != nil, draftWallpaperTitle.isEmpty || draftPreviewImageURL == nil {
                await loadYouTubeMetadata(for: url)
            }

            coordinator.selectWebPage(url: url, title: draftWallpaperTitle, previewImageURL: draftPreviewImageURL)
            selectedGalleryItemID = coordinator.selectedGalleryItemID
            dismiss()
        }
    }

    private func resetDraftMetadata() {
        metadataRequestID += 1
        isMetadataLoading = false
        draftWallpaperTitle = ""
        draftPreviewImageURL = nil
        metadataSourceURL = nil
        if selectedAddMode != .localVideo {
            selectedLocalVideoURL = nil
        }
    }

    private func loadLocalVideoMetadata(for url: URL) {
        metadataRequestID += 1
        let requestID = metadataRequestID
        metadataSourceURL = url
        isMetadataLoading = true

        Task {
            let metadata = await WallpaperMetadataExtractor.localVideoMetadata(for: url)
            await MainActor.run {
                guard metadataRequestID == requestID, selectedLocalVideoURL == url else {
                    return
                }
                draftWallpaperTitle = metadata.title ?? url.deletingPathExtension().lastPathComponent
                draftPreviewImageURL = metadata.previewImageURL
                isMetadataLoading = false
            }
        }
    }

    private func scheduleYouTubeMetadataExtraction() {
        metadataRequestID += 1
        guard selectedAddMode == .webURL, let url = URL(string: webAddress), YouTubeEmbedURL.videoID(from: url) != nil else {
            isMetadataLoading = false
            return
        }

        if metadataSourceURL != url {
            draftWallpaperTitle = ""
            draftPreviewImageURL = nil
            metadataSourceURL = url
        }
        let requestID = metadataRequestID
        isMetadataLoading = true

        Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else {
                return
            }
            let metadata = await WallpaperMetadataExtractor.youTubeMetadata(for: url)
            await MainActor.run {
                guard metadataRequestID == requestID, webAddress == url.absoluteString else {
                    return
                }
                if let title = metadata?.title, draftWallpaperTitle.isEmpty {
                    draftWallpaperTitle = title
                }
                if let previewImageURL = metadata?.previewImageURL {
                    draftPreviewImageURL = previewImageURL
                }
                isMetadataLoading = false
            }
        }
    }

    private func loadYouTubeMetadata(for url: URL) async {
        isMetadataLoading = true
        let metadata = await WallpaperMetadataExtractor.youTubeMetadata(for: url)
        if let title = metadata?.title, draftWallpaperTitle.isEmpty {
            draftWallpaperTitle = title
        }
        if let previewImageURL = metadata?.previewImageURL {
            draftPreviewImageURL = previewImageURL
        }
        isMetadataLoading = false
    }

    private func finishImportIfNeeded() {
        if let lastError = coordinator.lastError {
            errorMessage = lastError
            return
        }

        selectedGalleryItemID = coordinator.selectedGalleryItemID
        dismiss()
    }

    private func steamWorkshopURLIsValid(_ rawURL: String) -> Bool {
        (try? SteamWorkshopURL(rawURL)) != nil
    }
}
