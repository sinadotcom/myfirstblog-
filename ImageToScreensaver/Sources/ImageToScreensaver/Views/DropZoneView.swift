import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08)
                                         : Color.secondary.opacity(0.04))
                )

            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop PNG, JPG or WEBP images here")
                    .font(.title3)
                Text("or click to browse")
                    .foregroundStyle(.secondary)
                Button("Choose Images…") { openPanel() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture { openPanel() }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = ImageProcessor.acceptedUTTypes
        panel.title = "Select images"
        panel.begin { resp in
            if resp == .OK { vm.addImages(from: panel.urls) }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { vm.addImages(from: urls) }
        return true
    }
}
