import Foundation
#if canImport(Compression)
import Compression
#endif

enum WallpaperEngineTextureError: LocalizedError, Equatable {
    case invalidMagic(String)
    case unsupportedContainer(String)
    case unsupportedAnimationContainer(String)
    case unsupportedMipmapCompression(UInt32)
    case invalidCompressedMipmapSize(Int32?)
    case mipmapDecompressionFailed(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidMagic(let value):
            return "Wallpaper Engine texture has an invalid magic value: \(value)"
        case .unsupportedContainer(let value):
            return "Wallpaper Engine texture uses an unsupported container: \(value)"
        case .unsupportedAnimationContainer(let value):
            return "Wallpaper Engine texture uses an unsupported animation container: \(value)"
        case .unsupportedMipmapCompression(let value):
            return "Wallpaper Engine texture uses unsupported mipmap compression: \(value)"
        case .invalidCompressedMipmapSize(let value):
            return "Wallpaper Engine texture has an invalid compressed mipmap size: \(value.map(String.init) ?? "nil")"
        case .mipmapDecompressionFailed(let expected, let actual):
            return "Wallpaper Engine texture mipmap decompression failed: expected \(expected) bytes, got \(actual)"
        }
    }
}

struct WallpaperEngineTextureInfo: Equatable, Sendable {
    enum Format: UInt32, Equatable, Sendable {
        case argb8888 = 0
        case rgb888 = 1
        case rgb565 = 2
        case dxt5 = 4
        case dxt3 = 6
        case dxt1 = 7
        case rg88 = 8
        case r8 = 9
        case rg1616f = 10
        case r16f = 11
        case bc7 = 12
        case rgba1010102 = 13
        case rgba16161616f = 14
        case rgb161616f = 15
        case unknown = 0xFFFF_FFFF
    }

    enum ContainerVersion: String, Equatable, Sendable {
        case texb0001 = "TEXB0001"
        case texb0002 = "TEXB0002"
        case texb0003 = "TEXB0003"
        case texb0004 = "TEXB0004"
    }

    enum AnimationVersion: String, Equatable, Sendable {
        case texs0001 = "TEXS0001"
        case texs0002 = "TEXS0002"
        case texs0003 = "TEXS0003"
    }

    struct Mipmap: Equatable, Sendable {
        let imageIndex: Int
        let level: Int
        let width: UInt32
        let height: UInt32
        let compression: UInt32?
        let uncompressedSize: Int32?
        let byteCount: Int32
        let data: Data
        let metadataJSON: String?
    }

    struct Frame: Equatable, Sendable {
        let frameNumber: UInt32
        let frameTime: Float
        let x: Float
        let y: Float
        let width1: Float
        let width2: Float
        let height1: Float
        let height2: Float
    }

    let path: String
    let format: Format
    let rawFormat: UInt32
    let flags: UInt32
    let textureWidth: UInt32
    let textureHeight: UInt32
    let imageWidth: UInt32
    let imageHeight: UInt32
    let containerVersion: ContainerVersion
    let rawContainerVersion: String
    let freeImageFormat: Int32?
    let isVideoMP4: Bool
    let imageCount: UInt32
    let mipmaps: [Mipmap]
    let animationVersion: AnimationVersion?
    let gifWidth: UInt32?
    let gifHeight: UInt32?
    let frames: [Frame]

    var isAnimated: Bool {
        (flags & WallpaperEngineTextureParser.Flags.isGIF) != 0
    }

    var isVideoTexture: Bool {
        isVideoMP4 || (flags & WallpaperEngineTextureParser.Flags.isVideoTexture) != 0
    }
}

struct WallpaperEngineTextureParser {
    enum Flags {
        static let noInterpolation: UInt32 = 1
        static let clampUVs: UInt32 = 2
        static let isGIF: UInt32 = 4
        static let clampUVsBorder: UInt32 = 8
        static let isVideoTexture: UInt32 = 32
        static let alphaChannelPriority: UInt32 = 524_288
    }

