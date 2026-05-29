//
//  ContentView.swift
//  LivePaper
//
//  Created by Limtaehyun on 5/29/26.
//

import AppKit
import SwiftUI

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
        .onReceive(NotificationCenter.default.publisher(for: .livePaperSelectSettingsTab)) { _ in
            selectedNavigationTab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .livePaperOpenAddWallpaper)) { _ in
            selectedNavigationTab = .wallpaper
            isAddWallpaperPresented = true
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
            WallpaperLibraryTab(
                coordinator: coordinator,
                selectedGalleryItemID: $selectedGalleryItemID,
                isWallpaperDetailPresented: $isWallpaperDetailPresented,
                isAddWallpaperPresented: $isAddWallpaperPresented
            )
        case .displays:
            DisplaysTab(coordinator: coordinator)
        case .settings:
            SettingsTab(coordinator: coordinator)
        }
    }

    private var selectedGalleryItem: WallpaperGalleryItem? {
        let id = selectedGalleryItemID ?? coordinator.selectedGalleryItemID
        return coordinator.galleryItems.first { $0.id == id }
    }
}

#if DEBUG
#Preview {
    ContentView(coordinator: WallpaperCoordinator())
}
#endif
