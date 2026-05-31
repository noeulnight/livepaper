import Foundation

struct WallpaperEngineShaderBindingPlan: Equatable, Sendable {
    let usage: String
    let shaderName: String
    let materialPath: String?
    let overrideID: Int?
    let renderState: WallpaperEngineMaterialRenderState
    let combos: [String: Int]
    let textures: [WallpaperEngineShaderTextureBinding]
    let parameters: [WallpaperEngineShaderParameterBinding]
}

struct WallpaperEngineMaterialRenderState: Equatable, Sendable {
    let blending: String
    let cullMode: String
    let depthTest: String
    let depthWrite: String
}

struct WallpaperEngineShaderTextureBinding: Equatable, Sendable {
    let uniformName: String
    let index: Int?
    let samplerType: String
    let materialName: String?
    let reference: WallpaperEngineRenderTextureReference?
    let source: WallpaperEngineShaderTextureBindingSource
    let defaultTexture: String?
}

enum WallpaperEngineShaderTextureBindingSource: String, Equatable, Sendable {
    case effectBind
    case materialTexture
    case userTexture
    case shaderDefault
    case missing
}

struct WallpaperEngineShaderParameterBinding: Equatable, Sendable {
    let uniformName: String
    let valueType: String
    let materialName: String?
    let value: WallpaperEngineSceneValue
    let source: WallpaperEngineShaderParameterBindingSource
}

enum WallpaperEngineShaderParameterBindingSource: String, Equatable, Sendable {
    case daytime
    case materialConstant
    case shaderDefault
    case implicitDefault
    case modelViewProjectionMatrix
    case time
    case texelSize
    case texelSizeHalf
    case textureReductionScale
    case textureResolution
    case textureTransform
}

struct WallpaperEngineShaderBindingPlanner {
    func buildBindings(
        plan: WallpaperEngineSceneRenderPlan,
        shaders: [String: WallpaperEngineResolvedShader],
        shaderIncludes: [String: WallpaperEngineResolvedShaderInclude]
    ) -> [WallpaperEngineShaderBindingPlan] {
        materialContexts(in: plan).compactMap { context in
            guard let shader = shaders[context.materialPass.shader] else {
                return nil
            }
            return buildBinding(
                context: context,
                shader: shader,
                shaderIncludes: shaderIncludes
            )
        }
    }

    private func buildBinding(
        context: MaterialPassContext,
        shader: WallpaperEngineResolvedShader,
        shaderIncludes: [String: WallpaperEngineResolvedShaderInclude]
    ) -> WallpaperEngineShaderBindingPlan {
        let metadata = shaderMetadata(for: shader, shaderIncludes: shaderIncludes)
        return WallpaperEngineShaderBindingPlan(
            usage: context.usage,
            shaderName: shader.name,
            materialPath: context.materialPass.materialPath,
            overrideID: context.materialPass.overrideID,
            renderState: WallpaperEngineMaterialRenderState(
                blending: context.materialPass.blending,
                cullMode: context.materialPass.cullMode,
                depthTest: context.materialPass.depthTest,
                depthWrite: context.materialPass.depthWrite
            ),
            combos: context.materialPass.combos,
            textures: textureBindings(
                metadata: metadata,
                materialPass: context.materialPass,
                effectBinds: context.effectBinds
            ),
            parameters: parameterBindings(
                metadata: metadata,
                materialPass: context.materialPass
            )
        )
    }

    private func shaderMetadata(
        for shader: WallpaperEngineResolvedShader,
        shaderIncludes: [String: WallpaperEngineResolvedShaderInclude]
    ) -> [WallpaperEngineShaderMetadata] {
        var result = [shader.vertexMetadata, shader.fragmentMetadata].compactMap { $0 }
        let includePaths = result.flatMap(\.includes)
        var visited = Set<String>()

        func appendInclude(_ path: String) {
            let normalized = path.normalizedWallpaperEnginePath
            guard !visited.contains(normalized),
                  let include = shaderIncludes[normalized] else {
                return
            }
            visited.insert(normalized)
            result.append(include.metadata)
            for nestedInclude in include.metadata.includes {
                appendInclude(nestedInclude)
            }
        }

        for includePath in includePaths {
            appendInclude(includePath)
        }
        return result
    }

