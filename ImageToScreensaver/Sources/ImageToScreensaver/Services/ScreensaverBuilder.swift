import Foundation

enum ScreensaverBuilderError: LocalizedError {
    case stubMissing
    case noImages
    case ioError(String)

    var errorDescription: String? {
        switch self {
        case .stubMissing:    return "Bundled ScreensaverStub.exe is missing. Run stub/build_stub.sh."
        case .noImages:       return "Add at least one image before exporting."
        case .ioError(let m): return m
        }
    }
}

/// Orchestrates the full export: transcode images → write stub → append
/// payload → append footer → rename to `.scr`.
struct ScreensaverBuilder {

    struct ProgressUpdate {
        let fraction: Double           // 0.0 – 1.0
        let message: String
    }

    static func locateStub() -> URL? {
        // SwiftPM bundles `.copy` resources flat into Bundle.module.
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "ScreensaverStub", withExtension: "exe"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/ImageToScreensaver/Resources/ScreensaverStub.exe")
        ]
        for case let url? in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            // Reject the placeholder text file shipped in the repo before the
            // real PE has been compiled by stub/build_stub.sh.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = (attrs[.size] as? NSNumber)?.intValue,
               size >= 1024,
               let header = try? FileHandle(forReadingFrom: url).read(upToCount: 2),
               header == Data([0x4D, 0x5A]) {     // "MZ" PE magic
                return url
            }
        }
        return nil
    }

    /// Build a `.scr` at `outputURL`. Calls `progress` on the main actor.
    static func build(
        images: [ImageItem],
        config: ScreensaverConfig,
        outputURL: URL,
        progress: @MainActor @escaping (ProgressUpdate) -> Void
    ) async throws {
        guard !images.isEmpty else { throw ScreensaverBuilderError.noImages }
        guard let stubURL = locateStub() else { throw ScreensaverBuilderError.stubMissing }

        // 1. Transcode images to PNG at target resolution.
        let maxSize = CGSize(width: config.resolution.width, height: config.resolution.height)
        var pngs: [Data] = []
        pngs.reserveCapacity(images.count)
        for (idx, item) in images.enumerated() {
            let png = try ImageProcessor.transcodeToPNG(url: item.url, maxSize: maxSize)
            pngs.append(png)
            let frac = 0.05 + 0.65 * Double(idx + 1) / Double(images.count)
            let msg = "Encoding \(item.displayName) (\(idx + 1)/\(images.count))"
            await MainActor.run { progress(.init(fraction: frac, message: msg)) }
        }

        // 2. Write stub bytes to output.
        await MainActor.run { progress(.init(fraction: 0.75, message: "Writing stub…")) }
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }
        try fm.copyItem(at: stubURL, to: outputURL)

        // 3. Append payload + footer.
        await MainActor.run { progress(.init(fraction: 0.85, message: "Appending payload…")) }

        let body = try PayloadBuilder.buildBody(config: config, pngs: pngs)
        let stubSize = (try fm.attributesOfItem(atPath: outputURL.path)[.size]
            as? NSNumber)?.uint64Value ?? 0

        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: body)
        let footer = PayloadBuilder.footer(payloadOffset: stubSize)
        try handle.write(contentsOf: footer)

        await MainActor.run { progress(.init(fraction: 1.0, message: "Done.")) }
    }
}
