import Foundation

struct WallpaperEngineMetalRenderPlan: Equatable, Sendable {
    let canvasSize: WallpaperEngineSceneVector2?
    let clearColor: WallpaperEngineSceneValue?
    let textures: [WallpaperEngineMetalTextureDescriptor]
    let framebuffers: [WallpaperEngineMetalFramebufferDescriptor]
    let pipelines: [WallpaperEngineMetalPipelineDescriptor]
    let draws: [WallpaperEngineMetalDrawCommand]
    let diagnostics: [String]
}

struct WallpaperEngineMetalTextureDescriptor: Equatable, Sendable {
    let key: String
    let path: String
    let width: Int
    let height: Int
    let realWidth: Int
    let realHeight: Int
    let pixelFormat: WallpaperEngineMetalPixelFormat
    let mipmapLevelCount: Int
    let imageCount: Int
    let sampler: WallpaperEngineMetalSamplerDescriptor
    let isAnimated: Bool
    let isVideoTexture: Bool
    let usage: [WallpaperEngineMetalTextureUsage]
    let diagnostics: [String]
}

struct WallpaperEngineMetalFramebufferDescriptor: Equatable, Sendable {
    let key: String
    let name: String
    let role: WallpaperEngineMetalFramebufferRole
    let objectID: Int?
    let objectSlot: WallpaperEngineObjectFramebufferSlot?
    let width: Int?
    let height: Int?
    let scale: Double
    let pixelFormat: WallpaperEngineMetalPixelFormat
    let usage: [WallpaperEngineMetalTextureUsage]
    let diagnostics: [String]
}

struct WallpaperEngineMetalPipelineDescriptor: Equatable, Sendable {
    let id: String
    let usage: String
    let shaderName: String
    let vertexFunctionName: String
    let fragmentFunctionName: String
    let colorPixelFormat: WallpaperEngineMetalPixelFormat
    let blend: WallpaperEngineMetalBlendState
    let depthStencil: WallpaperEngineMetalDepthStencilState
    let cullMode: WallpaperEngineMetalCullMode
    let diagnostics: [String]
}

struct WallpaperEngineMetalDrawCommand: Equatable, Sendable {
    let id: String
    let kind: WallpaperEngineRenderCommandKind
    let objectID: Int
    let objectName: String
    let targetTextureKey: String
    let pipelineID: String?
    let textureArguments: [WallpaperEngineMetalTextureArgument]
    let uniformArguments: [WallpaperEngineMetalUniformArgument]
    let diagnostics: [String]
}

struct WallpaperEngineMetalTextureArgument: Equatable, Sendable {
    let uniformName: String
    let index: Int?
    let textureKey: String?
    let source: WallpaperEngineShaderTextureBindingSource
    let diagnostics: [String]
}

struct WallpaperEngineMetalUniformArgument: Equatable, Sendable {
    let uniformName: String
    let valueType: String
    let value: WallpaperEngineSceneValue
    let source: WallpaperEngineShaderParameterBindingSource
}

enum WallpaperEngineMetalPixelFormat: String, Equatable, Sendable {
    case rgba8Unorm
    case bgra8Unorm
    case r8Unorm
    case rg8Unorm
    case r16Float
    case rg16Float
    case rgba16Float
    case bc1RGBA
    case bc2RGBA
    case bc3RGBA
    case bc7RGBAUnorm
    case unsupported
}

enum WallpaperEngineMetalTextureUsage: String, Equatable, Sendable {
    case shaderRead
    case renderTarget
}

struct WallpaperEngineMetalSamplerDescriptor: Equatable, Sendable {
    let minFilter: WallpaperEngineMetalSamplerFilter
    let magFilter: WallpaperEngineMetalSamplerFilter
    let mipFilter: WallpaperEngineMetalSamplerMipFilter
    let addressModeU: WallpaperEngineMetalSamplerAddressMode
    let addressModeV: WallpaperEngineMetalSamplerAddressMode
}

enum WallpaperEngineMetalSamplerFilter: String, Equatable, Sendable {
    case nearest
    case linear
}

enum WallpaperEngineMetalSamplerMipFilter: String, Equatable, Sendable {
    case notMipmapped
    case nearest
    case linear
}

enum WallpaperEngineMetalSamplerAddressMode: String, Equatable, Sendable {
    case `repeat`
    case clampToEdge
    case clampToBorderColor
}