    private func textureBindings(
        metadata: [WallpaperEngineShaderMetadata],
        materialPass: WallpaperEngineMaterialPassRenderPlan,
        effectBinds: [WallpaperEngineRenderTextureBinding]
    ) -> [WallpaperEngineShaderTextureBinding] {
        let textures = uniqueTextures(metadata.flatMap(\.textures))
        let texturesByIndex = Dictionary(
            textures.compactMap { texture -> (Int, WallpaperEngineShaderTexture)? in
                texture.index.map { ($0, texture) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let explicitBindings = explicitTextureBindings(materialPass: materialPass, effectBinds: effectBinds)
        let allIndices = Set(texturesByIndex.keys)
            .union(explicitBindings.keys)
            .sorted()

        var bindings = allIndices.map { index -> WallpaperEngineShaderTextureBinding in
            let texture = texturesByIndex[index]
            let explicit = explicitBindings[index]
            let fallback = texture?.defaultTexture.map {
                WallpaperEngineBoundTexture(
                    reference: .asset(defaultTexturePath($0)),
                    source: .shaderDefault
                )
            }
            let bound = explicit ?? fallback
            return WallpaperEngineShaderTextureBinding(
                uniformName: texture?.uniformName ?? "g_Texture\(index)",
                index: index,
                samplerType: texture?.samplerType ?? "sampler2D",
                materialName: texture?.materialName,
                reference: bound?.reference,
                source: bound?.source ?? .missing,
                defaultTexture: texture?.defaultTexture
            )
        }

        let nonIndexedTextures = textures
            .filter { $0.index == nil }
            .map {
                WallpaperEngineShaderTextureBinding(
                    uniformName: $0.uniformName,
                    index: nil,
                    samplerType: $0.samplerType,
                    materialName: $0.materialName,
                    reference: nil,
                    source: .missing,
                    defaultTexture: $0.defaultTexture
                )
            }
        bindings.append(contentsOf: nonIndexedTextures)
        return bindings.sorted { lhs, rhs in
            switch (lhs.index, rhs.index) {
            case let (.some(leftIndex), .some(rightIndex)):
                return leftIndex == rightIndex
                    ? lhs.uniformName < rhs.uniformName
                    : leftIndex < rightIndex
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.uniformName < rhs.uniformName
            }
        }
    }

    private func parameterBindings(
        metadata: [WallpaperEngineShaderMetadata],
        materialPass: WallpaperEngineMaterialPassRenderPlan
    ) -> [WallpaperEngineShaderParameterBinding] {
        uniqueParameters(metadata.flatMap(\.parameters)).map { parameter in
            let resolved = parameterValue(parameter, constants: materialPass.constants)
            return WallpaperEngineShaderParameterBinding(
                uniformName: parameter.uniformName,
                valueType: parameter.valueType,
                materialName: parameter.materialName,
                value: resolved.value,
                source: resolved.source
            )
        }
    }

    private func explicitTextureBindings(
        materialPass: WallpaperEngineMaterialPassRenderPlan,
        effectBinds: [WallpaperEngineRenderTextureBinding]
    ) -> [Int: WallpaperEngineBoundTexture] {
        var bindings: [Int: WallpaperEngineBoundTexture] = [:]
        for binding in materialPass.textures {
            bindings[binding.index] = WallpaperEngineBoundTexture(
                reference: binding.reference,
                source: .materialTexture
            )
        }
        for binding in materialPass.userTextures {
            bindings[binding.index] = WallpaperEngineBoundTexture(
                reference: binding.reference,
                source: .userTexture
            )
        }
        for binding in effectBinds {
            bindings[binding.index] = WallpaperEngineBoundTexture(
                reference: binding.reference,
                source: .effectBind
            )
        }
        return bindings
    }

    private func parameterValue(
        _ parameter: WallpaperEngineShaderParameter,
        constants: [String: WallpaperEngineSceneValue]
    ) -> (value: WallpaperEngineSceneValue, source: WallpaperEngineShaderParameterBindingSource) {
        let candidateKeys = [
            parameter.materialName,
            parameter.uniformName,
            strippedUniformName(parameter.uniformName)
        ].compactMap { $0 }

        for key in candidateKeys {
            if let value = constants[key] {
                return (value, .materialConstant)
            }
        }
        if let defaultValue = parameter.defaultValue {
            return (defaultValue, .shaderDefault)
        }
        return (implicitDefault(for: parameter.valueType), .implicitDefault)
    }

    private func strippedUniformName(_ uniformName: String) -> String? {
        guard uniformName.hasPrefix("g_") else {
            return nil
        }
        let stripped = uniformName.dropFirst(2)
        guard let first = stripped.first else {
            return nil
        }
        return String(first).lowercased() + String(stripped.dropFirst())
    }

    private func implicitDefault(for valueType: String) -> WallpaperEngineSceneValue {
        switch valueType.lowercased() {
        case "bool":
            return .bool(false)
        case "int", "uint":
            return .int(0)
        case "vec2", "float2":
            return .vector2(WallpaperEngineSceneVector2(x: 0, y: 0))
        case "vec3", "float3":
            return .vector3(WallpaperEngineSceneVector3(x: 0, y: 0, z: 0))
        case "vec4", "float4":
            return .vector4(WallpaperEngineSceneVector4(x: 0, y: 0, z: 0, w: 0))
        default:
            return .double(0)
        }
    }

    private func uniqueTextures(_ textures: [WallpaperEngineShaderTexture]) -> [WallpaperEngineShaderTexture] {
        var seen = Set<String>()
        return textures.filter {
            let key = $0.index.map { "index:\($0)" } ?? "uniform:\($0.uniformName)"
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func uniqueParameters(_ parameters: [WallpaperEngineShaderParameter]) -> [WallpaperEngineShaderParameter] {
        var seen = Set<String>()
        return parameters.filter {
            guard !seen.contains($0.uniformName) else {
                return false
            }
            seen.insert($0.uniformName)
            return true
        }
    }

    private func defaultTexturePath(_ textureName: String) -> String {
        let normalized = textureName.normalizedWallpaperEnginePath
        if normalized.wallpaperEnginePathExtension == "tex" {
            return normalized
        }
        return "materials/\(normalized).tex"
    }

    private func materialContexts(in plan: WallpaperEngineSceneRenderPlan) -> [MaterialPassContext] {
        plan.objects.flatMap { object -> [MaterialPassContext] in
            switch object.payload {
            case .image(let image):
                let baseContexts = image.basePasses.enumerated().map { index, materialPass in
                    MaterialPassContext(
                        usage: "object:\(object.id):image:base:\(index)",
                        materialPass: materialPass,
                        effectBinds: []
                    )
                }
                let effectContexts = image.effects.flatMap { effect in
                    effect.passes.compactMap { effectPass -> MaterialPassContext? in
                        guard let materialPass = effectPass.materialPass else {
                            return nil
                        }
                        return MaterialPassContext(
                            usage: "object:\(object.id):image:effect:\(effect.id):pass:\(effectPass.effectPassIndex):material:\(effectPass.materialPassIndex ?? 0)",
                            materialPass: materialPass,
                            effectBinds: effectPass.binds
                        )
                    }
                }
                return baseContexts + effectContexts
            case .particle(let particle):
                return particle.materialPasses.enumerated().map { index, materialPass in
                    MaterialPassContext(
                        usage: "object:\(object.id):particle:material:\(index)",
                        materialPass: materialPass,
                        effectBinds: []
                    )
                }
            case .sound, .text, .unsupported:
                return []
            }
        }
    }
}

private struct MaterialPassContext {
    let usage: String
    let materialPass: WallpaperEngineMaterialPassRenderPlan
    let effectBinds: [WallpaperEngineRenderTextureBinding]
}

private struct WallpaperEngineBoundTexture {
    let reference: WallpaperEngineRenderTextureReference
    let source: WallpaperEngineShaderTextureBindingSource
}
