import Foundation

enum TransitionEffect: String, CaseIterable, Identifiable, Codable {
    case none
    case fade
    case slide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:  return "None"
        case .fade:  return "Fade"
        case .slide: return "Slide"
        }
    }
}

enum FitMode: String, CaseIterable, Identifiable, Codable {
    case contain
    case cover
    case stretch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .contain: return "Contain (letterbox)"
        case .cover:   return "Cover (crop)"
        case .stretch: return "Stretch"
        }
    }
}

struct Resolution: Hashable, Identifiable, Codable {
    let width: Int
    let height: Int
    var id: String { "\(width)x\(height)" }
    var label: String { "\(width) × \(height)" }

    static let presets: [Resolution] = [
        Resolution(width: 1280, height: 720),
        Resolution(width: 1920, height: 1080),
        Resolution(width: 2560, height: 1440),
        Resolution(width: 3840, height: 2160)
    ]
}
