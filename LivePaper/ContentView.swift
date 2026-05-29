//
//  ContentView.swift
//  LivePaper
//
//  Created by Limtaehyun on 5/29/26.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Bindable var coordinator: WallpaperCoordinator
    @State private var selectedNavigationTab: LivePaperNavigationTab = .wallpaper
    @State private var selectedGalleryItemID: WallpaperGalleryItem.ID?
    @State private var selectedFilter: WallpaperGalleryFilter = .all
    @State private var isWallpaperDetailPresented = false
    @State private var isAddWallpaperPresented = false

    var body: some View {
        ZStack {
            LivePaperGlassBackground()

            VStack(spacing: 0) {
                LivePaperTopBar(selectedTab: $selectedNavigationTab)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                selectedNavigationContent
                    .padding(.horizontal, 34)
                    .padding(.top, 34)
                    .padding(.bottom, 28)
            }
        }
        .frame(minWidth: 920, minHeight: 620)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            Task {
                await coordinator.shutdown()
            }
        }
        .sheet(isPresented: $isWallpaperDetailPresented) {
            if let selectedGalleryItem {
                WallpaperDetailSheet(coordinator: coordinator, item: selectedGalleryItem)
            }
        }
        .sheet(isPresented: $isAddWallpaperPresented) {
            AddWallpaperSheet(coordinator: coordinator, selectedGalleryItemID: $selectedGalleryItemID)
        }
    }

    @ViewBuilder
    private var selectedNavigationContent: some View {
        switch selectedNavigationTab {
        case .wallpaper:
            wallpaperTab
        case .displays:
            displaysTab
        case .settings:
            settingsTab
        }
    }

    private var wallpaperTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            mediaHeader
            mediaFilter

            wallpaperGallery
        }
    }

    private var mediaHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("My Media")
                    .font(.system(size: 36, weight: .bold, design: .serif))
                Text("\(coordinator.galleryItems.count) wallpaper\(coordinator.galleryItems.count == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer()

            Button {
                isAddWallpaperPresented = true
            } label: {
                Label("Add Wallpaper", systemImage: "plus.circle.fill")
            }
            .buttonStyle(GlassProminentButtonStyle())
        }
    }

    private var mediaFilter: some View {
        Picker("Filter", selection: $selectedFilter) {
            ForEach(WallpaperGalleryFilter.allCases) { filter in
                Label(filter.title, systemImage: filter.systemImage)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 300)
        .tint(.white)
    }

    private var wallpaperGallery: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                ForEach(filteredGalleryItems) { item in
                    Button {
                        selectGalleryItem(item)
                    } label: {
                        WallpaperCard(
                            item: item,
                            isSelected: selectedGalleryItemID == item.id || coordinator.selectedGalleryItemID == item.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
        .overlay {
            if filteredGalleryItems.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("No Wallpapers")
                        .font(.title3.weight(.semibold))
                    Text("Add a local video or web wallpaper to get started.")
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var displayList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Displays")
                    .font(.headline)
                Spacer()
                Button {
                    coordinator.refreshDisplays()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(GlassIconButtonStyle())
                .help("Refresh displays")
            }

            ForEach(coordinator.displays) { display in
                Toggle(isOn: displayBinding(for: display.id)) {
                    HStack {
                        Image(systemName: "display")
                            .frame(width: 22)
                        VStack(alignment: .leading) {
                            Text(display.name)
                            Text(display.frameDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12))
        }
    }

    private var displaysTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Displays")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                    Text("Choose where LivePaper can apply the selected wallpaper.")
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Button {
                    coordinator.refreshDisplays()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GlassProminentButtonStyle())
            }

            displayList

            HStack {
                Button {
                    Task {
                        await coordinator.restoreSavedWallpapers()
                    }
                } label: {
                    Label("Restore Saved Wallpapers", systemImage: "arrow.counterclockwise")
                }
                .disabled(!coordinator.hasSavedWallpapers)
                .buttonStyle(GlassSecondaryButtonStyle())

                Spacer()

                Button(role: .destructive) {
                    Task {
                        await coordinator.stopAll()
                    }
                } label: {
                    Label("Stop All", systemImage: "stop.fill")
                }
                .buttonStyle(GlassSecondaryButtonStyle())
            }

            Spacer(minLength: 0)
        }
    }

    private var displaySelectionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(coordinator.displays) { display in
                Toggle(isOn: displayBinding(for: display.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name)
                        Text(display.frameDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var selectedGalleryItem: WallpaperGalleryItem? {
        let id = selectedGalleryItemID ?? coordinator.selectedGalleryItemID
        return coordinator.galleryItems.first { $0.id == id }
    }

    private var filteredGalleryItems: [WallpaperGalleryItem] {
        coordinator.galleryItems.filter(selectedFilter.includes)
    }

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                    Text("Tune playback, power behavior, and saved wallpapers.")
                        .foregroundStyle(.white.opacity(0.58))
                }

                GlassSection(title: "Video") {
                    VStack(spacing: 0) {
                        GlassSettingsRow(
                            icon: "rectangle.arrowtriangle.2.inward",
                            iconColor: .blue,
                            title: "Scale Mode",
                            subtitle: "Controls how video fills each display."
                        ) {
                            Picker("Scale", selection: $coordinator.scaleMode) {
                                ForEach(ScaleMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        GlassDivider()

                        GlassSettingsRow(
                            icon: "speaker.slash.fill",
                            iconColor: .orange,
                            title: "Mute video audio",
                            subtitle: "Keep wallpapers silent by default."
                        ) {
                            Toggle("", isOn: $coordinator.muted)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        GlassDivider()

                        GlassSettingsRow(
                            icon: "speaker.wave.2.fill",
                            iconColor: .teal,
                            title: "Volume",
                            subtitle: "Applies only when audio is enabled."
                        ) {
                            HStack(spacing: 10) {
                                Slider(value: $coordinator.volume, in: 0...1)
                                    .frame(width: 160)
                                    .disabled(coordinator.muted)
                                Text(coordinator.volume, format: .percent.precision(.fractionLength(0)))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.68))
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                }

                GlassSection(title: "Power") {
                    VStack(spacing: 0) {
                        GlassSettingsRow(
                            icon: "battery.50",
                            iconColor: .green,
                            title: "Pause on battery",
                            subtitle: "Reduce work when the Mac is not plugged in."
                        ) {
                            Toggle("", isOn: $coordinator.pauseOnBattery)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        GlassDivider()

                        GlassSettingsRow(
                            icon: "rectangle.inset.filled",
                            iconColor: .purple,
                            title: "Pause on fullscreen",
                            subtitle: "Avoid rendering behind fullscreen apps when detected."
                        ) {
                            Toggle("", isOn: $coordinator.pauseOnFullscreen)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }

                GlassSection(title: "Saved Wallpapers") {
                    VStack(spacing: 0) {
                        GlassSettingsRow(
                            icon: "arrow.counterclockwise",
                            iconColor: .cyan,
                            title: "Restore Saved Wallpapers",
                            subtitle: "Restart saved display sessions."
                        ) {
                            Button("Restore") {
                                Task {
                                    await coordinator.restoreSavedWallpapers()
                                }
                            }
                            .buttonStyle(GlassSecondaryButtonStyle())
                            .disabled(!coordinator.hasSavedWallpapers)
                        }

                        GlassDivider()

                        GlassSettingsRow(
                            icon: "trash.fill",
                            iconColor: .red,
                            title: "Forget Saved Wallpapers",
                            subtitle: "Remove persisted display assignments."
                        ) {
                            Button("Forget", role: .destructive) {
                                Task {
                                    await coordinator.forgetSavedWallpapers()
                                }
                            }
                            .buttonStyle(GlassSecondaryButtonStyle())
                            .disabled(!coordinator.hasSavedWallpapers)
                        }
                    }
                }

                GlassSection(title: "Steam") {
                    GlassSettingsRow(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .orange,
                        title: "Sync Steam Metadata",
                        subtitle: "Refresh imported Workshop titles and previews."
                    ) {
                        Button("Sync") {
                            coordinator.syncSteamMetadata()
                        }
                        .buttonStyle(GlassSecondaryButtonStyle())
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .onChange(of: coordinator.scaleMode) { _, _ in
            saveRuntimeSettings()
        }
        .onChange(of: coordinator.muted) { _, _ in
            saveRuntimeSettings()
        }
        .onChange(of: coordinator.volume) { _, _ in
            saveRuntimeSettings()
        }
        .onChange(of: coordinator.pauseOnBattery) { _, _ in
            saveRuntimeSettings()
        }
        .onChange(of: coordinator.pauseOnFullscreen) { _, _ in
            saveRuntimeSettings()
        }
    }

    private func selectGalleryItem(_ item: WallpaperGalleryItem) {
        selectedGalleryItemID = item.id
        coordinator.selectGalleryItem(id: item.id)
        isWallpaperDetailPresented = true
    }

    private func displayBinding(for id: DisplayID) -> Binding<Bool> {
        Binding {
            coordinator.selectedDisplayIDs.contains(id)
        } set: { isSelected in
            if isSelected {
                coordinator.selectedDisplayIDs.insert(id)
            } else {
                coordinator.selectedDisplayIDs.remove(id)
            }
        }
    }

    private func saveRuntimeSettings() {
        Task {
            await coordinator.updateRuntimePreferences()
        }
    }
}

private struct AddWallpaperSheet: View {
    @Bindable var coordinator: WallpaperCoordinator
    @Binding var selectedGalleryItemID: WallpaperGalleryItem.ID?
    @Environment(\.dismiss) private var dismiss
    @State private var webAddress = "https://"
    @State private var steamWorkshopAddress = "https://steamcommunity.com/sharedfiles/filedetails/?id="
    @State private var errorMessage: String?
    @State private var isSteamCMDDownloading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Wallpaper")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Local Video")
                    .font(.headline)

                Button {
                    chooseVideo()
                } label: {
                    Label("Choose Video...", systemImage: "film")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Steam Workshop")
                    .font(.headline)

                TextField("https://steamcommunity.com/sharedfiles/filedetails/?id=123456789", text: $steamWorkshopAddress)
                    .textFieldStyle(.roundedBorder)

                Picker("Login", selection: $coordinator.steamCMDLoginMode) {
                    ForEach(SteamCMDLoginMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if coordinator.steamCMDLoginMode == .accountSession {
                    TextField("Steam account name", text: $coordinator.steamUsername)
                        .textFieldStyle(.roundedBorder)

                    Text("Run steamcmd login in Terminal first. LivePaper will reuse that saved SteamCMD session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        Task {
                            await downloadSteamWorkshop()
                        }
                    } label: {
                        Label(isSteamCMDDownloading ? "Downloading..." : "Download with SteamCMD", systemImage: "arrow.down.circle")
                    }
                    .disabled(isSteamCMDDownloading)

                    Button {
                        chooseSteamCMD()
                    } label: {
                        Label("Choose SteamCMD...", systemImage: "terminal")
                    }
                    .disabled(isSteamCMDDownloading)
                }

                if isSteamCMDDownloading || !coordinator.steamDownloadLog.isEmpty {
                    steamDownloadLogView
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("URL")
                    .font(.headline)

                TextField("https://example.com", text: $webAddress)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button {
                    addURL()
                } label: {
                    Label("Add URL", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 620)
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
                .frame(height: 170)
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

        coordinator.selectVideo(url: url)
        selectedGalleryItemID = coordinator.selectedGalleryItemID
        dismiss()
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

        coordinator.selectWebPage(url: url)
        selectedGalleryItemID = coordinator.selectedGalleryItemID
        dismiss()
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

private struct WallpaperDetailSheet: View {
    @Bindable var coordinator: WallpaperCoordinator
    @Environment(\.dismiss) private var dismiss
    let item: WallpaperGalleryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    Text((item.sourceURL ?? item.url).absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WallpaperPreview(item: item, iconSize: 48)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)

                    HStack(spacing: 10) {
                        Label(item.subtitle, systemImage: item.kind == .video ? "film" : "globe")
                        if item.savedDisplayCount > 0 {
                            Label("\(item.savedDisplayCount) saved", systemImage: "display")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    Divider()

                    Text("Apply to Displays")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(coordinator.displays) { display in
                            Toggle(isOn: displayBinding(for: display.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(display.name)
                                    Text(display.frameDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let error = coordinator.lastError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button {
                    Task {
                        await coordinator.applySelectedContent()
                        if coordinator.lastError == nil {
                            dismiss()
                        }
                    }
                } label: {
                    Label("Apply Wallpaper", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.selectedDisplayIDs.isEmpty)
            }
            .padding(24)
        }
        .frame(width: 560, height: 640)
    }

    private func displayBinding(for id: DisplayID) -> Binding<Bool> {
        Binding {
            coordinator.selectedDisplayIDs.contains(id)
        } set: { isSelected in
            if isSelected {
                coordinator.selectedDisplayIDs.insert(id)
            } else {
                coordinator.selectedDisplayIDs.remove(id)
            }
        }
    }
}

private enum WallpaperGalleryFilter: String, CaseIterable, Identifiable {
    case all
    case local
    case web

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .local:
            return "Local"
        case .web:
            return "Web"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "folder"
        case .local:
            return "externaldrive"
        case .web:
            return "globe"
        }
    }

    func includes(_ item: WallpaperGalleryItem) -> Bool {
        switch self {
        case .all:
            return true
        case .local:
            return item.url.isFileURL
        case .web:
            return item.kind == .web
        }
    }
}

private struct WallpaperCard: View {
    let item: WallpaperGalleryItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WallpaperPreview(item: item, iconSize: 34)
            .aspectRatio(16 / 10, contentMode: .fit)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if item.savedDisplayCount > 0 {
                    Label("\(item.savedDisplayCount) saved", systemImage: "display")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        }
    }
}

private struct WallpaperPreview: View {
    let item: WallpaperGalleryItem
    let iconSize: CGFloat

    var body: some View {
        ZStack {
            fallbackBackground

            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.kind == .video ? "film.fill" : "globe")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(item.kind == .video ? .blue : .green)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

private enum LivePaperNavigationTab: String, CaseIterable, Identifiable {
    case wallpaper
    case displays
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .wallpaper:
            return "My Media"
        case .displays:
            return "Displays"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .wallpaper:
            return "folder.fill"
        case .displays:
            return "display.2"
        case .settings:
            return "gearshape.fill"
        }
    }
}

private struct LivePaperGlassBackground: View {
    var body: some View {
        ZStack {
            Color.black

            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.05),
                    Color(red: 0.00, green: 0.00, blue: 0.00),
                    Color(red: 0.03, green: 0.06, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.25, green: 0.52, blue: 0.62).opacity(0.24),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    Color(red: 0.86, green: 0.28, blue: 0.22).opacity(0.15),
                    .clear
                ],
                center: .bottom,
                startRadius: 40,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

private struct LivePaperTopBar: View {
    @Binding var selectedTab: LivePaperNavigationTab

    var body: some View {
        HStack {
            Color.clear
                .frame(width: 112, height: 1)

            Spacer()

            HStack(spacing: 3) {
                ForEach(LivePaperNavigationTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .labelStyle(.titleOnly)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.62))
                            .frame(minWidth: 92)
                            .padding(.vertical, 8)
                            .background {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(.white.opacity(0.17))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.on.rectangle")
                Text("LivePaper")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.68))
            .frame(width: 112, alignment: .trailing)
        }
    }
}

private struct GlassSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 10)

            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.12))
                }
        }
    }
}

private struct GlassSettingsRow<Accessory: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.gradient)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
    }
}

private struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 56)
    }
}

private struct GlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(configuration.isPressed ? 0.18 : 0.24),
                        Color.white.opacity(configuration.isPressed ? 0.08 : 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.16))
            }
    }
}

private struct GlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.62 : 0.86))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.12))
            }
    }
}

private struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.58 : 0.84))
            .frame(width: 30, height: 30)
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0.13), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.12))
            }
    }
}

#if DEBUG
#Preview {
    ContentView(coordinator: WallpaperCoordinator())
}
#endif
