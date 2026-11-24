import Foundation
import Compression

enum ZIPArchiveError: LocalizedError {
    case invalidArchive, invalidFile, unsupportedCompression, tooLarge, missingLists
    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "The selected file isn't a valid ZIP archive."
        case .invalidFile: return "A Followers or Following file is damaged or isn't UTF-8."
        case .unsupportedCompression: return "This ZIP uses an unsupported compression method."
        case .tooLarge: return "The archive or its list files exceed the safe import size."
        case .missingLists: return "Could not find both Followers and Following lists in this ZIP."
        }
    }
}

enum ZIPArchiveReader {
    // Limits protect against ZIP bombs and unexpectedly large exports.
    private static let maxArchive = 100 * 1024 * 1024
    private static let maxFile = 16 * 1024 * 1024
    private static let maxTotal = 40 * 1024 * 1024

    static func extract(from data: Data, selecting isRelevant: (String) -> Bool) throws -> [(String, Data)] {
        guard data.count <= maxArchive else { throw ZIPArchiveError.tooLarge }
        guard data.count >= 22 else { throw ZIPArchiveError.invalidArchive }
        try Task.checkCancellation()
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int? {
            guard i >= 0, i <= bytes.count - 2 else { return nil }
            return Int(bytes[i]) | (Int(bytes[i+1]) << 8)
        }
        func u32(_ i: Int) -> Int? {
            guard i >= 0, i <= bytes.count - 4 else { return nil }
            return Int(bytes[i]) | (Int(bytes[i+1]) << 8) | (Int(bytes[i+2]) << 16) | (Int(bytes[i+3]) << 24)
        }
        let scanStart = max(0, bytes.count - 65_557)
        guard let eocd = stride(from: bytes.count - 22, through: scanStart, by: -1).first(where: { u32($0) == 0x06054b50 }),
              let count = u16(eocd + 10), count <= 10_000,
              u16(eocd + 4) == 0, u16(eocd + 6) == 0, u16(eocd + 8) == count,
              let commentSize = u16(eocd + 20), eocd + 22 + commentSize == bytes.count,
              let directorySize = u32(eocd + 12),
              let directoryOffset = u32(eocd + 16), directoryOffset <= eocd, directorySize == eocd - directoryOffset else {
            throw ZIPArchiveError.invalidArchive
        }
        var cursor = directoryOffset
        var output: [(String, Data)] = []
        var total = 0
        for _ in 0..<count {
            try Task.checkCancellation()
            guard cursor + 46 <= eocd, u32(cursor) == 0x02014b50,
                  let flags = u16(cursor + 8), let method = u16(cursor + 10),
                  let crc = u32(cursor + 16),
                  let compressedSize = u32(cursor + 20), let uncompressedSize = u32(cursor + 24),
                  let nameLength = u16(cursor + 28), let extraLength = u16(cursor + 30),
                  let commentLength = u16(cursor + 32), let localOffset = u32(cursor + 42),
                  cursor + 46 + nameLength + extraLength + commentLength <= eocd,
                  let filename = String(bytes: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8) else {
                throw ZIPArchiveError.invalidArchive
            }
            cursor += 46 + nameLength + extraLength + commentLength
            guard isRelevant(filename) else { continue }
            guard compressedSize <= maxArchive, uncompressedSize <= maxFile,
                  total + uncompressedSize <= maxTotal else { throw ZIPArchiveError.tooLarge }
            guard flags & 1 == 0, localOffset < directoryOffset,
                  u16(localOffset + 6) == flags, u16(localOffset + 8) == method,
                  compressedSize <= maxArchive,
                  uncompressedSize <= maxFile, total + uncompressedSize <= maxTotal,
                  u32(localOffset) == 0x04034b50,
                  let localNameLength = u16(localOffset + 26), let localExtraLength = u16(localOffset + 28) else {
                throw ZIPArchiveError.invalidArchive
            }
            let payload = localOffset + 30 + localNameLength + localExtraLength
            guard payload <= directoryOffset, compressedSize <= directoryOffset - payload,
                  localNameLength == nameLength,
                  String(bytes: bytes[(localOffset + 30)..<(localOffset + 30 + localNameLength)], encoding: .utf8) == filename else {
                throw ZIPArchiveError.invalidArchive
            }
            let compressed = Data(bytes[payload..<(payload + compressedSize)])
            let decoded: Data
            switch method {
            case 0:
                guard compressedSize == uncompressedSize else { throw ZIPArchiveError.invalidFile }
                decoded = compressed
            case 8:
                guard !compressed.isEmpty else { throw ZIPArchiveError.invalidFile }
                let outputCapacity = uncompressedSize + 1
                var buffer = [UInt8](repeating: 0, count: outputCapacity)
                let written = compressed.withUnsafeBytes { source in
                    buffer.withUnsafeMutableBytes { destination in
                        guard let target = destination.bindMemory(to: UInt8.self).baseAddress,
                              let input = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                        return compression_decode_buffer(target, outputCapacity,
                            input, compressedSize, nil, COMPRESSION_ZLIB)
                    }
                }
                guard written == uncompressedSize else { throw ZIPArchiveError.invalidFile }
                decoded = Data(buffer.prefix(written))
            default: throw ZIPArchiveError.unsupportedCompression
            }
            guard try Self.crc32(decoded) == UInt32(crc) else { throw ZIPArchiveError.invalidFile }
            total += uncompressedSize
            output.append((filename, decoded))
        }
        guard cursor == eocd else { throw ZIPArchiveError.invalidArchive }
        return output
    }
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb8_8320) }
        return crc
    }

    static func crc32(_ data: Data) throws -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for (index, byte) in data.enumerated() {
            if index & 65_535 == 0 { try Task.checkCancellation() }
            crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)]
        }
        return crc ^ 0xffff_ffff
    }
}
