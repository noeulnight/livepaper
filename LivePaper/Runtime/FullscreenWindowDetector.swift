import AppKit

enum FullscreenWindowDetector {
    static func coveredDisplayIDs() -> Set<DisplayID> {
        guard let windowInfos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let displays = displayInfos()
        guard !displays.isEmpty else {
            return []
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        var coveredDisplayIDs: Set<DisplayID> = []

        for windowInfo in windowInfos {
            guard
                isCandidateFullscreenWindow(windowInfo, currentProcessID: currentProcessID),
                let windowBounds = windowBounds(from: windowInfo)
            else {
                continue
            }

            for display in displays where covers(windowBounds: windowBounds, display: display) {
                coveredDisplayIDs.insert(display.id)
            }
        }

        return coveredDisplayIDs
    }

    private struct DisplayInfo {
        let id: DisplayID
        let bounds: CGRect
        let visibleFrame: CGRect
    }

    private static func displayInfos() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let id = screen.livePaperDisplayID
            else {
                return nil
            }

            let displayID = CGDirectDisplayID(number.uint32Value)
            return DisplayInfo(
                id: id,
                bounds: CGDisplayBounds(displayID),
                visibleFrame: screen.visibleFrame
            )
        }
    }

    private static func isCandidateFullscreenWindow(
        _ windowInfo: [String: Any],
        currentProcessID: Int32
    ) -> Bool {
        let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue
        let ownerProcessID = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1

        return layer == 0 && ownerProcessID != currentProcessID && alpha > 0
    }

    private static func windowBounds(from windowInfo: [String: Any]) -> CGRect? {
        guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }

        return CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
    }

    private static func covers(windowBounds: CGRect, display: DisplayInfo) -> Bool {
        covers(windowBounds: windowBounds, displayBounds: display.bounds, visibleFrame: display.visibleFrame)
    }

    static func covers(windowBounds: CGRect, displayBounds: CGRect, visibleFrame: CGRect) -> Bool {
        covers(windowBounds: windowBounds, targetBounds: displayBounds, coverageThreshold: 0.98)
            || covers(windowBounds: windowBounds, targetBounds: visibleFrame, coverageThreshold: 0.95)
    }

    private static func covers(
        windowBounds: CGRect,
        targetBounds: CGRect,
        coverageThreshold: CGFloat
    ) -> Bool {
        let tolerance: CGFloat = 8
        let insetTargetBounds = targetBounds.insetBy(dx: tolerance, dy: tolerance)
        guard !windowBounds.isNull, !windowBounds.isEmpty, !insetTargetBounds.isEmpty else {
            return false
        }

        if windowBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(insetTargetBounds) {
            return true
        }

        let coveredArea = windowBounds.intersection(targetBounds).area
        let targetArea = targetBounds.area
        return targetArea > 0 && coveredArea / targetArea >= coverageThreshold
    }
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }
}
