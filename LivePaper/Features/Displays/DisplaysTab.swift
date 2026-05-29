import SwiftUI

struct DisplaysTab: View {
    @Bindable var coordinator: WallpaperCoordinator

    var body: some View {
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
                .focusEffectDisabled()
            }

            displayList

            Spacer(minLength: 0)
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
                        isAudioDisplay: isAudibleDisplay(display.id),
                        audioSystemImage: audioDisplaySystemImage(for: display.id),
                        audioHelpText: audioDisplayHelpText(for: display.id)
                    ) {
                        DisplayHighlighter.shared.highlight(displayID: display.id, duration: nil)
                    } audioAction: {
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

    private func isAudibleDisplay(_ id: DisplayID) -> Bool {
        !coordinator.muted && coordinator.audioDisplayID == id
    }

    private func audioDisplayHelpText(for id: DisplayID) -> String {
        if coordinator.muted {
            return "Wallpaper audio is muted in Settings"
        }
        if coordinator.audioDisplayID == id {
            return "This display is used for wallpaper audio"
        }
        return "Use this display for wallpaper audio"
    }
}
