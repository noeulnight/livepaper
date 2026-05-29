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
    @State private var isWallpaperDetailPresented = false
    @State private var isAddWallpaperPresented = false
    @State private var displayErrorAlert: AlertMessage?

    var body: some View {
        ZStack(alignment: .bottom) {
            LivePaperGlassBackground()

            selectedNavigationContent
                .padding(.horizontal, 34)
                .padding(.top, 34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            LivePaperBottomTabBar(selectedTab: $selectedNavigationTab)
                .padding(.horizontal, 24)
                .padding(.bottom, LivePaperBottomTabMetrics.bottomPadding)
                .zIndex(1)
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
        .onChange(of: coordinator.lastError) { _, error in
            guard selectedNavigationTab == .displays, let error else {
                return
            }
            displayErrorAlert = AlertMessage(message: error)
        }
        .alert(item: $displayErrorAlert) { alert in
            Alert(
                title: Text("LivePaper"),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    coordinator.clearLastError()
                }
            )
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
            wallpaperHeader

            wallpaperGallery
        }
    }

    private var wallpaperHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wallpapers")
                    .font(.largeTitle.bold())
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
            .focusable(false)
        }
    }

    private var wallpaperGallery: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: WallpaperCardMetrics.width,
                            maximum: WallpaperCardMetrics.width
                        ),
                        spacing: 16,
                        alignment: .top
                    )
                ],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(coordinator.galleryItems) { item in
                    Button {
                        selectGalleryItem(item)
                    } label: {
                        WallpaperCard(
                            item: item,
                            isSelected: selectedGalleryItemID == item.id || coordinator.selectedGalleryItemID == item.id
                        )
                    }
                    .frame(width: WallpaperCardMetrics.width, height: WallpaperCardMetrics.height)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(.top, 2)
            .padding(.trailing, 18)
            .padding(.bottom, LivePaperBottomTabMetrics.scrollContentTailPadding)
        }
        .overlay {
            if coordinator.galleryItems.isEmpty {
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
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: DisplayCardMetrics.width,
                            maximum: DisplayCardMetrics.width
                        ),
                        spacing: 16,
                        alignment: .top
                    )
                ],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(coordinator.displays) { display in
                    DisplayCard(
                        display: display,
                        wallpaperItem: coordinator.displayWallpaperItem(for: display.id),
                        description: displayRuntimeDescription(for: display),
                        isEnabled: displayRuntimeBinding(for: display.id),
                        isAudioDisplay: coordinator.audioDisplayID == display.id,
                        audioSystemImage: audioDisplaySystemImage(for: display.id)
                    ) {
                        Task {
                            await coordinator.setAudioDisplay(display.id)
                        }
                    }
                    .frame(width: DisplayCardMetrics.width, height: DisplayCardMetrics.height)
                }
            }
            .padding(.top, 2)
            .padding(.trailing, 18)
            .padding(.bottom, LivePaperBottomTabMetrics.scrollContentTailPadding)
        }
        .overlay {
            if coordinator.displays.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("No Displays")
                        .font(.title3.weight(.semibold))
                    Text("Connect a display or refresh to scan again.")
                        .foregroundStyle(.white.opacity(0.48))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var displaysTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Displays")
                        .font(.largeTitle.bold())
                    Text("Manage active and saved wallpaper session per display.")
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Button {
                    coordinator.refreshDisplays()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GlassProminentButtonStyle())
                .focusable(false)
            }

            displayList

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
            .padding(.bottom, LivePaperBottomTabMetrics.scrollContentTailPadding)
        }
    }

    private var selectedGalleryItem: WallpaperGalleryItem? {
        let id = selectedGalleryItemID ?? coordinator.selectedGalleryItemID
        return coordinator.galleryItems.first { $0.id == id }
    }

    private var settingsTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.largeTitle.bold())
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

                        GlassDivider()

                        GlassSettingsRow(
                            icon: "speaker.slash",
                            iconColor: .orange,
                            title: "Mute on fullscreen",
                            subtitle: "Silence wallpaper audio behind full-screen windows."
                        ) {
                            Toggle("", isOn: $coordinator.muteOnFullscreen)
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
                            .focusable(false)
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
                            .focusable(false)
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
                        .focusable(false)
                    }
                }
            }
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
        .onChange(of: coordinator.audioDisplayID) { _, _ in
            saveRuntimeSettings()
        }
        .onChange(of: coordinator.pauseOnBattery) { _, _ in
            saveRuntimeSettings()
        }
        .onChange(of: coordinator.pauseOnFullscreen) { _, _ in
            saveRuntimeSettings()
        }
        .onChange(of: coordinator.muteOnFullscreen) { _, _ in
            saveRuntimeSettings()
        }
    }

    private func selectGalleryItem(_ item: WallpaperGalleryItem) {
        selectedGalleryItemID = item.id
        coordinator.selectGalleryItem(id: item.id)
        coordinator.refreshDisplays()
        coordinator.selectedDisplayIDs = Set(coordinator.displays.map(\.id))
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

    private func displayRuntimeBinding(for id: DisplayID) -> Binding<Bool> {
        Binding {
            coordinator.isDisplayEnabled(id)
        } set: { isEnabled in
            Task {
                await coordinator.setDisplayEnabled(displayID: id, isEnabled: isEnabled)
            }
        }
    }

    private func displayRuntimeDescription(for display: DisplayState) -> String {
        if let activeContentName = coordinator.activeContentName(for: display.id) {
            return "\(display.frameDescription) - Active: \(activeContentName)"
        }

        if let savedContentName = coordinator.savedContentName(for: display.id) {
            return "\(display.frameDescription) - Saved: \(savedContentName)"
        }

        return "\(display.frameDescription) - No wallpaper"
    }

    private func audioDisplaySystemImage(for id: DisplayID) -> String {
        guard !coordinator.muted else {
            return "speaker.slash.fill"
        }
        return coordinator.audioDisplayID == id ? "speaker.wave.2.fill" : "speaker"
    }

    private func saveRuntimeSettings() {
        Task {
            await coordinator.updateRuntimePreferences()
        }
    }
}

