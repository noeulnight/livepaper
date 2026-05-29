import AppKit
import SwiftUI

struct FirstLaunchIntroView: View {
    let onLaunchAtLoginChanged: (Bool) -> Void
    let onAddWallpaper: () -> Void
    let onSkip: () -> Void

    @State private var step: IntroStep = .overview
    @State private var launchAtLoginEnabled: Bool
    @State private var appliedLaunchAtLoginEnabled: Bool

    init(
        launchAtLoginEnabled: Bool,
        onLaunchAtLoginChanged: @escaping (Bool) -> Void,
        onAddWallpaper: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.onLaunchAtLoginChanged = onLaunchAtLoginChanged
        self.onAddWallpaper = onAddWallpaper
        self.onSkip = onSkip
        _launchAtLoginEnabled = State(initialValue: launchAtLoginEnabled)
        _appliedLaunchAtLoginEnabled = State(initialValue: launchAtLoginEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 8) {
                ForEach(IntroStep.allCases) { item in
                    Capsule()
                        .fill(item == step ? Color.accentColor : Color.white.opacity(0.18))
                        .frame(width: item == step ? 26 : 8, height: 8)
                }

                Spacer(minLength: 0)

                Button(action: onSkip) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .focusable(false)
                .help("Skip intro")
            }

            VStack(alignment: .leading, spacing: 12) {
                stepIcon

                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(step.subtitle)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(step.rows) { row in
                    IntroStepRow(
                        systemImage: row.systemImage,
                        title: row.title,
                        subtitle: row.subtitle
                    )
                }

                if step == .launchAtLogin {
                    IntroLaunchAtLoginChoice(isOn: $launchAtLoginEnabled)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                if step != .overview {
                    Button {
                        step = step.previous
                    } label: {
                        Text("Back")
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .focusable(false)
                }

                Spacer(minLength: 0)

                Button(action: primaryAction) {
                    Label(step.primaryTitle, systemImage: step.primarySystemImage)
                }
                .buttonStyle(GlassProminentButtonStyle())
                .focusable(false)
            }
        }
        .padding(28)
        .frame(width: 420, height: 640, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.16))
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 18)
    }

    private func primaryAction() {
        switch step {
        case .overview:
            step = .launchAtLogin
        case .launchAtLogin:
            if launchAtLoginEnabled != appliedLaunchAtLoginEnabled {
                onLaunchAtLoginChanged(launchAtLoginEnabled)
                appliedLaunchAtLoginEnabled = launchAtLoginEnabled
            }
            step = .addWallpaper
        case .addWallpaper:
            onAddWallpaper()
        }
    }

    @ViewBuilder
    private var stepIcon: some View {
        Group {
            if step == .overview {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 76, height: 76)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(step.iconColor.gradient)

                    Image(systemName: step.systemImage)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 68, height: 68)
            }
        }
        .frame(width: 76, height: 76, alignment: .leading)
    }
}

private enum IntroStep: Int, CaseIterable, Identifiable {
    case overview
    case launchAtLogin
    case addWallpaper

    var id: Self { self }

    var previous: IntroStep {
        IntroStep(rawValue: max(rawValue - 1, 0)) ?? .overview
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "play.rectangle.on.rectangle"
        case .launchAtLogin:
            return "power"
        case .addWallpaper:
            return "plus.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .overview:
            return .blue
        case .launchAtLogin:
            return .mint
        case .addWallpaper:
            return .purple
        }
    }

    var title: String {
        switch self {
        case .overview:
            return "Live wallpapers for your desktop"
        case .launchAtLogin:
            return "Start LivePaper at login"
        case .addWallpaper:
            return "Add your first wallpaper"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return "LivePaper keeps animated wallpapers local, quiet, and easy to control from the menu bar."
        case .launchAtLogin:
            return "Choose whether LivePaper should open automatically when you sign in to this Mac."
        case .addWallpaper:
            return "Choose a local video, web page, or Steam Workshop item to begin."
        }
    }

    var rows: [IntroStepRowModel] {
        switch self {
        case .overview:
            return [
                IntroStepRowModel(systemImage: "display", title: "Desktop-level playback", subtitle: "Wallpapers sit behind your normal windows."),
                IntroStepRowModel(systemImage: "lock.shield", title: "Local first", subtitle: "No account, cloud library, or tracking requirement."),
                IntroStepRowModel(systemImage: "menubar.rectangle", title: "Menu bar control", subtitle: "Pause, restore, mute, or stop without opening settings.")
            ]
        case .launchAtLogin:
            return [
                IntroStepRowModel(systemImage: "arrow.clockwise", title: "Restore quickly", subtitle: "Saved wallpapers can come back after login."),
                IntroStepRowModel(systemImage: "gearshape", title: "Change later", subtitle: "You can update this anytime in Settings.")
            ]
        case .addWallpaper:
            return [
                IntroStepRowModel(systemImage: "film", title: "Local video", subtitle: "Add .mp4, .mov, .m4v, or .mkv files."),
                IntroStepRowModel(systemImage: "link", title: "Web wallpaper", subtitle: "Use a web page or supported YouTube link."),
                IntroStepRowModel(systemImage: "display.2", title: "Apply to displays", subtitle: "Pick one or more screens in the next flow.")
            ]
        }
    }

    var primaryTitle: String {
        switch self {
        case .overview:
            return "Continue"
        case .launchAtLogin:
            return "Continue"
        case .addWallpaper:
            return "Add Wallpaper"
        }
    }

    var primarySystemImage: String {
        switch self {
        case .overview:
            return "arrow.right"
        case .launchAtLogin:
            return "arrow.right"
        case .addWallpaper:
            return "plus.circle.fill"
        }
    }
}

private struct IntroStepRowModel: Identifiable {
    let systemImage: String
    let title: String
    let subtitle: String

    var id: String { title }
}

private struct IntroLaunchAtLoginChoice: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Launch at Login")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.94))

                Text(isOn ? "LivePaper will open when you sign in." : "LivePaper will only open when you start it.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .focusable(false)
        }
        .padding(14)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isOn ? Color.accentColor.opacity(0.65) : .white.opacity(0.14))
        }
    }
}

private struct IntroStepRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
#Preview {
    FirstLaunchIntroView(
        launchAtLoginEnabled: false,
        onLaunchAtLoginChanged: { _ in },
        onAddWallpaper: {},
        onSkip: {}
    )
    .preferredColorScheme(.dark)
}
#endif
