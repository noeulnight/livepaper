import Foundation

#if canImport(Metal)
import Metal

struct WallpaperEngineMetalCompiledScene {
    let sourceTextures: [String: MTLTexture]
    let renderTargetTextures: [String: MTLTexture]
    let sourceSamplerStates: [String: MTLSamplerState]
    let shaderLibraries: [String: MTLLibrary]
    let pipelineStates: [String: MTLRenderPipelineState]
    let depthStencilStates: [String: MTLDepthStencilState]
    let samplerState: MTLSamplerState
    let diagnostics: [String]
}

struct WallpaperEngineMetalResourceCompiler {
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    func compile(
        resources: WallpaperEngineResolvedSceneResources
    ) throws -> WallpaperEngineMetalCompiledScene {
        var diagnostics: [String] = []
        let sourceTextures = makeSourceTextures(
            textureDescriptors: resources.metalRenderPlan.textures,
            textureInfos: resources.textures,
            diagnostics: &diagnostics
        )
        let renderTargetTextures = makeRenderTargetTextures(
            framebufferDescriptors: resources.metalRenderPlan.framebuffers,
            diagnostics: &diagnostics
        )
        let sourceSamplerStates = makeSourceSamplerStates(
            textureDescriptors: resources.metalRenderPlan.textures
        )
        let shaderLibraries = try makeShaderLibraries(
            shaders: resources.metalShaders,
            diagnostics: &diagnostics
        )
        let pipelineStates = try makePipelineStates(
            pipelines: resources.metalRenderPlan.pipelines,
            shaderLibraries: shaderLibraries,
            diagnostics: &diagnostics
        )
        let depthStencilStates = makeDepthStencilStates(
            pipelines: resources.metalRenderPlan.pipelines
        )
        let samplerState = makeSamplerState()

        return WallpaperEngineMetalCompiledScene(
            sourceTextures: sourceTextures,
            renderTargetTextures: renderTargetTextures,
            sourceSamplerStates: sourceSamplerStates,
            shaderLibraries: shaderLibraries,
            pipelineStates: pipelineStates,
            depthStencilStates: depthStencilStates,
            samplerState: samplerState,
            diagnostics: diagnostics
        )
    }

    private func makeSourceTextures(
        textureDescriptors: [WallpaperEngineMetalTextureDescriptor],
        textureInfos: [String: WallpaperEngineTextureInfo],
        diagnostics: inout [String]
    ) -> [String: MTLTexture] {
        var textures: [String: MTLTexture] = [:]

        for descriptor in textureDescriptors {
            guard let pixelFormat = metalPixelFormat(descriptor.pixelFormat) else {
                diagnostics.append("Cannot create source texture \(descriptor.key) for unsupported format \(descriptor.pixelFormat.rawValue).")
                continue
            }
            guard let textureInfo = textureInfos[descriptor.path] else {
                diagnostics.append("Cannot create source texture \(descriptor.key) because parsed texture info is missing.")
                continue
            }
            guard let texture = makeTexture(
                key: descriptor.key,
                width: descriptor.width,
                height: descriptor.height,
                mipmapLevelCount: descriptor.mipmapLevelCount,
                arrayLength: descriptor.imageCount,
                pixelFormat: pixelFormat,
                usage: descriptor.usage,
                storageMode: .shared,
                diagnostics: &diagnostics
            ) else {
                continue
            }

            uploadMipmaps(
                textureInfo.mipmaps,
                to: texture,
                pixelFormat: descriptor.pixelFormat,
                textureKey: descriptor.key,
                diagnostics: &diagnostics
            )
            textures[descriptor.key] = texture
        }

        return textures
    }

    private func makeSourceSamplerStates(
        textureDescriptors: [WallpaperEngineMetalTextureDescriptor]
    ) -> [String: MTLSamplerState] {
        var samplerStates: [String: MTLSamplerState] = [:]
        for descriptor in textureDescriptors {
            samplerStates[descriptor.key] = makeSamplerState(
                descriptor: descriptor.sampler,
                label: "sampler:\(descriptor.key)"
            )
        }
        return samplerStates
    }