private enum AddWallpaperMode: String, CaseIterable, Identifiable {
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

private struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
}

private struct AddWallpaperSheet: View {
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

private struct WallpaperDetailSheet: View {
    @Bindable var coordinator: WallpaperCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var presentedAlert: WallpaperDetailAlert?
    @State private var isDeleteHovered = false
    let item: WallpaperGalleryItem

    var body: some View {
        ZStack {
            WallpaperDetailBackground(item: item)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.title2.weight(.bold))
                            .lineLimit(2)
                        Text(detailDescription)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(2)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .focusable(false)
                    .help("Close")
                }
                .padding(.top, 28)
                .padding(.horizontal, 26)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Displays")
                        .font(.headline)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(coordinator.displays) { display in
                                Toggle(isOn: displayBinding(for: display.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(display.name)
                                            .font(.callout.weight(.medium))
                                        Text(display.frameDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .frame(height: 132, alignment: .topLeading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.18))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await coordinator.applySelectedContent()
                            if coordinator.lastError == nil {
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Apply This Wallpaper")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(coordinator.selectedDisplayIDs.isEmpty)
                    .opacity(coordinator.selectedDisplayIDs.isEmpty ? 0.55 : 1)
                    .focusable(false)

                    Button(role: .destructive) {
                        presentedAlert = .deleteConfirmation
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isDeleteHovered ? .white : .red)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.borderless)
                    .background {
                        Circle()
                            .fill(isDeleteHovered ? Color.red.opacity(0.86) : Color.white.opacity(0.08))
                            .background(.regularMaterial, in: Circle())
                    }
                    .overlay {
                        Circle()
                            .stroke(isDeleteHovered ? Color.red.opacity(0.92) : Color.white.opacity(0.16))
                    }
                    .contentShape(Circle())
                    .onHover { isDeleteHovered = $0 }
                    .focusable(false)
                    .help("Delete wallpaper")
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 420, height: 640)
        .onChange(of: coordinator.lastError) { _, error in
            guard let error else {
                return
            }
            presentedAlert = .error(error)
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .error(let message):
                Alert(
                    title: Text("LivePaper"),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) {
                        coordinator.clearLastError()
                    }
                )
            case .deleteConfirmation:
                Alert(
                    title: Text("Delete Wallpaper?"),
                    message: Text("This removes the wallpaper from the library and clears any saved display assignments for it."),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            await coordinator.deleteGalleryItem(id: item.id)
                            dismiss()
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var detailDescription: String {
        if item.savedDisplayCount > 0 {
            return "\(item.subtitle) - \(item.savedDisplayCount) saved"
        }
        return item.subtitle
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

private enum WallpaperDetailAlert: Identifiable {
    case error(String)
    case deleteConfirmation

    var id: String {
        switch self {
        case .error(let message):
            return "error-\(message)"
        case .deleteConfirmation:
            return "delete-confirmation"
        }
    }
}

private struct WallpaperDetailBackground: View {
    let item: WallpaperGalleryItem

    var body: some View {
        ZStack {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackBackground
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.72),
                    .black.opacity(0.34),
                    .black.opacity(0.08),
                    .black.opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(width: 420, height: 640)
    }

    private var fallbackBackground: some View {
        ZStack {
            LinearGradient(
                colors: item.kind == .video
                    ? [Color.blue.opacity(0.34), Color.black, Color.indigo.opacity(0.28)]
                    : [Color.green.opacity(0.32), Color.black, Color.teal.opacity(0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: item.kind == .video ? "film.fill" : "globe")
                .font(.system(size: 74, weight: .medium))
                .foregroundStyle(.white.opacity(0.22))
        }
    }

    private var previewImage: NSImage? {
        guard let previewImageURL = item.previewImageURL, previewImageURL.isFileURL else {
            return nil
        }
        return NSImage(contentsOf: previewImageURL)
    }
}

private enum WallpaperCardMetrics {
    static let width: CGFloat = 260
    static let previewWidth: CGFloat = width
    static let previewHeight: CGFloat = width * 9 / 16
    static let height: CGFloat = previewHeight
}

private enum DisplayCardMetrics {
    static let width: CGFloat = 260
    static let height: CGFloat = 154
}

private enum LivePaperBottomTabMetrics {
    static let bottomPadding: CGFloat = 16
    static let scrollContentTailPadding: CGFloat = 84
}

private struct DisplayCard: View {
    let display: DisplayState
    let wallpaperItem: WallpaperGalleryItem?
    let description: String
    @Binding var isEnabled: Bool
    let isAudioDisplay: Bool
    let audioSystemImage: String
    let audioAction: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            DisplayWallpaperPreview(item: wallpaperItem)

            LinearGradient(
                colors: [
                    .black.opacity(0.72),
                    .black.opacity(0.16),
                    .black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.top, 13)
                .padding(.horizontal, 14)

                Spacer(minLength: 0)

                HStack(alignment: .center) {
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .focusable(false)
                        .help(isEnabled ? "Stop this display" : "Start this display")

                    Spacer()

                    Button(action: audioAction) {
                        Image(systemName: audioSystemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isAudioDisplay ? .white : .white.opacity(0.62))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(isAudioDisplay ? Color.accentColor : Color.black.opacity(0.34))
                            )
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(isAudioDisplay ? 0.24 : 0.16))
                            }
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Use this display for wallpaper audio")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .frame(width: DisplayCardMetrics.width, height: DisplayCardMetrics.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isEnabled ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.14), lineWidth: isEnabled ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
    }
}

private struct DisplayWallpaperPreview: View {
    let item: WallpaperGalleryItem?

    var body: some View {
        ZStack {
            if let item {
                WallpaperPreview(item: item, iconSize: 38)
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.black.opacity(0.68),
                        Color.blue.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "display")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
        .frame(width: DisplayCardMetrics.width, height: DisplayCardMetrics.height)
    }
}

private struct WallpaperCard: View {
    let item: WallpaperGalleryItem
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WallpaperPreview(item: item, iconSize: 34)
                .frame(width: WallpaperCardMetrics.previewWidth, height: WallpaperCardMetrics.previewHeight)

            LinearGradient(
                colors: [
                    .black.opacity(0),
                    .black.opacity(0.36),
                    .black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 82)
            .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(cardDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: WallpaperCardMetrics.width, height: WallpaperCardMetrics.height, alignment: .topLeading)
        .background(isSelected ? Color.accentColor.opacity(0.045) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
        }
    }

    private var cardDescription: String {
        guard item.savedDisplayCount > 0 else {
            return item.subtitle
        }
        return "\(item.subtitle) · \(item.savedDisplayCount) saved"
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
                    .frame(width: WallpaperCardMetrics.previewWidth, height: WallpaperCardMetrics.previewHeight)
                    .clipped()
            } else {
                Image(systemName: item.kind == .video ? "film.fill" : "globe")
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(item.kind == .video ? .blue : .green)
            }
        }
        .frame(width: WallpaperCardMetrics.previewWidth, height: WallpaperCardMetrics.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .clipped()
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
            return "Wallpapers"
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

private struct LivePaperBottomTabBar: View {
    @Binding var selectedTab: LivePaperNavigationTab

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ForEach(LivePaperNavigationTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.62))
                            .frame(width: 122, height: 36)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 122, height: 36)
                    .contentShape(Capsule())
                    .focusable(false)
                    .help(tab.title)
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.12))
            }

            Spacer(minLength: 0)
        }
    }
}

private struct LivePaperGlassBackground: View {
    var body: some View {
        Color.black
        .ignoresSafeArea()
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