    func parseTexture(data: Data, path: String) throws -> WallpaperEngineTextureInfo {
        var reader = WallpaperEngineBinaryReader(data: data)

        let magic = try reader.readNullTerminatedString()
        guard magic == "TEXV0005" else {
            throw WallpaperEngineTextureError.invalidMagic(magic)
        }

        let subMagic = try reader.readNullTerminatedString()
        guard subMagic == "TEXI0001" else {
            throw WallpaperEngineTextureError.invalidMagic(subMagic)
        }

        let rawFormat = try reader.readUInt32()
        let flags = try reader.readUInt32()
        let textureWidth = try reader.readUInt32()
        let textureHeight = try reader.readUInt32()
        let imageWidth = try reader.readUInt32()
        let imageHeight = try reader.readUInt32()
        try reader.skip(4)

        let rawContainerVersion = try reader.readNullTerminatedString()
        let imageCount = try reader.readUInt32()
        var containerVersion = try parseContainerVersion(rawContainerVersion)
        var freeImageFormat: Int32?
        var isVideoMP4 = false

        switch containerVersion {
        case .texb0004:
            freeImageFormat = try reader.readInt32()
            isVideoMP4 = try reader.readUInt32() == 1

            if !isVideoMP4 {
                containerVersion = .texb0003
            }
        case .texb0003:
            freeImageFormat = try reader.readInt32()
        case .texb0002, .texb0001:
            break
        }

        var mipmaps: [WallpaperEngineTextureInfo.Mipmap] = []
        for imageIndex in 0..<Int(imageCount) {
            let mipmapCount = try reader.readUInt32()

            for level in 0..<Int(mipmapCount) {
                mipmaps.append(try parseMipmap(
                    imageIndex: imageIndex,
                    level: level,
                    containerVersion: containerVersion,
                    reader: &reader
                ))
            }
        }

        var animationVersion: WallpaperEngineTextureInfo.AnimationVersion?
        var gifWidth: UInt32?
        var gifHeight: UInt32?
        var frames: [WallpaperEngineTextureInfo.Frame] = []

        if (flags & Flags.isGIF) != 0 {
            let animationMagic = try reader.readNullTerminatedString()
            animationVersion = try parseAnimationVersion(animationMagic)
            let frameCount = try reader.readUInt32()

            if animationVersion == .texs0003 {
                gifWidth = try reader.readUInt32()
                gifHeight = try reader.readUInt32()
            }

            for _ in 0..<frameCount {
                frames.append(try parseFrame(animationVersion: animationVersion!, reader: &reader))
            }

            if animationVersion == .texs0001 || animationVersion == .texs0002, let first = frames.first {
                gifWidth = UInt32(first.width1)
                gifHeight = UInt32(first.height1)
            }
        }

        return WallpaperEngineTextureInfo(
            path: path.normalizedWallpaperEnginePath,
            format: WallpaperEngineTextureInfo.Format(rawValue: rawFormat) ?? .unknown,
            rawFormat: rawFormat,
            flags: flags,
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            containerVersion: containerVersion,
            rawContainerVersion: rawContainerVersion,
            freeImageFormat: freeImageFormat,
            isVideoMP4: isVideoMP4,
            imageCount: imageCount,
            mipmaps: mipmaps,
            animationVersion: animationVersion,
            gifWidth: gifWidth,
            gifHeight: gifHeight,
            frames: frames
        )
    }

    private func parseContainerVersion(_ rawValue: String) throws -> WallpaperEngineTextureInfo.ContainerVersion {
        guard let value = WallpaperEngineTextureInfo.ContainerVersion(rawValue: rawValue) else {
            throw WallpaperEngineTextureError.unsupportedContainer(rawValue)
        }
        return value
    }

    private func parseAnimationVersion(_ rawValue: String) throws -> WallpaperEngineTextureInfo.AnimationVersion {
        guard let value = WallpaperEngineTextureInfo.AnimationVersion(rawValue: rawValue) else {
            throw WallpaperEngineTextureError.unsupportedAnimationContainer(rawValue)
        }
        return value
    }

    private func parseMipmap(
        imageIndex: Int,
        level: Int,
        containerVersion: WallpaperEngineTextureInfo.ContainerVersion,
        reader: inout WallpaperEngineBinaryReader
    ) throws -> WallpaperEngineTextureInfo.Mipmap {
        var metadataJSON: String?

        if containerVersion == .texb0004 {
            try reader.skip(8)
            metadataJSON = try reader.readNullTerminatedString()
            try reader.skip(4)
        }

        let width = try reader.readUInt32()
        let height = try reader.readUInt32()

        var compression: UInt32?
        var uncompressedSize: Int32?
        if containerVersion == .texb0004 || containerVersion == .texb0003 || containerVersion == .texb0002 {
            compression = try reader.readUInt32()
            uncompressedSize = try reader.readInt32()
        }

        let byteCount = try reader.readInt32()
        let data = try decodeMipmapData(
            compression: compression,
            uncompressedSize: uncompressedSize,
            byteCount: byteCount,
            reader: &reader
        )

        return WallpaperEngineTextureInfo.Mipmap(
            imageIndex: imageIndex,
            level: level,
            width: width,
            height: height,
            compression: compression,
            uncompressedSize: uncompressedSize,
            byteCount: byteCount,
            data: data,
            metadataJSON: metadataJSON
        )
    }

    private func decodeMipmapData(
        compression: UInt32?,
        uncompressedSize: Int32?,
        byteCount: Int32,
        reader: inout WallpaperEngineBinaryReader
    ) throws -> Data {
        let storedData = try reader.readData(count: Int(byteCount))
        let compressionMode = compression ?? 0

        switch compressionMode {
        case 0:
            return storedData
        case 1:
            guard let uncompressedSize,
                  uncompressedSize >= 0 else {
                throw WallpaperEngineTextureError.invalidCompressedMipmapSize(uncompressedSize)
            }
            return try decompressLZ4(storedData, expectedByteCount: Int(uncompressedSize))
        default:
            throw WallpaperEngineTextureError.unsupportedMipmapCompression(compressionMode)
        }
    }

