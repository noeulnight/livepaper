import Foundation

struct WallpaperEngineResolvedSceneResources: Equatable, Sendable {
    let assets: [String: Data]
    let textures: [String: WallpaperEngineTextureInfo]
    let shaders: [String: WallpaperEngineResolvedShader]
    let shaderIncludes: [String: WallpaperEngineResolvedShaderInclude]
    let preparedShaders: [WallpaperEnginePreparedShader]
    let shaderBindings: [WallpaperEngineShaderBindingPlan]
    let metalShaders: [WallpaperEngineMetalShader]
    let renderCommandPlan: WallpaperEngineSceneRenderCommandPlan
    let metalRenderPlan: WallpaperEngineMetalRenderPlan
    let missingAssets: [String]
    let textureParseFailures: [WallpaperEngineResolvedResourceFailure]
    let unresolvedShaders: [String]
    let unresolvedShaderIncludes: [String]
}

struct WallpaperEngineResolvedShader: Equatable, Sendable {
    let name: String
    let vertexPath: String?
    let fragmentPath: String?
    let vertexSource: String?
    let fragmentSource: String?
    let vertexMetadata: WallpaperEngineShaderMetadata?
    let fragmentMetadata: WallpaperEngineShaderMetadata?

    var isComplete: Bool {
        vertexSource != nil && fragmentSource != nil
    }

    var defaultTextures: [Int: String] {
        let shaderTextures = (vertexMetadata?.textures ?? []) + (fragmentMetadata?.textures ?? [])
        let texturePairs = shaderTextures
            .compactMap { texture -> (Int, String)? in
                guard let index = texture.index,
                      let defaultTexture = texture.defaultTexture else {
                    return nil
                }
                return (index, defaultTexture)
            }
        return Dictionary(texturePairs, uniquingKeysWith: { _, fragment in fragment })
    }
}

struct WallpaperEngineResolvedResourceFailure: Equatable, Sendable {
    let path: String
    let reason: String
}

struct WallpaperEngineResolvedShaderInclude: Equatable, Sendable {
    let requestedPath: String
    let resolvedPath: String
    let source: String
    let metadata: WallpaperEngineShaderMetadata
}

struct WallpaperEngineSceneResourceResolver {
    private let assetStore: WallpaperEngineSceneAssetStore
    private let textureParser: WallpaperEngineTextureParser
    private let shaderParser: WallpaperEngineShaderParser
    private let shaderPreprocessor: WallpaperEngineShaderPreprocessor
    private let shaderBindingPlanner: WallpaperEngineShaderBindingPlanner
    private let metalShaderTranslator: WallpaperEngineMetalShaderTranslator
    private let renderCommandPlanner: WallpaperEngineRenderCommandPlanner
    private let metalRenderPlanBuilder: WallpaperEngineMetalRenderPlanBuilder
    private let builtinShaderLibrary: WallpaperEngineBuiltinShaderLibrary

    init(
        assetStore: WallpaperEngineSceneAssetStore,
        textureParser: WallpaperEngineTextureParser = WallpaperEngineTextureParser(),
        shaderParser: WallpaperEngineShaderParser = WallpaperEngineShaderParser(),
        shaderPreprocessor: WallpaperEngineShaderPreprocessor = WallpaperEngineShaderPreprocessor(),
        shaderBindingPlanner: WallpaperEngineShaderBindingPlanner = WallpaperEngineShaderBindingPlanner(),
        metalShaderTranslator: WallpaperEngineMetalShaderTranslator = WallpaperEngineMetalShaderTranslator(),
        renderCommandPlanner: WallpaperEngineRenderCommandPlanner = WallpaperEngineRenderCommandPlanner(),
        metalRenderPlanBuilder: WallpaperEngineMetalRenderPlanBuilder = WallpaperEngineMetalRenderPlanBuilder(),
        builtinShaderLibrary: WallpaperEngineBuiltinShaderLibrary = WallpaperEngineBuiltinShaderLibrary()
    ) {
        self.assetStore = assetStore
        self.textureParser = textureParser
        self.shaderParser = shaderParser
        self.shaderPreprocessor = shaderPreprocessor
        self.shaderBindingPlanner = shaderBindingPlanner
        self.metalShaderTranslator = metalShaderTranslator
        self.renderCommandPlanner = renderCommandPlanner
        self.metalRenderPlanBuilder = metalRenderPlanBuilder
        self.builtinShaderLibrary = builtinShaderLibrary
    }

