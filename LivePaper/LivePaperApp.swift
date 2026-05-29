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
    @State private var coordinator = WallpaperCoordinator()

    var body: some Scene {
        MenuBarExtra("LivePaper", systemImage: "play.rectangle.on.rectangle") {
            MenuBarControls(coordinator: coordinator)
        }

        Window("LivePaper", id: "main") {
            ContentView(coordinator: coordinator)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appTermination) {
                Button("Stop Wallpapers") {
                    Task {
                        await coordinator.stopAll()
                    }
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

private struct MenuBarControls: View {
    @Bindable var coordinator: WallpaperCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open LivePaper") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Restore Saved Wallpapers") {
            Task {
                await coordinator.restoreSavedWallpapers()
            }
        }
        .disabled(!coordinator.hasSavedWallpapers)

        Button("Stop Wallpapers") {
            Task {
                await coordinator.stopAll()
            }
        }

        Divider()

        Button("Quit LivePaper") {
            Task {
                await coordinator.shutdown()
                NSApplication.shared.terminate(nil)
            }
        }
        .keyboardShortcut("q")
    }
}
