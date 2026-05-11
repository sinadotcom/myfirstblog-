import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var images: [ImageItem] = []
    @Published var config: ScreensaverConfig = .init()
    @Published var isBuilding: Bool = false
    @Published var progress: Double = 0.0
    @Published var progressMessage: String = ""
    @Published var lastExportURL: URL?
    @Published var errorMessage: String?

    var canExport: Bool { !images.isEmpty && !isBuilding }

    // MARK: - Image management

    func addImages(from urls: [URL]) {
        for url in urls {
            // Expand directories — let users drop a folder of pictures.
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                if let children = try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil) {
                    addImages(from: children)
                }
                continue
            }
            guard ImageProcessor.isAccepted(url) else { continue }
            if images.contains(where: { $0.url == url }) { continue }
            do {
                let item = try ImageProcessor.makeImageItem(from: url)
                images.append(item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func remove(_ item: ImageItem) {
        images.removeAll { $0.id == item.id }
    }

    func clearAll() { images.removeAll() }

    func move(from source: IndexSet, to destination: Int) {
        images.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Export

    func chooseAndExport() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "scr") ?? .data]
        panel.nameFieldStringValue = config.outputFilename + ".scr"
        panel.canCreateDirectories = true
        panel.title = "Export Screensaver"
        let response = await panel.beginAsync()
        guard response == .OK, let url = panel.url else { return }
        await export(to: url)
    }

    func export(to outputURL: URL) async {
        isBuilding = true
        defer { isBuilding = false }
        progress = 0
        progressMessage = "Starting…"
        do {
            try await ScreensaverBuilder.build(
                images: images,
                config: config,
                outputURL: outputURL
            ) { [weak self] update in
                self?.progress = update.fraction
                self?.progressMessage = update.message
            }
            lastExportURL = outputURL
            progressMessage = "Exported to \(outputURL.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
            progressMessage = ""
        }
    }

    func revealInFinder() {
        guard let url = lastExportURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - NSSavePanel async helper

private extension NSSavePanel {
    func beginAsync() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { cont in
            self.begin { response in cont.resume(returning: response) }
        }
    }
}
