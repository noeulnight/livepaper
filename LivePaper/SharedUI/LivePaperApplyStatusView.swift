import SwiftUI

struct LivePaperApplyStatusView: View {
    let status: WallpaperApplyStatus

    var body: some View {
        HStack(spacing: 4) {
            StatusPill(
                title: "Desktop",
                systemImage: "display",
                contentName: status.contentName,
                displayCount: status.displayCount,
                status: status.desktop
            )
            StatusPill(
                title: "Lock Screen",
                systemImage: "lock.display",
                contentName: status.contentName,
                displayCount: status.displayCount,
                status: status.lockScreen
            )
            StatusPill(
                title: "Screen Saver",
                systemImage: "rectangle.on.rectangle",
                contentName: status.contentName,
                displayCount: status.displayCount,
                status: status.screenSaver
            )
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
        .help(helpText)
    }

    private var helpText: String {
        guard status.displayCount > 0 else {
            return status.contentName
        }

        let displayText = status.displayCount == 1 ? "1 display" : "\(status.displayCount) displays"
        return "\(status.contentName) - \(displayText)"
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let contentName: String
    let displayCount: Int
    let status: WallpaperApplySurfaceStatus
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 18, height: 18)

            if status.state == .applying {
                Circle()
                    .trim(from: 0.08, to: 0.72)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                    )
                    .frame(width: 31, height: 31)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        .linear(duration: 0.85).repeatForever(autoreverses: false),
                        value: isSpinning
                    )
                    .accessibilityLabel("\(title) in progress")
            }
        }
        .frame(width: 36, height: 36)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .stroke(borderColor, lineWidth: status.state == .applying ? 1.4 : 1)
        }
        .help(helpText)
        .onAppear {
            isSpinning = status.state == .applying
        }
        .onChange(of: status.state) { _, state in
            isSpinning = state == .applying
        }
    }

    private var backgroundColor: Color {
        status.state == .applying ? .white.opacity(0.14) : statusColor.opacity(0.16)
    }

    private var borderColor: Color {
        status.state == .applying ? Color.accentColor.opacity(0.54) : statusColor.opacity(0.28)
    }

    private var iconColor: Color {
        status.state == .applying ? .white.opacity(0.88) : statusColor
    }

    private var iconName: String {
        switch status.state {
        case .idle:
            return systemImage
        case .applying:
            return systemImage
        case .applied:
            return "checkmark"
        case .skipped:
            return "minus"
        case .failed:
            return "exclamationmark"
        }
    }

    private var statusColor: Color {
        switch status.state {
        case .idle:
            return .white.opacity(0.46)
        case .applying:
            return .accentColor
        case .applied:
            return .green
        case .skipped:
            return .orange
        case .failed:
            return .red
        }
    }

    private var helpText: String {
        let displayText: String
        if displayCount <= 0 {
            displayText = "No display"
        } else if displayCount == 1 {
            displayText = "1 display"
        } else {
            displayText = "\(displayCount) displays"
        }

        return "\(title): \(status.detail) - \(contentName) - \(displayText)"
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LivePaperApplyStatusView(
            status: WallpaperApplyStatus(
                contentName: "Sample Wallpaper.mov",
                displayCount: 2,
                desktop: .init(state: .applied, detail: "Applied"),
                lockScreen: .init(state: .applying, detail: "Exporting"),
                screenSaver: .init(state: .skipped, detail: "Video only")
            )
        )
        .padding()
    }
}
#endif
