import Foundation
import IOKit.ps

enum SystemPowerState {
    static var isOnBatteryPower: Bool {
        IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() == nil
    }
}
