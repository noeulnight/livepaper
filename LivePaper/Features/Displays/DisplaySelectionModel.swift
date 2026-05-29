import AppKit
import Foundation

@MainActor
final class DisplaySelectionModel {
    private(set) var displays: [DisplayState] = []
    var selectedDisplayIDs: Set<DisplayID> = []
    var audioDisplayID: DisplayID?

    func refreshDisplays() {
        displays = NSScreen.screens.compactMap(DisplayState.init(screen:))
        selectedDisplayIDs.formIntersection(Set(displays.map(\.id)))
        normalizeAudioDisplayID()

        if selectedDisplayIDs.isEmpty, let firstDisplay = displays.first {
            selectedDisplayIDs = [firstDisplay.id]
        }
    }

    func normalizeAudioDisplayID() {
        let availableDisplayIDs = Set(displays.map(\.id))
        if let audioDisplayID, availableDisplayIDs.contains(audioDisplayID) {
            return
        }

        audioDisplayID = NSScreen.main?.livePaperDisplayID ?? displays.first?.id
    }

    func fallbackAudioDisplayID(activeDisplayIDs: Set<DisplayID>) -> DisplayID? {
        if let mainDisplayID = NSScreen.main?.livePaperDisplayID, activeDisplayIDs.contains(mainDisplayID) {
            return mainDisplayID
        }

        if let firstActiveDisplayID = orderedDisplayIDs(from: activeDisplayIDs).first {
            return firstActiveDisplayID
        }

        return NSScreen.main?.livePaperDisplayID ?? displays.first?.id
    }

    func audioOwnerID(activeDisplayIDs: Set<DisplayID>, muted: Bool) -> DisplayID? {
        guard !muted, !activeDisplayIDs.isEmpty else {
            return nil
        }

        if let audioDisplayID, activeDisplayIDs.contains(audioDisplayID) {
            return audioDisplayID
        }

        if let mainDisplayID = NSScreen.main?.livePaperDisplayID, activeDisplayIDs.contains(mainDisplayID) {
            return mainDisplayID
        }

        return orderedDisplayIDs(from: activeDisplayIDs).first
    }

    func orderedDisplayIDs(from displayIDs: Set<DisplayID>) -> [DisplayID] {
        let displayOrder = displays.map(\.id).filter { displayIDs.contains($0) }
        let displayOrderSet = Set(displayOrder)
        let remainingIDs = displayIDs
            .subtracting(displayOrderSet)
            .sorted { $0.uuid < $1.uuid }
        return displayOrder + remainingIDs
    }
}
