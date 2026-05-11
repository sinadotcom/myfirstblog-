import Foundation

/// Builds the binary payload that gets appended to the stub `.exe`.
///
/// Layout (must match screensaver_stub.cpp):
///
///   [u32 metadata_len][metadata JSON utf-8]
///   [u32 image_count]
///     for each image: [u32 image_len][PNG bytes]
///   [8 bytes magic = "SCRPLD\x01\x00"]
///   [u64 LE offset to start of payload]
struct PayloadBuilder {
    static let footerMagic: [UInt8] = [0x53, 0x43, 0x52, 0x50, 0x4C, 0x44, 0x01, 0x00]

    static func buildBody(config: ScreensaverConfig, pngs: [Data]) throws -> Data {
        var body = Data()
        let json = try config.jsonForStub()
        body.appendLE(UInt32(json.count))
        body.append(json)
        body.appendLE(UInt32(pngs.count))
        for png in pngs {
            body.appendLE(UInt32(png.count))
            body.append(png)
        }
        return body
    }

    /// Returns the 16-byte footer given the offset where the payload starts in
    /// the final file (i.e. the size of the stub bytes prefix).
    static func footer(payloadOffset: UInt64) -> Data {
        var footer = Data(footerMagic)
        footer.appendLE(payloadOffset)
        return footer
    }
}

private extension Data {
    mutating func appendLE(_ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ v: UInt64) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