enum WallpaperEngineMetalFramebufferRole: String, Equatable, Sendable {
    case scene
    case effect
    case object
}

struct WallpaperEngineMetalBlendState: Equatable, Sendable {
    let isEnabled: Bool
    let sourceRGBFactor: WallpaperEngineMetalBlendFactor
    let destinationRGBFactor: WallpaperEngineMetalBlendFactor
    let sourceAlphaFactor: WallpaperEngineMetalBlendFactor
    let destinationAlphaFactor: WallpaperEngineMetalBlendFactor
}

enum WallpaperEngineMetalBlendFactor: String, Equatable, Sendable {
    case zero
    case one
    case sourceAlpha
    case oneMinusSourceAlpha
}

struct WallpaperEngineMetalDepthStencilState: Equatable, Sendable {
    let depthCompareFunction: WallpaperEngineMetalDepthCompareFunction
    let isDepthWriteEnabled: Bool
}

enum WallpaperEngineMetalDepthCompareFunction: String, Equatable, Sendable {
    case always
    case lessEqual
}

enum WallpaperEngineMetalCullMode: String, Equatable, Sendable {
    case none
    case back
}

struct WallpaperEngineMetalRenderPlanBuilder {
    func buildPlan(
        commandPlan: WallpaperEngineSceneRenderCommandPlan,
        textures: [String: WallpaperEngineTextureInfo],
        metalShaders: [WallpaperEngineMetalShader]
    ) -> WallpaperEngineMetalRenderPlan {
        let textureDescriptors = textures.values
            .map(textureDescriptor)
            .sorted { $0.key < $1.key }
        let framebufferDescriptors = framebuffers(commandPlan: commandPlan)
        let shadersByUsage = Dictionary(
            metalShaders.map { ($0.usage, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let resourceSizes = resourceSizes(
            textureDescriptors: textureDescriptors,
            framebufferDescriptors: framebufferDescriptors
        )
        let resourceKeys = Set(resourceSizes.keys)
        let pipelines = pipelineDescriptors(
            commandPlan: commandPlan,
            shadersByUsage: shadersByUsage,
            framebufferDescriptors: framebufferDescriptors
        )
        let pipelineIDs = Set(pipelines.map(\.id))
        let draws = commandPlan.commands.map {
            drawCommand(
                command: $0,
                shadersByUsage: shadersByUsage,
                pipelineIDs: pipelineIDs,
                resourceKeys: resourceKeys,
                resourceSizes: resourceSizes,
                canvasSize: commandPlan.canvasSize
            )
        }
        let diagnostics = textureDescriptors.flatMap(\.diagnostics)
            + framebufferDescriptors.flatMap(\.diagnostics)
            + pipelines.flatMap(\.diagnostics)
            + draws.flatMap(\.diagnostics)

        return WallpaperEngineMetalRenderPlan(
            canvasSize: commandPlan.canvasSize,
            clearColor: commandPlan.clearColor,
            textures: textureDescriptors,
            framebuffers: framebufferDescriptors,
            pipelines: pipelines,
            draws: draws,
            diagnostics: diagnostics
        )
    }

    private func textureDescriptor(_ texture: WallpaperEngineTextureInfo) -> WallpaperEngineMetalTextureDescriptor {
        let pixelFormat = pixelFormat(for: texture.format)
        var diagnostics: [String] = []
        if pixelFormat == .unsupported {
            diagnostics.append("Texture \(texture.path) uses unsupported WE texture format \(texture.rawFormat).")
        }
        if texture.isVideoTexture {
            diagnostics.append("Texture \(texture.path) is a video texture and needs a runtime video-backed texture source.")
        }

        return WallpaperEngineMetalTextureDescriptor(
            key: textureKey(.asset(texture.path)),
            path: texture.path,
            width: Int(texture.textureWidth),
            height: Int(texture.textureHeight),
            realWidth: Int(texture.imageWidth),
            realHeight: Int(texture.imageHeight),
            pixelFormat: pixelFormat,
            mipmapLevelCount: mipmapLevelCount(for: texture),
            imageCount: Int(texture.imageCount),
            sampler: samplerDescriptor(for: texture),
            isAnimated: texture.isAnimated,
            isVideoTexture: texture.isVideoTexture,
            usage: [.shaderRead],
            diagnostics: diagnostics
        )
    }

    private func mipmapLevelCount(for texture: WallpaperEngineTextureInfo) -> Int {
        let mipmapsByImage = Dictionary(grouping: texture.mipmaps, by: \.imageIndex)
        let maxLevelCount = mipmapsByImage.values
            .compactMap { mipmaps in
                mipmaps.map(\.level).max().map { $0 + 1 }
            }
            .max() ?? 0
        return max(maxLevelCount, 1)
    }

    private func resourceSizes(
        textureDescriptors: [WallpaperEngineMetalTextureDescriptor],
        framebufferDescriptors: [WallpaperEngineMetalFramebufferDescriptor]
    ) -> [String: TextureResourceSize] {
        var sizes: [String: TextureResourceSize] = [:]
        for descriptor in textureDescriptors {
            sizes[descriptor.key] = TextureResourceSize(
                width: descriptor.width,
                height: descriptor.height,
                realWidth: descriptor.realWidth,
                realHeight: descriptor.realHeight
            )
        }
        for descriptor in framebufferDescriptors {
            sizes[descriptor.key] = TextureResourceSize(
                width: descriptor.width,
                height: descriptor.height,
                realWidth: descriptor.width,
                realHeight: descriptor.height
            )
        }
        return sizes
    }

    private func samplerDescriptor(
        for texture: WallpaperEngineTextureInfo
    ) -> WallpaperEngineMetalSamplerDescriptor {
        let mipmapLevelCount = mipmapLevelCount(for: texture)
        let noInterpolation = (texture.flags & WallpaperEngineTextureParser.Flags.noInterpolation) != 0
        let clampToEdge = (texture.flags & WallpaperEngineTextureParser.Flags.clampUVs) != 0
        let clampToBorder = (texture.flags & WallpaperEngineTextureParser.Flags.clampUVsBorder) != 0
        let filter: WallpaperEngineMetalSamplerFilter = noInterpolation ? .nearest : .linear
        let mipFilter: WallpaperEngineMetalSamplerMipFilter
        if mipmapLevelCount <= 1 {
            mipFilter = .notMipmapped
        } else {
            mipFilter = noInterpolation ? .nearest : .linear
        }
        let addressMode: WallpaperEngineMetalSamplerAddressMode
        if clampToBorder {
            addressMode = .clampToBorderColor
        } else if clampToEdge {
            addressMode = .clampToEdge
        } else {
            addressMode = .repeat
        }

        return WallpaperEngineMetalSamplerDescriptor(
            minFilter: filter,
            magFilter: filter,
            mipFilter: mipFilter,
            addressModeU: addressMode,
            addressModeV: addressMode
        )
    }

    private func framebuffers(
        commandPlan: WallpaperEngineSceneRenderCommandPlan
    ) -> [WallpaperEngineMetalFramebufferDescriptor] {
        var descriptors: [String: WallpaperEngineMetalFramebufferDescriptor] = [:]
        let framebufferFormats = Dictionary(
            commandPlan.framebuffers.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let sceneFramebuffer = framebufferFormats[commandPlan.sceneFramebuffer]
        descriptors[framebufferKey(commandPlan.sceneFramebuffer)] = framebufferDescriptor(
            name: commandPlan.sceneFramebuffer,
            role: .scene,
            objectID: nil,
            objectSlot: nil,
            size: commandPlan.canvasSize,
            scale: sceneFramebuffer?.scale ?? 1,
            format: sceneFramebuffer?.format ?? "rgba8888"
        )

        for framebuffer in commandPlan.framebuffers where framebuffer.name != commandPlan.sceneFramebuffer {
            descriptors[framebufferKey(framebuffer.name)] = framebufferDescriptor(
                name: framebuffer.name,
                role: .effect,
                objectID: nil,
                objectSlot: nil,
                size: scaledSize(commandPlan.canvasSize, scale: framebuffer.scale),
                scale: framebuffer.scale,
                format: framebuffer.format
            )
        }

        for objectFramebuffer in commandPlan.objectFramebuffers {
            let key = objectFramebufferKey(
                objectID: objectFramebuffer.objectID,
                slot: objectFramebuffer.slot
            )
            descriptors[key] = framebufferDescriptor(
                name: key,
                role: .object,
                objectID: objectFramebuffer.objectID,
                objectSlot: objectFramebuffer.slot,
                size: objectFramebuffer.size ?? commandPlan.canvasSize,
                scale: 1,
                format: "rgba8888"
            )
        }

        return descriptors.values.sorted { $0.key < $1.key }
    }

    private func framebufferDescriptor(
        name: String,
        role: WallpaperEngineMetalFramebufferRole,
        objectID: Int?,
        objectSlot: WallpaperEngineObjectFramebufferSlot?,
        size: WallpaperEngineSceneVector2?,
        scale: Double,
        format: String
    ) -> WallpaperEngineMetalFramebufferDescriptor {
        let resolvedFormat = pixelFormat(forFramebufferFormat: format)
        var diagnostics: [String] = []
        if resolvedFormat == .unsupported {
            diagnostics.append("Framebuffer \(name) uses unsupported WE framebuffer format \(format).")
        }
        if size == nil {
            diagnostics.append("Framebuffer \(name) has no resolved size.")
        }

        return WallpaperEngineMetalFramebufferDescriptor(
            key: objectID.map { objectFramebufferKey(objectID: $0, slot: objectSlot ?? .main) } ?? framebufferKey(name),
            name: name,
            role: role,
            objectID: objectID,
            objectSlot: objectSlot,
            width: size.map { max(Int($0.x.rounded()), 1) },
            height: size.map { max(Int($0.y.rounded()), 1) },
            scale: scale,
            pixelFormat: resolvedFormat == .unsupported ? .rgba8Unorm : resolvedFormat,
            usage: [.renderTarget, .shaderRead],
            diagnostics: diagnostics
        )
    }

    private func pipelineDescriptors(
        commandPlan: WallpaperEngineSceneRenderCommandPlan,
        shadersByUsage: [String: WallpaperEngineMetalShader],
        framebufferDescriptors: [WallpaperEngineMetalFramebufferDescriptor]
    ) -> [WallpaperEngineMetalPipelineDescriptor] {
        let framebuffersByKey = Dictionary(
            framebufferDescriptors.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return commandPlan.commands.compactMap { command in
            guard let shader = shadersByUsage[command.usage],
                  let binding = command.shaderBinding else {
                return nil
            }

            let targetKey = textureKey(command.target)
            let colorFormat = framebuffersByKey[targetKey]?.pixelFormat ?? .rgba8Unorm
            let blend = blendState(for: binding.renderState.blending)
            let depth = depthStencilState(for: binding.renderState)
            let cull = cullMode(for: binding.renderState.cullMode)

            return WallpaperEngineMetalPipelineDescriptor(
                id: pipelineID(for: command.usage),
                usage: command.usage,
                shaderName: shader.shaderName,
                vertexFunctionName: shader.vertexFunctionName,
                fragmentFunctionName: shader.fragmentFunctionName,
                colorPixelFormat: colorFormat,
                blend: blend.state,
                depthStencil: depth.state,
                cullMode: cull.mode,
                diagnostics: shader.diagnostics + blend.diagnostics + depth.diagnostics + cull.diagnostics
            )
        }
        .sorted { $0.id < $1.id }
    }

    private func drawCommand(
        command: WallpaperEngineRenderCommand,
        shadersByUsage: [String: WallpaperEngineMetalShader],
        pipelineIDs: Set<String>,
        resourceKeys: Set<String>,
        resourceSizes: [String: TextureResourceSize],
        canvasSize: WallpaperEngineSceneVector2?
    ) -> WallpaperEngineMetalDrawCommand {
        let targetKey = textureKey(command.target)
        let pipelineID = pipelineID(for: command.usage)
        let hasPipeline = pipelineIDs.contains(pipelineID)
        let shader = shadersByUsage[command.usage]
        var diagnostics: [String] = []
        if command.shaderBinding == nil {
            diagnostics.append("Draw \(command.id) has no resolved shader binding.")
        }
        if shader == nil {
            diagnostics.append("Draw \(command.id) has no translated Metal shader.")
        }
        if !hasPipeline {
            diagnostics.append("Draw \(command.id) has no executable Metal pipeline.")
        }

        let textureArguments = command.shaderBinding?.textures.map {
            textureArgument(binding: $0, command: command, resourceKeys: resourceKeys)
        } ?? []
        diagnostics.append(contentsOf: textureArguments.flatMap(\.diagnostics))

        let parameterUniformArguments = command.shaderBinding?.parameters.map {
            WallpaperEngineMetalUniformArgument(
                uniformName: $0.uniformName,
                valueType: $0.valueType,
                value: $0.value,
                source: $0.source
            )
        } ?? []
        let uniformArguments = parameterUniformArguments + builtinUniformArguments(
            shader: shader,
            textureArguments: textureArguments,
            resourceSizes: resourceSizes,
            canvasSize: canvasSize,
            diagnostics: &diagnostics
        )

        return WallpaperEngineMetalDrawCommand(
            id: command.id,
            kind: command.kind,
            objectID: command.objectID,
            objectName: command.objectName,
            targetTextureKey: targetKey,
            pipelineID: hasPipeline ? pipelineID : nil,
            textureArguments: textureArguments,
            uniformArguments: uniformArguments,
            diagnostics: diagnostics
        )
    }

    private func builtinUniformArguments(
        shader: WallpaperEngineMetalShader?,
        textureArguments: [WallpaperEngineMetalTextureArgument],
        resourceSizes: [String: TextureResourceSize],
        canvasSize: WallpaperEngineSceneVector2?,
        diagnostics: inout [String]
    ) -> [WallpaperEngineMetalUniformArgument] {
        guard let shader else {
            return []
        }

        let texturesByIndex = Dictionary(
            textureArguments.compactMap { argument -> (Int, WallpaperEngineMetalTextureArgument)? in
                guard let index = argument.index else {
                    return nil
                }
                return (index, argument)
            },
            uniquingKeysWith: { first, _ in first }
        )

        return shader.builtinUniforms.compactMap { builtinUniform in
            switch builtinUniform.kind {
            case .time:
                return WallpaperEngineMetalUniformArgument(
                    uniformName: builtinUniform.uniformName,
                    valueType: builtinUniform.valueType,
                    value: .double(0),
                    source: .time
                )
            case .daytime:
                return WallpaperEngineMetalUniformArgument(
                    uniformName: builtinUniform.uniformName,
                    valueType: builtinUniform.valueType,
                    value: .double(0),
                    source: .daytime
                )
            case .modelViewProjectionMatrix:
                return WallpaperEngineMetalUniformArgument(
                    uniformName: builtinUniform.uniformName,
                    valueType: builtinUniform.valueType,
                    value: .array([
                        .double(1), .double(0), .double(0), .double(0),
                        .double(0), .double(1), .double(0), .double(0),
                        .double(0), .double(0), .double(1), .double(0),
                        .double(0), .double(0), .double(0), .double(1)
                    ]),
                    source: .modelViewProjectionMatrix
                )
            case .textureReductionScale:
                return WallpaperEngineMetalUniformArgument(
                    uniformName: builtinUniform.uniformName,
                    valueType: builtinUniform.valueType,
                    value: .double(1),
                    source: .textureReductionScale
                )
            case .textureResolution:
                guard let textureIndex = builtinUniform.textureIndex,
                      let textureKey = texturesByIndex[textureIndex]?.textureKey else {
                    diagnostics.append("Builtin uniform \(builtinUniform.uniformName) has no bound texture index.")
                    return nil
                }
                guard let size = resourceSizes[textureKey],
                      let width = size.width,
                      let height = size.height,
                      let realWidth = size.realWidth,
                      let realHeight = size.realHeight else {
                    diagnostics.append("Builtin uniform \(builtinUniform.uniformName) cannot resolve size for texture \(textureKey).")
                    return nil
                }
                return WallpaperEngineMetalUniformArgument(
                    uniformName: builtinUniform.uniformName,
                    valueType: builtinUniform.valueType,
                    value: .vector4(WallpaperEngineSceneVector4(
                        x: Double(width),
                        y: Double(height),
                        z: Double(realWidth),
                        w: Double(realHeight)
                    )),
                    source: .textureResolution
                )
            case .textureRotation:
                return WallpaperEngineMetalUniformArgument(
                    uniformName: builtinUniform.uniformName,
                    valueType: builtinUniform.valueType,
                    value: .vector4(WallpaperEngineSceneVector4(x: 0, y: 0, z: 0, w: 0)),
                    source: .textureTransform
                )
            case .textureTranslation:
                return WallpaperEngineMetalUniformArgument(
                    uniformName: builtinUniform.uniformName,
                    valueType: builtinUniform.valueType,
                    value: .vector2(WallpaperEngineSceneVector2(x: 0, y: 0)),
                    source: .textureTransform
                )
            case .texelSize:
                return texelUniformArgument(
                    builtinUniform,
                    canvasSize: canvasSize,
                    scale: 1,
                    source: .texelSize,
                    diagnostics: &diagnostics
                )
            case .texelSizeHalf:
                return texelUniformArgument(
                    builtinUniform,
                    canvasSize: canvasSize,
                    scale: 0.5,
                    source: .texelSizeHalf,
                    diagnostics: &diagnostics
                )
            }
        }
    }

    private func texelUniformArgument(
        _ builtinUniform: WallpaperEngineMetalBuiltinUniform,
        canvasSize: WallpaperEngineSceneVector2?,
        scale: Double,
        source: WallpaperEngineShaderParameterBindingSource,
        diagnostics: inout [String]
    ) -> WallpaperEngineMetalUniformArgument? {
        guard let canvasSize, canvasSize.x > 0, canvasSize.y > 0 else {
            diagnostics.append("Builtin uniform \(builtinUniform.uniformName) cannot resolve texel size without a positive canvas size.")
            return nil
        }
        return WallpaperEngineMetalUniformArgument(
            uniformName: builtinUniform.uniformName,
            valueType: builtinUniform.valueType,
            value: .vector2(WallpaperEngineSceneVector2(
                x: scale / canvasSize.x,
                y: scale / canvasSize.y
            )),
            source: source
        )
    }

    private func textureArgument(
        binding: WallpaperEngineShaderTextureBinding,
        command: WallpaperEngineRenderCommand,
        resourceKeys: Set<String>
    ) -> WallpaperEngineMetalTextureArgument {
        let resolvedKey = binding.reference.flatMap {
            textureKey(reference: $0, command: command)
        }
        var diagnostics: [String] = []
        if binding.reference == nil {
            diagnostics.append("Texture \(binding.uniformName) has no resolved texture reference.")
        }
        if let resolvedKey, !resourceKeys.contains(resolvedKey) {
            diagnostics.append("Texture \(binding.uniformName) resolves to missing resource \(resolvedKey).")
        }

        return WallpaperEngineMetalTextureArgument(
            uniformName: binding.uniformName,
            index: binding.index,
            textureKey: resolvedKey,
            source: binding.source,
            diagnostics: diagnostics
        )
    }

    private func textureKey(
        reference: WallpaperEngineRenderTextureReference,
        command: WallpaperEngineRenderCommand
    ) -> String? {
        switch reference {
        case .previous:
            return (command.previousInput ?? command.input).flatMap(textureKey)
        case .asset, .framebuffer, .alias, .named:
            return textureKey(reference)
        }
    }

    private func textureKey(_ texture: WallpaperEngineRenderCommandTexture) -> String? {
        switch texture {
        case .asset(let path):
            return textureKey(.asset(path))
        case .framebuffer(let name), .alias(let name), .named(let name):
            return framebufferKey(name)
        case .objectFramebuffer(let objectID, let slot):
            return objectFramebufferKey(objectID: objectID, slot: slot)
        case .previous:
            return nil
        }
    }

    private func textureKey(_ reference: WallpaperEngineRenderTextureReference) -> String {
        switch reference {
        case .asset(let path):
            return "asset:\(path)"
        case .framebuffer(let name), .alias(let name), .named(let name):
            return framebufferKey(name)
        case .previous:
            return "previous"
        }
    }

    private func textureKey(_ target: WallpaperEngineRenderCommandTarget) -> String {
        switch target {
        case .framebuffer(let name):
            return framebufferKey(name)
        case .objectFramebuffer(let objectID, let slot):
            return objectFramebufferKey(objectID: objectID, slot: slot)
        }
    }

    private func framebufferKey(_ name: String) -> String {
        "framebuffer:\(name)"
    }

    private func objectFramebufferKey(objectID: Int, slot: WallpaperEngineObjectFramebufferSlot) -> String {
        "object:\(objectID):\(slot.rawValue)"
    }

    private func pipelineID(for usage: String) -> String {
        "pipeline:\(usage)"
    }

    private func scaledSize(
        _ size: WallpaperEngineSceneVector2?,
        scale: Double
    ) -> WallpaperEngineSceneVector2? {
        guard let size else {
            return nil
        }
        return WallpaperEngineSceneVector2(
            x: size.x * scale,
            y: size.y * scale
        )
    }

    private func pixelFormat(for format: WallpaperEngineTextureInfo.Format) -> WallpaperEngineMetalPixelFormat {
        switch format {
        case .argb8888:
            return .bgra8Unorm
        case .rgb888, .rgb565, .rgba1010102:
            return .rgba8Unorm
        case .dxt1:
            return .bc1RGBA
        case .dxt3:
            return .bc2RGBA
        case .dxt5:
            return .bc3RGBA
        case .rg88:
            return .rg8Unorm
        case .r8:
            return .r8Unorm
        case .rg1616f:
            return .rg16Float
        case .r16f:
            return .r16Float
        case .rgba16161616f, .rgb161616f:
            return .rgba16Float
        case .bc7:
            return .bc7RGBAUnorm
        case .unknown:
            return .unsupported
        }
    }

    private func pixelFormat(forFramebufferFormat format: String) -> WallpaperEngineMetalPixelFormat {
        switch format.normalizedWallpaperEnginePath {
        case "rgba8888", "rgba8", "rgba":
            return .rgba8Unorm
        case "bgra8888", "bgra8", "argb8888":
            return .bgra8Unorm
        case "r8":
            return .r8Unorm
        case "rg88", "rg8":
            return .rg8Unorm
        case "r16f":
            return .r16Float
        case "rg1616f", "rg16f":
            return .rg16Float
        case "rgba16161616f", "rgba16f":
            return .rgba16Float
        default:
            return .unsupported
        }
    }

    private func blendState(
        for rawValue: String
    ) -> (state: WallpaperEngineMetalBlendState, diagnostics: [String]) {
        switch rawValue.lowercased() {
        case "normal":
            return (
                WallpaperEngineMetalBlendState(
                    isEnabled: true,
                    sourceRGBFactor: .one,
                    destinationRGBFactor: .zero,
                    sourceAlphaFactor: .one,
                    destinationAlphaFactor: .zero
                ),
                []
            )
        case "translucent":
            return (
                WallpaperEngineMetalBlendState(
                    isEnabled: true,
                    sourceRGBFactor: .sourceAlpha,
                    destinationRGBFactor: .oneMinusSourceAlpha,
                    sourceAlphaFactor: .sourceAlpha,
                    destinationAlphaFactor: .oneMinusSourceAlpha
                ),
                []
            )
        case "additive":
            return (
                WallpaperEngineMetalBlendState(
                    isEnabled: true,
                    sourceRGBFactor: .sourceAlpha,
                    destinationRGBFactor: .one,
                    sourceAlphaFactor: .sourceAlpha,
                    destinationAlphaFactor: .one
                ),
                []
            )
        default:
            return (
                WallpaperEngineMetalBlendState(
                    isEnabled: true,
                    sourceRGBFactor: .one,
                    destinationRGBFactor: .zero,
                    sourceAlphaFactor: .one,
                    destinationAlphaFactor: .zero
                ),
                ["Unknown WE blend mode \(rawValue); defaulted to normal."]
            )
        }
    }

    private func depthStencilState(
        for renderState: WallpaperEngineMaterialRenderState
    ) -> (state: WallpaperEngineMetalDepthStencilState, diagnostics: [String]) {
        var diagnostics: [String] = []
        let compareFunction: WallpaperEngineMetalDepthCompareFunction
        switch renderState.depthTest.lowercased() {
        case "enabled":
            compareFunction = .lessEqual
        case "disabled":
            compareFunction = .always
        default:
            compareFunction = .always
            diagnostics.append("Unknown WE depthtest mode \(renderState.depthTest); defaulted to disabled.")
        }

        let isDepthWriteEnabled: Bool
        switch renderState.depthWrite.lowercased() {
        case "enabled":
            isDepthWriteEnabled = true
        case "disabled":
            isDepthWriteEnabled = false
        default:
            isDepthWriteEnabled = false
            diagnostics.append("Unknown WE depthwrite mode \(renderState.depthWrite); defaulted to disabled.")
        }

        return (
            WallpaperEngineMetalDepthStencilState(
                depthCompareFunction: compareFunction,
                isDepthWriteEnabled: isDepthWriteEnabled
            ),
            diagnostics
        )
    }

    private func cullMode(
        for rawValue: String
    ) -> (mode: WallpaperEngineMetalCullMode, diagnostics: [String]) {
        switch rawValue.lowercased() {
        case "normal":
            return (.back, [])
        case "nocull":
            return (.none, [])
        default:
            return (.none, ["Unknown WE cullmode \(rawValue); defaulted to nocull."])
        }
    }
}

private struct TextureResourceSize {
    let width: Int?
    let height: Int?
    let realWidth: Int?
    let realHeight: Int?
}
