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
    }

    private func saveRuntimeSettings() {
        Task {
            await coordinator.updateRuntimePreferences()
        }
    }
}
