import Foundation

struct ScreensaverConfig: Codable, Equatable {
    var duration: Double = 5.0
    var transition: TransitionEffect = .fade
    var transitionDuration: Double = 1.0
    var fitMode: FitMode = .contain
    var backgroundColor: String = "#000000"
    var shuffle: Bool = false
    var resolution: Resolution = Resolution(width: 1920, height: 1080)
    var outputFilename: String = "MySlideshow"
    var version: Int = 1

    enum CodingKeys: String, CodingKey {
        // These keys must match what screensaver_stub.cpp parses.
        case duration, transition, transitionDuration, fitMode
        case backgroundColor, shuffle, version
    }

    /// Returns a JSON-encoded representation matching the stub's parser.
    func jsonForStub() throws -> Data {
        let dict: [String: Any] = [
            "duration": duration,
            "transition": transition.rawValue,
            "transitionDuration": transitionDuration,
            "fitMode": fitMode.rawValue,
            "backgroundColor": backgroundColor,
            "shuffle": shuffle,
            "version": version
        ]
        return try JSONSerialization.data(
            withJSONObject: dict,
            options: [.sortedKeys]
        )
    }
}