    private func makeRenderTargetTextures(
        framebufferDescriptors: [WallpaperEngineMetalFramebufferDescriptor],
        diagnostics: inout [String]
    ) -> [String: MTLTexture] {
        var textures: [String: MTLTexture] = [:]

        for descriptor in framebufferDescriptors {
            guard let pixelFormat = metalPixelFormat(descriptor.pixelFormat) else {
                diagnostics.append("Cannot create render target \(descriptor.key) for unsupported format \(descriptor.pixelFormat.rawValue).")
                continue
            }
            guard let width = descriptor.width,
                  let height = descriptor.height else {
                diagnostics.append("Cannot create render target \(descriptor.key) because its size is unresolved.")
                continue
            }
            guard let texture = makeTexture(
                key: descriptor.key,
                width: width,
                height: height,
                mipmapLevelCount: 1,
                arrayLength: 1,
                pixelFormat: pixelFormat,
                usage: descriptor.usage,
                storageMode: .private,
                diagnostics: &diagnostics
            ) else {
                continue
            }
            textures[descriptor.key] = texture
        }

        return textures
    }

    private func makeTexture(
        key: String,
        width: Int,
        height: Int,
        mipmapLevelCount: Int,
        arrayLength: Int,
        pixelFormat: MTLPixelFormat,
        usage: [WallpaperEngineMetalTextureUsage],
        storageMode: MTLStorageMode,
        diagnostics: inout [String]
    ) -> MTLTexture? {
        guard width > 0, height > 0 else {
            diagnostics.append("Cannot create texture \(key) with invalid size \(width)x\(height).")
            return nil
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: mipmapLevelCount > 1
        )
        textureDescriptor.mipmapLevelCount = max(mipmapLevelCount, 1)
        textureDescriptor.textureType = arrayLength > 1 ? .type2DArray : .type2D
        textureDescriptor.arrayLength = max(arrayLength, 1)
        textureDescriptor.storageMode = storageMode
        textureDescriptor.usage = metalTextureUsage(usage)

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            diagnostics.append("Metal failed to allocate texture \(key).")
            return nil
        }

