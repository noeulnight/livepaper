//
//  LivePaperApp.swift
//  LivePaper
//
//  Created by Limtaehyun on 5/29/26.
//

import SwiftUI
import AppKit

@main
struct LivePaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LivePaper", systemImage: "play.rectangle.on.rectangle") {
            MenuBarControls(coordinator: appDelegate.coordinator)
        }
        .menuBarExtraStyle(.window)

        Window("LivePaper", id: "main") {
            ContentView(coordinator: appDelegate.coordinator)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appTermination) {
                Button("Stop Wallpapers") {
                    Task {
                        await appDelegate.coordinator.stopAll()
                    }
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = WallpaperCoordinator()
    private var didRestoreSavedWallpapers = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        restoreSavedWallpapersOnLaunch()
    }

    private func restoreSavedWallpapersOnLaunch() {
        guard !didRestoreSavedWallpapers, coordinator.hasSavedWallpapers else {
            return
        }

        didRestoreSavedWallpapers = true
        Task {
            await coordinator.restoreSavedWallpapers()
        }
    }
}

private struct MenuBarControls: View {
    private let panelWidth: CGFloat = 340
    private let panelHeight: CGFloat = 560
    private let contentWidth: CGFloat = 308

    @Bindable var coordinator: WallpaperCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDisplayID: DisplayID?

    var body: some View {
        ZStack {
            MenuBarWallpaperBackground(item: selectedWallpaperItem)

            LinearGradient(
                colors: [
                    .black.opacity(0.42),
                    .black.opacity(0.08),
                    .black.opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                topBar

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    displaySelectionStrip
                    controlsCard
                }
            }
            .frame(width: contentWidth, height: panelHeight - 32)
        }
        .frame(width: panelWidth, height: panelHeight)
        .clipShape(ContainerRelativeShape())
        .overlay {
            ContainerRelativeShape()
                .stroke(.white.opacity(0.26))
        }
        .onAppear(perform: syncSelectedDisplayFromMenuLocation)
        .onChange(of: coordinator.displays) { _, _ in
            ensureSelectedDisplayExists()
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedContentName)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 2)

