import Foundation

struct DisplayID: Hashable, Codable, Sendable, Identifiable {
    let uuid: String

    var id: String { uuid }
}
