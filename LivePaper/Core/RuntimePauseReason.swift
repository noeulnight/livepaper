import Foundation

enum RuntimePauseReason: Hashable, Sendable {
    case battery
    case fullscreen
    case systemSleep
    case screenSleep
    case locked
}
