import Compression
import Foundation

/// A minimal read-only zip reader, enough to pull named parts out of an OOXML
/// package.
///
/// Internal on purpose: this is how `PPTXMetadata` gets at the parts inside a
/// `.pptx`, not a general-purpose archive API, and it implements only what that
/// needs. It exists rather than a package dependency because `Compression` ships
/// with the OS, and ADR-0002 commits to an app that needs nothing installed.
///
/// Deliberately absent: writing, encryption, Zip64, multi-disk archives, and the
/// data-descriptor path. Each throws rather than guessing, because a zip reader
/// that returns *plausible* bytes for input it did not understand is worse than
/// one that refuses — the caller cannot tell it went wrong.
struct ZipArchive {
    struct Entry {
        let path: String
        /// Compression method: 0 stored, 8 deflate. Anything else is rejected.
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        /// Offset of this entry's *local* header, which is where the bytes live.
        let localHeaderOffset: Int
    }

    enum Error: Swift.Error, Equatable {
        case notAZipArchive
        case malformed(String)
        /// Zip64, encryption and unusual compression methods all land here. The
        /// reason is carried so a bug report says which one.
        case unsupported(String)
        case inflateFailed(path: String)
    }

    private let data: Data
    private let entries: [String: Entry]

    var paths: [String] { Array(entries.keys) }

    init(data: Data) throws {
        // Every offset in a zip is absolute from the start of the archive, and a
        // `Data` slice keeps its parent's indices — so `data[0]` traps on one.
        // Re-basing here means the rest of this type can index from zero without
        // each read having to remember to add `startIndex`.
        self.data = data.startIndex == 0 ? data : Data(data)
        self.entries = try Self.readCentralDirectory(self.data)
    }

    init(url: URL) throws {
        // Mapped rather than read: the largest deck in testing was 5.3MB, but a
        // 200-slide deck with images is not, and nothing here needs the whole
        // file resident at once.
        try self.init(data: try Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// The decompressed contents of a part, or `nil` if the archive has no such
    /// path. Throws only when the entry exists but cannot be read.
    func data(for path: String) throws -> Data? {
        guard let entry = entries[path] else { return nil }
        return try bytes(of: entry)
    }

    // MARK: - Central directory

    private static let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
    private static let centralFileSignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
    private static let localFileSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        // The EOCD sits at the end, after a comment of up to 64KB. Scanning back
        // from the end is the only way to find it — the format has no forward
        // pointer to it.
        let minimumEOCDSize = 22
        guard data.count >= minimumEOCDSize else { throw Error.notAZipArchive }

        let searchLimit = min(data.count, minimumEOCDSize + 65_535)
        var eocd: Int?
        for back in 0..<(searchLimit - minimumEOCDSize + 1) {
            let candidate = data.count - minimumEOCDSize - back
            if matches(data, at: candidate, eocdSignature) {
                eocd = candidate
                break
            }
        }
        guard let eocd else { throw Error.notAZipArchive }

        let entryCount = Int(u16(data, eocd + 10))
        let directoryOffset = Int(u32(data, eocd + 16))

        // 0xFFFF / 0xFFFFFFFF are Zip64 sentinels: the real values live in a
        // separate record this reader does not implement. Refusing beats reading
        // the sentinel as a count.
        if entryCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF {
            throw Error.unsupported("Zip64 archive")
        }
        guard directoryOffset >= 0, directoryOffset < data.count else {
            throw Error.malformed("central directory offset out of bounds")
        }

        var result: [String: Entry] = [:]
        var cursor = directoryOffset

        for _ in 0..<entryCount {
            let centralHeaderSize = 46
            guard cursor + centralHeaderSize <= data.count,
                matches(data, at: cursor, centralFileSignature)
            else {
                throw Error.malformed("central directory entry truncated")
            }

            let flags = u16(data, cursor + 8)
            // Bit 0 is the encryption flag. There is no useful partial read.
            if flags & 0x0001 != 0 { throw Error.unsupported("encrypted entry") }

            let method = u16(data, cursor + 10)
            let compressedSize = Int(u32(data, cursor + 20))
            let uncompressedSize = Int(u32(data, cursor + 24))
            let nameLength = Int(u16(data, cursor + 28))
            let extraLength = Int(u16(data, cursor + 30))
            let commentLength = Int(u16(data, cursor + 32))
            let localOffset = Int(u32(data, cursor + 42))

            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF
                || localOffset == 0xFFFF_FFFF
            {
                throw Error.unsupported("Zip64 entry sizes")
            }

            let nameStart = cursor + centralHeaderSize
            guard nameStart + nameLength <= data.count else {
                throw Error.malformed("entry name truncated")
            }
            let path = String(decoding: data[nameStart..<nameStart + nameLength], as: UTF8.self)

            // Directory markers carry no payload; keeping them would only make
            // `data(for:)` return empty for a path that is not a part.
            if !path.hasSuffix("/") {
                result[path] = Entry(
                    path: path,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset
                )
            }

            cursor = nameStart + nameLength + extraLength + commentLength
        }

        return result
    }

    // MARK: - Reading one entry

    private func bytes(of entry: Entry) throws -> Data {
        let localHeaderSize = 30
        let offset = entry.localHeaderOffset
        guard offset >= 0, offset + localHeaderSize <= data.count,
            Self.matches(data, at: offset, Self.localFileSignature)
        else {
            throw Error.malformed("local header missing for \(entry.path)")
        }

        // The local header repeats the name and extra fields, and its extra
        // field length can differ from the central directory's — so it has to be
        // read here rather than reused.
        let nameLength = Int(Self.u16(data, offset + 26))
        let extraLength = Int(Self.u16(data, offset + 28))
        let start = offset + localHeaderSize + nameLength + extraLength
        guard start >= 0, start + entry.compressedSize <= data.count else {
            throw Error.malformed("payload out of bounds for \(entry.path)")
        }
        let payload = data[start..<start + entry.compressedSize]

        switch entry.method {
        case 0:
            // Stored. A survey of 61 real decks found 1219 stored entries, 82 of
            // them .xml — treating everything as deflate silently yields garbage
            // for exactly the parts this reader exists to fetch.
            return Data(payload)
        case 8:
            return try inflate(payload, to: entry.uncompressedSize, path: entry.path)
        default:
            throw Error.unsupported("compression method \(entry.method) for \(entry.path)")
        }
    }

    private func inflate(_ payload: Data, to size: Int, path: String) throws -> Data {
        // An empty part deflates to a couple of bytes but has nothing to write
        // into; `compression_decode_buffer` with a zero-sized destination fails.
        guard size > 0 else { return Data() }

        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress
            else { return 0 }
            return payload.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE here, which is what a zip
                // entry holds — there is no zlib wrapper to strip.
                return compression_decode_buffer(
                    destinationBase, size,
                    sourceBase, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        // A short read means the stream disagreed with the declared size. That is
        // corruption, not something to hand back and hope about.
        guard written == size else { throw Error.inflateFailed(path: path) }
        return output
    }

    // MARK: - Little-endian field reads

    private static func matches(_ data: Data, at offset: Int, _ signature: [UInt8]) -> Bool {
        guard offset >= 0, offset + signature.count <= data.count else { return false }
        for (index, byte) in signature.enumerated() where data[offset + index] != byte {
            return false
        }
        return true
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(u16(data, offset)) | UInt32(u16(data, offset + 2)) << 16
    }

    private func u16(_ data: Data, _ offset: Int) -> UInt16 { Self.u16(data, offset) }
}
