import SwiftUI

struct SettingsTab: View {
    @Bindable var coordinator: WallpaperCoordinator

    var body: some View {
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

                        GlassDivider()

                        GlassSettingsRow(
                            icon: "display.2",
                            iconColor: .cyan,
                            title: "Sync Matching Videos",
                            subtitle: "Keep identical video wallpapers aligned across displays."
                        ) {
                            Toggle("", isOn: $coordinator.synchronizeMatchingWallpapers)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }

                GlassSection(title: "Music Sync") {
                    VStack(spacing: 0) {
                        GlassSettingsRow(
                            icon: "music.note",
                            iconColor: .pink,
                            title: "Album Artwork Sync",
                            subtitle: "Temporarily replace the desktop wallpaper with the current album art."
                        ) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { coordinator.isMusicSyncEnabled },
                                    set: { isEnabled in
                                        Task {
                                            await coordinator.setMusicSyncEnabled(isEnabled)
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

                        GlassDivider()

                        GlassSettingsRow(
                            icon: "music.mic",
                            iconColor: .green,
                            title: "Music App",
                            subtitle: "Read the current track from a local macOS music app."
                        ) {
                            Picker(
                                "Music App",
                                selection: Binding(
                                    get: { coordinator.musicSyncSource },
                                    set: { source in
                                        Task {
                                            await coordinator.setMusicSyncSource(source)
                                        }
                                    }
                                )
                            ) {
                                ForEach(WallpaperContent.MusicSource.allCases) { source in
                                    Text(source.title).tag(source)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                            .frame(width: 230, alignment: .trailing)
                        }

                        GlassDivider()

                        GlassSettingsRow(
                            icon: "sparkles",
                            iconColor: .purple,
                            title: "Visual Style",
                            subtitle: "Choose how album artwork becomes the desktop background."
                        ) {
                            Picker(
                                "Visual Style",
                                selection: Binding(
                                    get: { coordinator.musicWallpaperStyle },
                                    set: { style in
                                        Task {
                                            await coordinator.setMusicWallpaperStyle(style)
                                        }
                                    }
                                )
                            ) {
                                ForEach(MusicWallpaperStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize()
                            .frame(width: 230, alignment: .trailing)
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

                GlassSection(title: "Lock Screen") {
                    VStack(spacing: 0) {
                        GlassSettingsRow(
                            icon: "lock.fill",
                            iconColor: .indigo,
                            title: "Apply with Wallpaper",
                            subtitle: "Export supported video wallpapers to the macOS Lock Screen when applied."
                        ) {
                            Toggle("", isOn: $coordinator.applyLockScreenAutomatically)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        GlassDivider()

                        GlassSettingsRow(
                            icon: "rectangle.on.rectangle",
                            iconColor: .cyan,
                            title: "Screen Saver",
                            subtitle: "Install the video-only LivePaper screen saver bundle."
                        ) {
                            HStack(spacing: 8) {
                                Button("Install") {
                                    coordinator.installScreenSaver()
                                }
                                .buttonStyle(GlassSecondaryButtonStyle())
                                .focusable(false)

                                Button("Open Settings") {
                                    coordinator.openScreenSaverSettings()
                                }
                                .buttonStyle(GlassSecondaryButtonStyle())
                                .focusable(false)
                            }
                        }
                    }
                }

                GlassSection(title: "Startup") {
                    GlassSettingsRow(
                        icon: "power",
                        iconColor: .mint,
                        title: "Launch at Login",
                        subtitle: loginItemSubtitle
                    ) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { coordinator.loginItemStatus.isRegistered },
                                set: { coordinator.setLaunchAtLoginEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
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
            .padding(.bottom, LivePaperBottomTabMetrics.scrollContentTailPadding)
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
        .onChange(of: coordinator.applyLockScreenAutomatically) { _, _ in
            saveRuntimeSettings()
        }
        .onChange(of: coordinator.synchronizeMatchingWallpapers) { _, _ in
            saveRuntimeSettings()
        }
        .onAppear {
            coordinator.refreshLoginItemStatus()
        }
    }

    private var loginItemSubtitle: String {
        let status = coordinator.loginItemStatus
        if status.requiresApproval {
            return "Allow LivePaper in System Settings to finish enabling login startup."
        }
        if status.isRegistered {
            return "Open LivePaper automatically at user login."
        }
        return "Register LivePaper with macOS Login Items."
    }

    private func saveRuntimeSettings() {
        Task {
            await coordinator.updateRuntimePreferences()
        }
    }
}