        return texture
    }

    private func uploadMipmaps(
        _ mipmaps: [WallpaperEngineTextureInfo.Mipmap],
        to texture: MTLTexture,
        pixelFormat: WallpaperEngineMetalPixelFormat,
        textureKey: String,
        diagnostics: inout [String]
    ) {
        guard let layout = textureLayout(pixelFormat) else {
            diagnostics.append("Cannot upload \(textureKey) because \(pixelFormat.rawValue) has no byte layout.")
            return
        }

        for mipmap in mipmaps {
            guard mipmap.imageIndex < texture.arrayLength,
                  mipmap.level < texture.mipmapLevelCount else {
                diagnostics.append("Skipping \(textureKey) mip \(mipmap.level) image \(mipmap.imageIndex) outside allocated texture bounds.")
                continue
            }

            let width = Int(mipmap.width)
            let height = Int(mipmap.height)
            let bytesPerRow = layout.bytesPerRow(width: width)
            let bytesPerImage = layout.bytesPerImage(width: width, height: height)
            guard mipmap.data.count >= bytesPerImage else {
                diagnostics.append("Skipping \(textureKey) mip \(mipmap.level) because \(mipmap.data.count) bytes is less than required \(bytesPerImage).")
                continue
            }

            mipmap.data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return
                }
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: mipmap.level,
                    slice: mipmap.imageIndex,
                    withBytes: baseAddress,
                    bytesPerRow: bytesPerRow,
                    bytesPerImage: bytesPerImage
                )
            }
        }
    }

    private func makeShaderLibraries(
        shaders: [WallpaperEngineMetalShader],
        diagnostics: inout [String]
    ) throws -> [String: MTLLibrary] {
        var libraries: [String: MTLLibrary] = [:]

        for shader in shaders {
            if !shader.diagnostics.isEmpty {
                diagnostics.append(contentsOf: shader.diagnostics.map { "\(shader.usage): \($0)" })
            }
            libraries[shader.usage] = try device.makeLibrary(source: shader.source, options: nil)
        }

        return libraries
    }

    private func makePipelineStates(
        pipelines: [WallpaperEngineMetalPipelineDescriptor],
        shaderLibraries: [String: MTLLibrary],
        diagnostics: inout [String]
    ) throws -> [String: MTLRenderPipelineState] {
        var pipelineStates: [String: MTLRenderPipelineState] = [:]

        for pipeline in pipelines {
            guard let library = shaderLibraries[pipeline.usage] else {
                diagnostics.append("Cannot create pipeline \(pipeline.id) because its Metal library is missing.")
                continue
            }
            guard let vertexFunction = library.makeFunction(name: pipeline.vertexFunctionName) else {
                diagnostics.append("Cannot create pipeline \(pipeline.id) because vertex function \(pipeline.vertexFunctionName) is missing.")
                continue
            }
            guard let fragmentFunction = library.makeFunction(name: pipeline.fragmentFunctionName) else {
                diagnostics.append("Cannot create pipeline \(pipeline.id) because fragment function \(pipeline.fragmentFunctionName) is missing.")
                continue
            }
            guard let colorPixelFormat = metalPixelFormat(pipeline.colorPixelFormat) else {
                diagnostics.append("Cannot create pipeline \(pipeline.id) for unsupported color format \(pipeline.colorPixelFormat.rawValue).")
                continue
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = pipeline.id
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.vertexDescriptor = makeVertexDescriptor()
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            applyBlendState(pipeline.blend, to: descriptor.colorAttachments[0])

            pipelineStates[pipeline.id] = try device.makeRenderPipelineState(descriptor: descriptor)
        }

        return pipelineStates
    }

    private func makeVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset = MemoryLayout<Float>.stride * 3
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<Float>.stride * 5
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }

    private func makeDepthStencilStates(
        pipelines: [WallpaperEngineMetalPipelineDescriptor]
    ) -> [String: MTLDepthStencilState] {
        var states: [String: MTLDepthStencilState] = [:]

        for pipeline in pipelines {
            let descriptor = MTLDepthStencilDescriptor()
            descriptor.depthCompareFunction = metalDepthCompareFunction(pipeline.depthStencil.depthCompareFunction)
            descriptor.isDepthWriteEnabled = pipeline.depthStencil.isDepthWriteEnabled
            states[pipeline.id] = device.makeDepthStencilState(descriptor: descriptor)
        }

        return states
    }

    private func makeSamplerState() -> MTLSamplerState {
        makeSamplerState(
            descriptor: WallpaperEngineMetalSamplerDescriptor(
                minFilter: .linear,
                magFilter: .linear,
                mipFilter: .notMipmapped,
                addressModeU: .clampToEdge,
                addressModeV: .clampToEdge
            ),
            label: "sampler:default"
        )
    }

    private func makeSamplerState(
        descriptor sampler: WallpaperEngineMetalSamplerDescriptor,
        label: String
    ) -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.label = label
        descriptor.minFilter = metalSamplerFilter(sampler.minFilter)
        descriptor.magFilter = metalSamplerFilter(sampler.magFilter)
        descriptor.mipFilter = metalSamplerMipFilter(sampler.mipFilter)
        descriptor.sAddressMode = metalSamplerAddressMode(sampler.addressModeU)
        descriptor.tAddressMode = metalSamplerAddressMode(sampler.addressModeV)
        descriptor.borderColor = .transparentBlack
        return device.makeSamplerState(descriptor: descriptor)!
    }

    private func applyBlendState(
        _ blend: WallpaperEngineMetalBlendState,
        to attachment: MTLRenderPipelineColorAttachmentDescriptor
    ) {
        attachment.isBlendingEnabled = blend.isEnabled
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = metalBlendFactor(blend.sourceRGBFactor)
        attachment.destinationRGBBlendFactor = metalBlendFactor(blend.destinationRGBFactor)
        attachment.sourceAlphaBlendFactor = metalBlendFactor(blend.sourceAlphaFactor)
        attachment.destinationAlphaBlendFactor = metalBlendFactor(blend.destinationAlphaFactor)
    }

    private func metalPixelFormat(_ pixelFormat: WallpaperEngineMetalPixelFormat) -> MTLPixelFormat? {
        switch pixelFormat {
        case .rgba8Unorm:
            return .rgba8Unorm
        case .bgra8Unorm:
            return .bgra8Unorm
        case .r8Unorm:
            return .r8Unorm
        case .rg8Unorm:
            return .rg8Unorm
        case .r16Float:
            return .r16Float
        case .rg16Float:
            return .rg16Float
        case .rgba16Float:
            return .rgba16Float
        case .bc1RGBA:
            return .bc1_rgba
        case .bc2RGBA:
            return .bc2_rgba
        case .bc3RGBA:
            return .bc3_rgba
        case .bc7RGBAUnorm:
            return .bc7_rgbaUnorm
        case .unsupported:
            return nil
        }
    }

    private func metalTextureUsage(_ usages: [WallpaperEngineMetalTextureUsage]) -> MTLTextureUsage {
        var result: MTLTextureUsage = []
        for usage in usages {
            switch usage {
            case .shaderRead:
                result.insert(.shaderRead)
            case .renderTarget:
                result.insert(.renderTarget)
            }
        }
        return result
    }

    private func metalSamplerFilter(_ filter: WallpaperEngineMetalSamplerFilter) -> MTLSamplerMinMagFilter {
        switch filter {
        case .nearest:
            return .nearest
        case .linear:
            return .linear
        }
    }

    private func metalSamplerMipFilter(_ filter: WallpaperEngineMetalSamplerMipFilter) -> MTLSamplerMipFilter {
        switch filter {
        case .notMipmapped:
            return .notMipmapped
        case .nearest:
            return .nearest
        case .linear:
            return .linear
        }
    }

    private func metalSamplerAddressMode(
        _ addressMode: WallpaperEngineMetalSamplerAddressMode
    ) -> MTLSamplerAddressMode {
        switch addressMode {
        case .repeat:
            return .repeat
        case .clampToEdge:
            return .clampToEdge
        case .clampToBorderColor:
            return .clampToBorderColor
        }
    }

    private func metalBlendFactor(_ factor: WallpaperEngineMetalBlendFactor) -> MTLBlendFactor {
        switch factor {
        case .zero:
            return .zero
        case .one:
            return .one
        case .sourceAlpha:
            return .sourceAlpha
        case .oneMinusSourceAlpha:
            return .oneMinusSourceAlpha
        }
    }

    private func metalDepthCompareFunction(
        _ compareFunction: WallpaperEngineMetalDepthCompareFunction
    ) -> MTLCompareFunction {
        switch compareFunction {
        case .always:
            return .always
        case .lessEqual:
            return .lessEqual
        }
    }

    private func textureLayout(
        _ pixelFormat: WallpaperEngineMetalPixelFormat
    ) -> WallpaperEngineMetalTextureByteLayout? {
        switch pixelFormat {
        case .r8Unorm:
            return WallpaperEngineMetalTextureByteLayout(bytesPerPixel: 1)
        case .rg8Unorm, .r16Float:
            return WallpaperEngineMetalTextureByteLayout(bytesPerPixel: 2)
        case .rgba8Unorm, .bgra8Unorm, .rg16Float:
            return WallpaperEngineMetalTextureByteLayout(bytesPerPixel: 4)
        case .rgba16Float:
            return WallpaperEngineMetalTextureByteLayout(bytesPerPixel: 8)
        case .bc1RGBA:
            return WallpaperEngineMetalTextureByteLayout(blockByteCount: 8)
        case .bc2RGBA, .bc3RGBA, .bc7RGBAUnorm:
            return WallpaperEngineMetalTextureByteLayout(blockByteCount: 16)
        case .unsupported:
            return nil
        }
    }
}

private struct WallpaperEngineMetalTextureByteLayout {
    let bytesPerPixel: Int?
    let blockByteCount: Int?

    init(bytesPerPixel: Int) {
        self.bytesPerPixel = bytesPerPixel
        self.blockByteCount = nil
    }

    init(blockByteCount: Int) {
        self.bytesPerPixel = nil
        self.blockByteCount = blockByteCount
    }

    func bytesPerRow(width: Int) -> Int {
        if let bytesPerPixel {
            return width * bytesPerPixel
        }
        return max(1, (width + 3) / 4) * (blockByteCount ?? 0)
    }

    func bytesPerImage(width: Int, height: Int) -> Int {
        if bytesPerPixel != nil {
            return bytesPerRow(width: width) * height
        }
        return bytesPerRow(width: width) * max(1, (height + 3) / 4)
    }
}
#endif
