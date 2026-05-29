import AppKit
import Foundation

@MainActor
final class RuntimePolicyController {
    private var notificationObservers: [NSObjectProtocol] = []
    private var delayedPolicyRefreshTask: Task<Void, Never>?

    private(set) var globalPauseReasons: Set<RuntimePauseReason> = []
    private(set) var fullscreenDisplayIDs: Set<DisplayID> = []

    func observeSystemPolicyChanges(
        refreshPolicy: @escaping @MainActor () async -> Void,
        setGlobalPauseReason: @escaping @MainActor (RuntimePauseReason, Bool) async -> Void,
        scheduleDelayedRefresh: @escaping @MainActor () -> Void
    ) {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        notificationObservers = [
            workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in await setGlobalPauseReason(.systemSleep, true) }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    await setGlobalPauseReason(.systemSleep, false)
                    await refreshPolicy()
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in await setGlobalPauseReason(.screenSleep, true) }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    await setGlobalPauseReason(.screenSleep, false)
                    await refreshPolicy()
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in await setGlobalPauseReason(.locked, true) }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    await setGlobalPauseReason(.locked, false)
                    await refreshPolicy()
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    await refreshPolicy()
                    scheduleDelayedRefresh()
                }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    await refreshPolicy()
                    scheduleDelayedRefresh()
                }
            }
        ]
    }

    func shutdown() {
        notificationObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        notificationObservers.removeAll()
        delayedPolicyRefreshTask?.cancel()
        delayedPolicyRefreshTask = nil
    }

    func setGlobalPauseReason(_ reason: RuntimePauseReason, isActive: Bool) {
        if isActive {
            globalPauseReasons.insert(reason)
        } else {
            globalPauseReasons.remove(reason)
        }
    }

    func refreshDetectedPolicyState() {
        fullscreenDisplayIDs = FullscreenWindowDetector.coveredDisplayIDs()

        if SystemPowerState.isOnBatteryPower {
            globalPauseReasons.insert(.battery)
        } else {
            globalPauseReasons.remove(.battery)
        }
    }

    func scheduleDelayedRefresh(_ refresh: @escaping @MainActor () async -> Void) {
        delayedPolicyRefreshTask?.cancel()
        delayedPolicyRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }

            await refresh()
        }
    }

    func pauseReasons(for displayID: DisplayID, config: WallpaperConfig) -> Set<RuntimePauseReason> {
        var reasons = globalPauseReasons

        if globalPauseReasons.contains(.battery), !config.pauseOnBattery {
            reasons.remove(.battery)
        }

        if fullscreenDisplayIDs.contains(displayID), config.pauseOnFullscreen {
            reasons.insert(.fullscreen)
        }

        return reasons
    }
}
