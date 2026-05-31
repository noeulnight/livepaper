import Foundation

enum WallpaperEngineBinaryReaderError: Error, Equatable {
    case unexpectedEndOfFile(offset: Int, requested: Int, size: Int)
    case invalidUTF8(offset: Int)
}

struct WallpaperEngineBinaryReader {
    private let data: Data
    private(set) var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var remainingCount: Int {
        max(0, data.count - offset)
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw WallpaperEngineBinaryReaderError.unexpectedEndOfFile(
                offset: offset,
                requested: count,
                size: data.count
            )
        }

        let range = offset..<(offset + count)
        offset += count
        return data.subdata(in: range)
    }

    mutating func skip(_ count: Int) throws {
        _ = try readData(count: count)
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return UInt32(bytes[0])
            | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 24
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readFloat32() throws -> Float {
        Float(bitPattern: try readUInt32())
    }

    mutating func readNullTerminatedString() throws -> String {
        let start = offset

        while offset < data.count {
            if data[offset] == 0 {
                let stringData = data.subdata(in: start..<offset)
                offset += 1

                guard let value = String(data: stringData, encoding: .utf8) else {
                    throw WallpaperEngineBinaryReaderError.invalidUTF8(offset: start)
                }

                return value
            }

            offset += 1
        }

        throw WallpaperEngineBinaryReaderError.unexpectedEndOfFile(
            offset: start,
            requested: 1,
            size: data.count
        )
    }

    mutating func readLengthPrefixedString() throws -> String {
        let lengthOffset = offset
        let length = Int(try readUInt32())
        let stringData = try readData(count: length)

        guard let value = String(data: stringData, encoding: .utf8) else {
            throw WallpaperEngineBinaryReaderError.invalidUTF8(offset: lengthOffset + 4)
        }

        return value
    }

    private mutating func readBytes(count: Int) throws -> [UInt8] {
        Array(try readData(count: count))
    }
}
