import SwiftUI

enum LivePaperNavigationTab: String, CaseIterable, Identifiable {
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

struct LivePaperBottomTabBar: View {
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