    func resolve(plan: WallpaperEngineSceneRenderPlan) -> WallpaperEngineResolvedSceneResources {
        var assets: [String: Data] = [:]
        var textures: [String: WallpaperEngineTextureInfo] = [:]
        var shaders: [String: WallpaperEngineResolvedShader] = [:]
        var shaderIncludes: [String: WallpaperEngineResolvedShaderInclude] = [:]
        var preparedShaders: [WallpaperEnginePreparedShader] = []
        var shaderBindings: [WallpaperEngineShaderBindingPlan] = []
        var metalShaders: [WallpaperEngineMetalShader] = []
        var missingAssets = Set<String>()
        var textureParseFailures: [WallpaperEngineResolvedResourceFailure] = []
        var unresolvedShaders = Set<String>()
        var unresolvedShaderIncludes = Set<String>()

        resolveDataAssets(plan: plan, assets: &assets, missingAssets: &missingAssets)
        resolveTextures(
            plan.resources.textures,
            textures: &textures,
            missingAssets: &missingAssets,
            textureParseFailures: &textureParseFailures
        )
        resolveShaders(
            plan.resources.shaders,
            shaders: &shaders,
            unresolvedShaders: &unresolvedShaders
        )
        resolveShaderDependencies(
            Array(shaders.values),
            shaderIncludes: &shaderIncludes,
            textures: &textures,
            missingAssets: &missingAssets,
            textureParseFailures: &textureParseFailures,
            unresolvedShaderIncludes: &unresolvedShaderIncludes
        )
        preparedShaders = prepareShaders(
            plan: plan,
            shaders: shaders,
            shaderIncludes: shaderIncludes
        )
        shaderBindings = shaderBindingPlanner.buildBindings(
            plan: plan,
            shaders: shaders,
            shaderIncludes: shaderIncludes
        )
        metalShaders = translateMetalShaders(
            preparedShaders: preparedShaders,
            shaderBindings: shaderBindings
        )
        let renderCommandPlan = renderCommandPlanner.buildCommandPlan(
            plan: plan,
            shaderBindings: shaderBindings
        )
        let metalRenderPlan = metalRenderPlanBuilder.buildPlan(
            commandPlan: renderCommandPlan,
            textures: textures,
            metalShaders: metalShaders
        )

        return WallpaperEngineResolvedSceneResources(
            assets: assets,
            textures: textures,
            shaders: shaders,
            shaderIncludes: shaderIncludes,
            preparedShaders: preparedShaders,
            shaderBindings: shaderBindings,
            metalShaders: metalShaders,
            renderCommandPlan: renderCommandPlan,
            metalRenderPlan: metalRenderPlan,
            missingAssets: missingAssets.sorted(),
            textureParseFailures: textureParseFailures.sorted { $0.path < $1.path },
            unresolvedShaders: unresolvedShaders.sorted(),
            unresolvedShaderIncludes: unresolvedShaderIncludes.sorted()
        )
    }

    private func prepareShaders(
        plan: WallpaperEngineSceneRenderPlan,
        shaders: [String: WallpaperEngineResolvedShader],
        shaderIncludes: [String: WallpaperEngineResolvedShaderInclude]
    ) -> [WallpaperEnginePreparedShader] {
        var preparedShaders: [WallpaperEnginePreparedShader] = []

        for object in plan.objects {
            switch object.payload {
            case .image(let image):
                for (index, materialPass) in image.basePasses.enumerated() {
                    appendPreparedShader(
                        materialPass,
                        usage: "object:\(object.id):image:base:\(index)",
                        textureBindings: materialPass.textures + materialPass.userTextures,
                        shaders: shaders,
                        shaderIncludes: shaderIncludes,
                        preparedShaders: &preparedShaders
                    )
                }
                for effect in image.effects {
                    for effectPass in effect.passes {
                        guard let materialPass = effectPass.materialPass else {
                            continue
                        }
                        appendPreparedShader(
                            materialPass,
                            usage: "object:\(object.id):image:effect:\(effect.id):pass:\(effectPass.effectPassIndex):material:\(effectPass.materialPassIndex ?? 0)",
                            textureBindings: materialPass.textures + materialPass.userTextures + effectPass.binds,
                            shaders: shaders,
                            shaderIncludes: shaderIncludes,
                            preparedShaders: &preparedShaders
                        )
                    }
                }
            case .particle(let particle):
                for (index, materialPass) in particle.materialPasses.enumerated() {
                    appendPreparedShader(
                        materialPass,
                        usage: "object:\(object.id):particle:material:\(index)",
                        textureBindings: materialPass.textures + materialPass.userTextures,
                        shaders: shaders,
                        shaderIncludes: shaderIncludes,
                        preparedShaders: &preparedShaders
                    )
                }
            case .sound, .text, .unsupported:
                continue
            }
        }

        return preparedShaders
    }

