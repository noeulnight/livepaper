import AppKit

enum WallpaperRuntimeError: LocalizedError {
    case displayNotFound(String)
    case missingContentView

    var errorDescription: String? {
        switch self {
        case .displayNotFound(let uuid):
            "Display not found: \(uuid)"
        case .missingContentView:
            "Wallpaper window has no content view."
        }
    }
}

extension NSScreen {
    var livePaperDisplayID: DisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        let uuidString = CFUUIDCreateString(nil, uuid) as String?
        return uuidString.map(DisplayID.init(uuid:))
    }
}
