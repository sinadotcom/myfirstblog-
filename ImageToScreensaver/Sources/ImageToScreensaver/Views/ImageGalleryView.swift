import SwiftUI

struct ImageGalleryView: View {
    @EnvironmentObject var vm: AppViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(vm.images.count) image\(vm.images.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Button("Clear All", role: .destructive) { vm.clearAll() }
                    .disabled(vm.images.isEmpty)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(vm.images) { item in
                        thumb(for: item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func thumb(for item: ImageItem) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 140, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Text(item.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 140)
                Text("\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                vm.remove(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }
}