    private func translateMetalShaders(
        preparedShaders: [WallpaperEnginePreparedShader],
        shaderBindings: [WallpaperEngineShaderBindingPlan]
    ) -> [WallpaperEngineMetalShader] {
        let bindingsByUsage = Dictionary(
            shaderBindings.map { ($0.usage, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return preparedShaders.compactMap { preparedShader in
            guard let binding = bindingsByUsage[preparedShader.usage] else {
                return nil
            }
            return metalShaderTranslator.translate(
                preparedShader: preparedShader,
                binding: binding
            )
        }
    }

    private func appendPreparedShader(
        _ materialPass: WallpaperEngineMaterialPassRenderPlan,
        usage: String,
        textureBindings: [WallpaperEngineRenderTextureBinding],
        shaders: [String: WallpaperEngineResolvedShader],
        shaderIncludes: [String: WallpaperEngineResolvedShaderInclude],
        preparedShaders: inout [WallpaperEnginePreparedShader]
    ) {
        guard let shader = shaders[materialPass.shader] else {
            return
        }

        preparedShaders.append(shaderPreprocessor.prepare(
            shader: shader,
            usage: usage,
            materialCombos: materialPass.combos,
            textureBindings: textureBindings,
            includes: shaderIncludes
        ))
    }

    private func resolveDataAssets(
        plan: WallpaperEngineSceneRenderPlan,
        assets: inout [String: Data],
        missingAssets: inout Set<String>
    ) {
        let paths = Set(
            plan.resources.models
                + plan.resources.materials
                + plan.resources.effects
                + plan.resources.particles
                + plan.resources.fonts
                + plan.resources.sounds
        )

        for path in paths.sorted() {
            if let data = assetStore.data(for: path) {
                assets[path] = data
            } else {
                missingAssets.insert(path)
            }
        }
    }

    private func resolveTextures(
        _ paths: [String],
        textures: inout [String: WallpaperEngineTextureInfo],
        missingAssets: inout Set<String>,
        textureParseFailures: inout [WallpaperEngineResolvedResourceFailure]
    ) {
        for path in paths {
            guard let data = assetStore.data(for: path) else {
                missingAssets.insert(path)
                continue
            }

            do {
                textures[path] = try textureParser.parseTexture(data: data, path: path)
            } catch {
                textureParseFailures.append(WallpaperEngineResolvedResourceFailure(
                    path: path,
                    reason: String(describing: error)
                ))
            }
        }
    }

    private func resolveShaders(
        _ names: [String],
        shaders: inout [String: WallpaperEngineResolvedShader],
        unresolvedShaders: inout Set<String>
    ) {
        for name in names {
            let vertex = resolveShaderStage(name: name, extension: "vert")
            let fragment = resolveShaderStage(name: name, extension: "frag")

            if vertex.source == nil && fragment.source == nil {
                unresolvedShaders.insert(name)
                continue
            }

            shaders[name] = WallpaperEngineResolvedShader(
                name: name,
                vertexPath: vertex.path,
                fragmentPath: fragment.path,
                vertexSource: vertex.source,
                fragmentSource: fragment.source,
                vertexMetadata: vertex.path.flatMap { path in
                    vertex.source.map {
                        shaderParser.parseShader(source: $0, path: path, stage: .vertex)
                    }
                },
                fragmentMetadata: fragment.path.flatMap { path in
                    fragment.source.map {
                        shaderParser.parseShader(source: $0, path: path, stage: .fragment)
                    }
                }
            )
        }
    }

    private func resolveShaderDependencies(
        _ shaders: [WallpaperEngineResolvedShader],
        shaderIncludes: inout [String: WallpaperEngineResolvedShaderInclude],
        textures: inout [String: WallpaperEngineTextureInfo],
        missingAssets: inout Set<String>,
        textureParseFailures: inout [WallpaperEngineResolvedResourceFailure],
        unresolvedShaderIncludes: inout Set<String>
    ) {
        var defaultTextureNames = Set<String>()
        var includeQueue: [String] = []

        for shader in shaders {
            for metadata in [shader.vertexMetadata, shader.fragmentMetadata].compactMap({ $0 }) {
                defaultTextureNames.formUnion(defaultTextures(in: metadata))
                includeQueue.append(contentsOf: metadata.includes)
            }
        }

        var processedIncludes = Set<String>()
        while !includeQueue.isEmpty {
            let includePath = includeQueue.removeFirst().normalizedWallpaperEnginePath
            guard !processedIncludes.contains(includePath) else {
                continue
            }
            processedIncludes.insert(includePath)

            guard let resolved = resolveShaderInclude(includePath) else {
                unresolvedShaderIncludes.insert(includePath)
                continue
            }

            let metadata = shaderParser.parseShader(
                source: resolved.source,
                path: resolved.path,
                stage: .include
            )
            shaderIncludes[includePath] = WallpaperEngineResolvedShaderInclude(
                requestedPath: includePath,
                resolvedPath: resolved.path,
                source: resolved.source,
                metadata: metadata
            )
            defaultTextureNames.formUnion(defaultTextures(in: metadata))
            includeQueue.append(contentsOf: metadata.includes)
        }

        let defaultTexturePaths = defaultTextureNames.compactMap(defaultTexturePath).sorted()
        resolveTextures(
            defaultTexturePaths,
            textures: &textures,
            missingAssets: &missingAssets,
            textureParseFailures: &textureParseFailures
        )
    }

    private func defaultTextures(in metadata: WallpaperEngineShaderMetadata) -> [String] {
        metadata.textures.compactMap(\.defaultTexture)
    }

    private func defaultTexturePath(_ textureName: String) -> String? {
        let normalized = textureName.normalizedWallpaperEnginePath
        guard !normalized.isEmpty else {
            return nil
        }
        if normalized.wallpaperEnginePathExtension == "tex" {
            return normalized
        }
        return "materials/\(normalized).tex"
    }

    private func resolveShaderInclude(_ requestedPath: String) -> (path: String, source: String)? {
        for path in shaderIncludeCandidates(requestedPath) {
            if let source = assetStore.string(for: path) {
                return (path, source)
            }
        }
        if let include = builtinShaderLibrary.includeSource(for: requestedPath) {
            return (include.resolvedPath, include.source)
        }
        return nil
    }

    private func shaderIncludeCandidates(_ requestedPath: String) -> [String] {
        let normalized = requestedPath.normalizedWallpaperEnginePath
        let includePath = normalized.wallpaperEnginePathExtension.isEmpty
            ? "\(normalized).h"
            : normalized

        if includePath.hasPrefix("shaders/") {
            return [includePath]
        }
        return [
            "shaders/\(includePath)",
            includePath
        ]
    }

    private func resolveShaderStage(
        name: String,
        extension pathExtension: String
    ) -> (path: String?, source: String?) {
        for path in shaderStageCandidates(name: name, extension: pathExtension) {
            if let source = assetStore.string(for: path) {
                return (path, source)
            }
        }
        if let stage = builtinShaderLibrary.shaderStageSource(
            name: name,
            pathExtension: pathExtension
        ) {
            return (stage.resolvedPath, stage.source)
        }

        return (nil, nil)
    }

    private func shaderStageCandidates(
        name: String,
        extension pathExtension: String
    ) -> [String] {
        let normalized = name.normalizedWallpaperEnginePath
        var candidates = [
            "shaders/\(normalized).\(pathExtension)",
            "\(normalized).\(pathExtension)"
        ]

        if !normalized.hasPrefix("effects/") {
            candidates.append("shaders/effects/\(normalized).\(pathExtension)")
        }

        return candidates
    }
}
