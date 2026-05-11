import Foundation
import AppKit

struct ImageItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let displayName: String
    let pixelSize: CGSize
    let fileSize: Int64
    let thumbnail: NSImage

    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
