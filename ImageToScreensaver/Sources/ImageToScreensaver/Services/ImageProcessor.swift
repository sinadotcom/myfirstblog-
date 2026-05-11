import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Decodes input images (PNG/JPG/JPEG/WEBP), resizes them to the target
/// resolution while preserving aspect ratio, and re-encodes as PNG so the
/// Windows stub only has to deal with one format.
enum ImageProcessorError: LocalizedError {
    case unsupportedFormat(URL)
    case decodeFailed(URL)
    case encodeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let u): return "Unsupported image: \(u.lastPathComponent)"
        case .decodeFailed(let u):      return "Could not decode \(u.lastPathComponent)"
        case .encodeFailed(let u):      return "Could not encode \(u.lastPathComponent)"
        }
    }
}

struct ImageProcessor {
    static let acceptedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]
    static let acceptedUTTypes: [UTType] = [.png, .jpeg, .webP]

    static func isAccepted(_ url: URL) -> Bool {
        acceptedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Build a thumbnail and gather metadata for the gallery.
    static func makeImageItem(from url: URL) throws -> ImageItem {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            throw ImageProcessorError.decodeFailed(url)
        }
        let w = (props[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else {
            throw ImageProcessorError.decodeFailed(url)
        }
        let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        return ImageItem(
            url: url,
            displayName: url.lastPathComponent,
            pixelSize: CGSize(width: w, height: h),
            fileSize: size,
            thumbnail: ns
        )
    }

    /// Decode → fit-resize → re-encode as PNG bytes. `maxSize` is the target
    /// resolution; images larger than that are scaled down to fit (aspect
    /// preserved). Smaller images are left untouched.
    static func transcodeToPNG(url: URL, maxSize: CGSize) throws -> Data {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageProcessorError.decodeFailed(url)
        }
        let limit = Int(max(maxSize.width, maxSize.height))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ImageProcessorError.decodeFailed(url)
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageProcessorError.encodeFailed(url)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ImageProcessorError.encodeFailed(url)
        }
        return out as Data
    }
}