    private func decompressLZ4(_ data: Data, expectedByteCount: Int) throws -> Data {
        guard expectedByteCount > 0 else {
            return Data()
        }

        if let rawBlock = try? decompressRawLZ4Block(data, expectedByteCount: expectedByteCount) {
            return rawBlock
        }

#if canImport(Compression)
        var output = Data(count: expectedByteCount)
        let decodedByteCount = data.withUnsafeBytes { sourceBuffer in
            output.withUnsafeMutableBytes { destinationBuffer in
                guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let destination = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }

                return compression_decode_buffer(
                    destination,
                    expectedByteCount,
                    source,
                    data.count,
                    nil,
                    COMPRESSION_LZ4
                )
            }
        }

        guard decodedByteCount == expectedByteCount else {
            throw WallpaperEngineTextureError.mipmapDecompressionFailed(
                expected: expectedByteCount,
                actual: decodedByteCount
            )
        }

        return output
#else
        throw WallpaperEngineTextureError.unsupportedMipmapCompression(1)
#endif
    }

    private func decompressRawLZ4Block(_ data: Data, expectedByteCount: Int) throws -> Data {
        let source = Array(data)
        var sourceIndex = 0
        var output: [UInt8] = []
        output.reserveCapacity(expectedByteCount)

        while sourceIndex < source.count {
            let token = source[sourceIndex]
            sourceIndex += 1

            let literalLength = try readLZ4Length(
                baseLength: Int(token >> 4),
                source: source,
                sourceIndex: &sourceIndex
            )
            guard sourceIndex + literalLength <= source.count else {
                throw WallpaperEngineTextureError.mipmapDecompressionFailed(
                    expected: expectedByteCount,
                    actual: output.count
                )
            }
            output.append(contentsOf: source[sourceIndex..<(sourceIndex + literalLength)])
            sourceIndex += literalLength

            if sourceIndex == source.count {
                break
            }

            guard sourceIndex + 2 <= source.count else {
                throw WallpaperEngineTextureError.mipmapDecompressionFailed(
                    expected: expectedByteCount,
                    actual: output.count
                )
            }
            let matchOffset = Int(source[sourceIndex])
                | (Int(source[sourceIndex + 1]) << 8)
            sourceIndex += 2
            guard matchOffset > 0, matchOffset <= output.count else {
                throw WallpaperEngineTextureError.mipmapDecompressionFailed(
                    expected: expectedByteCount,
                    actual: output.count
                )
            }

            let matchLength = try readLZ4Length(
                baseLength: Int(token & 0x0F),
                source: source,
                sourceIndex: &sourceIndex
            ) + 4
            guard output.count + matchLength <= expectedByteCount else {
                throw WallpaperEngineTextureError.mipmapDecompressionFailed(
                    expected: expectedByteCount,
                    actual: output.count + matchLength
                )
            }

            for _ in 0..<matchLength {
                output.append(output[output.count - matchOffset])
            }
        }

        guard output.count == expectedByteCount else {
            throw WallpaperEngineTextureError.mipmapDecompressionFailed(
                expected: expectedByteCount,
                actual: output.count
            )
        }

        return Data(output)
    }

    private func readLZ4Length(
        baseLength: Int,
        source: [UInt8],
        sourceIndex: inout Int
    ) throws -> Int {
        var length = baseLength
        if baseLength != 15 {
            return length
        }

        while sourceIndex < source.count {
            let value = Int(source[sourceIndex])
            sourceIndex += 1
            length += value

            if value != 255 {
                return length
            }
        }

        throw WallpaperEngineTextureError.mipmapDecompressionFailed(
            expected: length,
            actual: sourceIndex
        )
    }

    private func parseFrame(
        animationVersion: WallpaperEngineTextureInfo.AnimationVersion,
        reader: inout WallpaperEngineBinaryReader
    ) throws -> WallpaperEngineTextureInfo.Frame {
        let frameNumber = try reader.readUInt32()
        let frameTime = try reader.readFloat32()

        if animationVersion == .texs0001 {
            let x = Float(try reader.readUInt32())
            let y = Float(try reader.readUInt32())
            let width1 = Float(try reader.readUInt32())
            _ = try reader.readUInt32()
            _ = try reader.readUInt32()
            let height1 = Float(try reader.readUInt32())

            return WallpaperEngineTextureInfo.Frame(
                frameNumber: frameNumber,
                frameTime: frameTime,
                x: x,
                y: y,
                width1: width1,
                width2: width1,
                height1: height1,
                height2: height1
            )
        }

        let x = try reader.readFloat32()
        let y = try reader.readFloat32()
        let width1 = try reader.readFloat32()
        let width2 = try reader.readFloat32()
        let height2 = try reader.readFloat32()
        let height1 = try reader.readFloat32()

        return WallpaperEngineTextureInfo.Frame(
            frameNumber: frameNumber,
            frameTime: frameTime,
            x: x,
            y: y,
            width1: width1,
            width2: width2,
            height1: height1,
            height2: height2
        )
    }
}