                Text(selectedWallpaperSubtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            MenuBarCircleButton(systemImage: "gearshape") {
                openSettings()
            }
        }
    }

    private var displaySelectionStrip: some View {
        VStack(spacing: 6) {
            ForEach(coordinator.displays) { display in
                Button {
                    selectedDisplayID = display.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "display")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 15)

                        Text(display.name)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 0)

                        if selectedDisplayID == display.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(selectedDisplayID == display.id ? .black.opacity(0.82) : .white)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(displayRowBackground(isSelected: selectedDisplayID == display.id))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered {
                        DisplayHighlighter.shared.highlight(displayID: display.id, duration: nil)
                    } else {
                        DisplayHighlighter.shared.hide(displayID: display.id)
                    }
                }
            }
        }
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                MenuBarToggleRow(title: "Pause on Battery", systemImage: "battery.50", isOn: $coordinator.pauseOnBattery)
                MenuBarToggleRow(title: "Mute", systemImage: "speaker.slash", isOn: $coordinator.muted)
                MenuBarVolumeRow(volume: $coordinator.volume, isMuted: coordinator.muted)
            }
            .onChange(of: coordinator.pauseOnBattery) { _, _ in
                saveRuntimeSettings()
            }
            .onChange(of: coordinator.muted) { _, _ in
                saveRuntimeSettings()
            }
            .onChange(of: coordinator.volume) { _, _ in
                saveRuntimeSettings()
            }

            HStack(spacing: 12) {
                Button("Restore") {
                    Task {
                        await restoreSelectedDisplay()
                    }
                }
                .buttonStyle(MenuBarMaterialButtonStyle())
                .disabled(selectedDisplayID == nil)
                .opacity(selectedDisplayID == nil ? 0.55 : 1)

                Button("Stop") {
                    Task {
                        await stopSelectedDisplay()
                    }
                }
                .buttonStyle(MenuBarMaterialButtonStyle(tint: .red, isProminent: true))
                .disabled(selectedDisplayID == nil || !isSelectedDisplayActive)
                .opacity(selectedDisplayID == nil || !isSelectedDisplayActive ? 0.55 : 1)
            }
        }
        .padding(18)
        .frame(width: contentWidth, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.18))
        }
    }

    private func displayRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? .white.opacity(0.86) : .black.opacity(0.38))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(isSelected ? 0.28 : 0.14))
            }
    }

    private var selectedDisplay: DisplayState? {
        guard let selectedDisplayID else {
            return coordinator.displays.first
        }
        return coordinator.displays.first { $0.id == selectedDisplayID } ?? coordinator.displays.first
    }

    private var selectedWallpaperItem: WallpaperGalleryItem? {
        guard let selectedDisplay else {
            return nil
        }
        return coordinator.displayWallpaperItem(for: selectedDisplay.id)
    }

    private var selectedContentName: String {
        selectedWallpaperItem?.title ?? "No Wallpaper"
    }

    private var selectedWallpaperSubtitle: String {
        guard let selectedWallpaperItem else {
            return selectedDisplay?.name ?? "Choose a wallpaper"
        }
        return selectedWallpaperItem.subtitle
    }

    private var isSelectedDisplayActive: Bool {
        guard let selectedDisplayID else {
            return false
        }
        return coordinator.isDisplayEnabled(selectedDisplayID)
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .livePaperSelectSettingsTab, object: nil)
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
        dismiss()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .livePaperSelectSettingsTab, object: nil)
            bringMainWindowForward(orderRegardless: false)

            DispatchQueue.main.async {
                bringMainWindowForward(orderRegardless: true)
            }
        }
    }

    private func bringMainWindowForward(orderRegardless: Bool) {
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "LivePaper" }) else {
            return
        }

        if orderRegardless {
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func saveRuntimeSettings() {
        Task {
            await coordinator.updateRuntimePreferences()
        }
    }

    private func syncSelectedDisplayFromMenuLocation() {
        coordinator.refreshDisplays()

        let mouseLocation = NSEvent.mouseLocation
        let clickedDisplayID = NSScreen.screens
            .first { NSMouseInRect(mouseLocation, $0.frame, false) }?
            .livePaperDisplayID

        if let clickedDisplayID, coordinator.displays.contains(where: { $0.id == clickedDisplayID }) {
            selectedDisplayID = clickedDisplayID
        } else {
            ensureSelectedDisplayExists()
        }
    }

    private func ensureSelectedDisplayExists() {
        if let selectedDisplayID, coordinator.displays.contains(where: { $0.id == selectedDisplayID }) {
            return
        }
        selectedDisplayID = NSScreen.main?.livePaperDisplayID ?? coordinator.displays.first?.id
    }

    private func restoreSelectedDisplay() async {
        guard let selectedDisplayID else {
            return
        }
        await coordinator.setDisplayEnabled(displayID: selectedDisplayID, isEnabled: true)
    }

    private func stopSelectedDisplay() async {
        guard let selectedDisplayID else {
            return
        }
        await coordinator.stopDisplay(displayID: selectedDisplayID)
    }
}

extension Notification.Name {
    static let livePaperSelectSettingsTab = Notification.Name("LivePaperSelectSettingsTab")
}

private struct MenuBarWallpaperBackground: View {
    let item: WallpaperGalleryItem?

    var body: some View {
        ZStack {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .saturation(0.94)
                    .overlay(.black.opacity(0.16))
            } else if let item {
                LinearGradient(
                    colors: [
                        Color(red: 0.83, green: 0.43, blue: 0.49),
                        Color(red: 0.55, green: 0.2, blue: 0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: item.kind == .video ? "film.fill" : "globe")
                    .font(.system(size: 92, weight: .medium))
                    .foregroundStyle(.white.opacity(0.16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .clipped()
    }

    private var previewImage: NSImage? {
        guard let previewImageURL = item?.previewImageURL, previewImageURL.isFileURL else {
            return nil
        }
        return NSImage(contentsOf: previewImageURL)
    }
}

private struct MenuBarCircleButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 27, height: 27)
                .background(.black.opacity(0.36), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.14))
                }
        }
        .buttonStyle(.plain)
    }
}

private struct MenuBarToggleRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.64))
                .frame(width: 15)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer()

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(height: 25)
    }
}

private struct MenuBarVolumeRow: View {
    @Binding var volume: Double
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isMuted ? 0.36 : 0.64))
                .frame(width: 15)

            Text("Volume")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isMuted ? 0.48 : 1))
                .lineLimit(1)

            Slider(value: $volume, in: 0...1)
                .controlSize(.small)
                .disabled(isMuted)

            Text(volume, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(isMuted ? 0.42 : 0.68))
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 25)
    }
}

private struct MenuBarMaterialButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(buttonBackground(isPressed: configuration.isPressed))
    }

    private func buttonBackground(isPressed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isProminent ? tint.opacity(isPressed ? 0.82 : 1) : .white.opacity(isPressed ? 0.16 : 0.08))
    }
}
