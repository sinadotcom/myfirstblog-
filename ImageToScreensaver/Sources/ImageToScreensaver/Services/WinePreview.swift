import Foundation

/// Optional preview using Wine, if the user has it installed.
/// We never bundle Wine; we only call it if it's already on PATH.
enum WinePreviewError: LocalizedError {
    case wineNotFound
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .wineNotFound:      return "Wine is not installed. Install with: brew install --cask --no-quarantine wine-stable"
        case .launchFailed(let m): return "Wine failed: \(m)"
        }
    }
}

struct WinePreview {
    static func wineBinary() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/wine",   // Apple Silicon
            "/usr/local/bin/wine",       // Intel
            "/opt/homebrew/bin/wine64",
            "/usr/local/bin/wine64"
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        return nil
    }

    static var isAvailable: Bool { wineBinary() != nil }

    /// Launches the `.scr` via Wine in `/s` mode for a quick preview.
    static func preview(scrURL: URL) throws {
        guard let wine = wineBinary() else { throw WinePreviewError.wineNotFound }
        let proc = Process()
        proc.executableURL = wine
        proc.arguments = [scrURL.path, "/s"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do { try proc.run() }
        catch { throw WinePreviewError.launchFailed(error.localizedDescription) }
    }
}
