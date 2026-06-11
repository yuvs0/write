import Foundation

/// Minimal ZIP writer for building DOCX packages. Entries are stored
/// uncompressed, which is valid ZIP and opens everywhere.
struct ZipArchive {
    private struct Entry {
        let name: String
        let data: Data
        let crc: UInt32
    }

    private var entries: [Entry] = []

    mutating func addFile(named name: String, data: Data) {
        entries.append(Entry(name: name, data: data, crc: Self.crc32(data)))
    }

    func archiveData() -> Data {
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let localHeaderOffset = UInt32(output.count)

            // Local file header.
            output.appendLE(UInt32(0x04034b50))
            output.appendLE(UInt16(20))         // version needed
            output.appendLE(UInt16(0x0800))     // flags: UTF-8 names
            output.appendLE(UInt16(0))          // method: stored
            output.appendLE(UInt16(0))          // mod time
            output.appendLE(UInt16(0x21))       // mod date (1980-01-01)
            output.appendLE(entry.crc)
            output.appendLE(UInt32(entry.data.count))
            output.appendLE(UInt32(entry.data.count))
            output.appendLE(UInt16(nameBytes.count))
            output.appendLE(UInt16(0))          // extra length
            output.append(contentsOf: nameBytes)
            output.append(entry.data)

            // Central directory record.
            centralDirectory.appendLE(UInt32(0x02014b50))
            centralDirectory.appendLE(UInt16(20))   // version made by
            centralDirectory.appendLE(UInt16(20))   // version needed
            centralDirectory.appendLE(UInt16(0x0800))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0))
            centralDirectory.appendLE(UInt16(0x21))
            centralDirectory.appendLE(entry.crc)
            centralDirectory.appendLE(UInt32(entry.data.count))
            centralDirectory.appendLE(UInt32(entry.data.count))
            centralDirectory.appendLE(UInt16(nameBytes.count))
            centralDirectory.appendLE(UInt16(0))    // extra length
            centralDirectory.appendLE(UInt16(0))    // comment length
            centralDirectory.appendLE(UInt16(0))    // disk number
            centralDirectory.appendLE(UInt16(0))    // internal attrs
            centralDirectory.appendLE(UInt32(0))    // external attrs
            centralDirectory.appendLE(localHeaderOffset)
            centralDirectory.append(contentsOf: nameBytes)
        }

        let centralDirectoryOffset = UInt32(output.count)
        output.append(centralDirectory)

        // End of central directory.
        output.appendLE(UInt32(0x06054b50))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(centralDirectory.count))
        output.appendLE(centralDirectoryOffset)
        output.appendLE(UInt16(0))

        return output
    }

    // MARK: - CRC-32 (IEEE 802.3)

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
