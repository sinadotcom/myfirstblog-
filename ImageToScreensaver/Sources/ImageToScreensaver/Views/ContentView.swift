import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        HSplitView {
            // LEFT: drop zone or gallery
            VStack(spacing: 12) {
                if vm.images.isEmpty {
                    DropZoneView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    ImageGalleryView()
                        .padding(.horizontal)
                        .padding(.top, 12)
                    Divider()
                    DropZoneView()
                        .frame(height: 110)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }
            }
            .frame(minWidth: 520)

            // RIGHT: settings + export
            VStack(spacing: 0) {
                SettingsPanel()

                Divider()

                ExportBar()
                    .padding(16)
            }
            .frame(minWidth: 340, idealWidth: 360)
        }
        .alert("Error",
               isPresented: .init(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
               ),
               presenting: vm.errorMessage) { _ in
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: { msg in
            Text(msg)
        }
    }
}

private struct ExportBar: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vm.isBuilding || vm.progress > 0 {
                ProgressView(value: vm.progress) {
                    Text(vm.progressMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .progressViewStyle(.linear)
            }

            HStack {
                Button {
                    Task { await vm.chooseAndExport() }
                } label: {
                    Label("Export .scr…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canExport)
                .keyboardShortcut("e", modifiers: [.command])
            }

            if vm.lastExportURL != nil {
                HStack {
                    Button("Reveal in Finder") { vm.revealInFinder() }
                    if vm.winePreviewAvailable {
                        Button("Preview with Wine") { vm.previewWithWine() }
                    }
                    Spacer()
                }
                .font(.callout)
            }
        }
    }
}
