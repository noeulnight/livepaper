import AVFoundation

enum ScaleMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fill
    case fit
    case stretch
    case center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: "Fill"
        case .fit: "Fit"
        case .stretch: "Stretch"
        case .center: "Center"
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill:
            .resizeAspectFill
        case .fit, .center:
            .resizeAspect
        case .stretch:
            .resize
        }
    }
}
