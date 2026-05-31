import Foundation

struct WallpaperEngineSceneRenderPlan: Equatable, Sendable {
    let canvasSize: WallpaperEngineSceneVector2?
    let clearColor: WallpaperEngineSceneValue?
    let objects: [WallpaperEngineRenderObject]
    let framebuffers: [WallpaperEngineRenderFramebuffer]
    let resources: WallpaperEngineRenderResources
}

struct WallpaperEngineRenderResources: Equatable, Sendable {
    let models: [String]
    let materials: [String]
    let textures: [String]
    let shaders: [String]
    let effects: [String]
    let particles: [String]
    let fonts: [String]
    let sounds: [String]
    let framebuffers: [String]
}

struct WallpaperEngineRenderObject: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case image(WallpaperEngineImageRenderPlan)
        case text(WallpaperEngineTextRenderPlan)
        case particle(WallpaperEngineParticleRenderPlan)
        case sound(WallpaperEngineSoundRenderPlan)
        case unsupported
    }

    let id: Int
    let name: String
    let kind: WallpaperEngineSceneObjectSummary.Kind
    let parentID: Int?
    let dependencies: [Int]
    let transform: WallpaperEngineRenderTransform
    let payload: Payload
}

struct WallpaperEngineRenderTransform: Equatable, Sendable {
    let origin: WallpaperEngineSceneValue?
    let scale: WallpaperEngineSceneValue?
    let angles: WallpaperEngineSceneValue?
    let visible: WallpaperEngineSceneValue?
    let alpha: WallpaperEngineSceneValue?
    let size: WallpaperEngineSceneValue?
}

struct WallpaperEngineImageRenderPlan: Equatable, Sendable {
    let modelPath: String
    let materialPath: String?
    let size: WallpaperEngineSceneVector2?
    let basePasses: [WallpaperEngineMaterialPassRenderPlan]
    let effects: [WallpaperEngineImageEffectRenderPlan]
    let animationLayers: [WallpaperEngineImageAnimationLayer]
}

struct WallpaperEngineTextRenderPlan: Equatable, Sendable {
    let text: String
    let script: String?
    let fontPath: String?
    let pointSize: WallpaperEngineSceneValue?
    let color: WallpaperEngineSceneValue?
    let alignment: String?
    let verticalAlignment: String?
}

struct WallpaperEngineParticleRenderPlan: Equatable, Sendable {
    let particlePath: String?
    let materialPath: String?
    let maxCount: Int?
    let materialPasses: [WallpaperEngineMaterialPassRenderPlan]
    let emitters: [WallpaperEngineParticleComponent]
    let initializers: [WallpaperEngineParticleComponent]
    let operators: [WallpaperEngineParticleComponent]
    let renderers: [WallpaperEngineParticleComponent]
    let controlPoints: [WallpaperEngineParticleControlPoint]
    let children: [WallpaperEngineParticleChild]
}

struct WallpaperEngineSoundRenderPlan: Equatable, Sendable {
    let soundPaths: [String]
    let playbackMode: String?
}

struct WallpaperEngineImageEffectRenderPlan: Equatable, Sendable {
    let id: Int
    let name: String
    let filePath: String
    let visible: WallpaperEngineSceneValue?
    let framebuffers: [WallpaperEngineRenderFramebuffer]
    let passes: [WallpaperEngineEffectPassRenderPlan]
}

struct WallpaperEngineEffectPassRenderPlan: Equatable, Sendable {
    let effectPassIndex: Int
    let materialPassIndex: Int?
    let command: String?
    let source: WallpaperEngineRenderTextureReference?
    let target: WallpaperEngineRenderTextureReference?
    let binds: [WallpaperEngineRenderTextureBinding]
    let materialPass: WallpaperEngineMaterialPassRenderPlan?
}

struct WallpaperEngineMaterialPassRenderPlan: Equatable, Sendable {
    let materialPath: String?
    let shader: String
    let blending: String
    let cullMode: String
    let depthTest: String
    let depthWrite: String
    let textures: [WallpaperEngineRenderTextureBinding]
    let userTextures: [WallpaperEngineRenderTextureBinding]
    let combos: [String: Int]
    let constants: [String: WallpaperEngineSceneValue]
    let overrideID: Int?
}

struct WallpaperEngineRenderTextureBinding: Equatable, Sendable {
    let index: Int
    let reference: WallpaperEngineRenderTextureReference
}

enum WallpaperEngineRenderTextureReference: Equatable, Sendable {
    case asset(String)
    case framebuffer(String)
    case previous
    case alias(String)
    case named(String)
}

struct WallpaperEngineRenderFramebuffer: Equatable, Sendable {
    let name: String
    let format: String
    let scale: Double
    let unique: Bool
}

struct WallpaperEngineSceneRenderPlanner {
    func buildPlan(for document: WallpaperEngineSceneDocument) -> WallpaperEngineSceneRenderPlan {
        var resources = ResourceCollector()
        var framebuffersByName: [String: WallpaperEngineRenderFramebuffer] = [:]
        let objects = renderOrderedObjects(document.objects).map {
            buildObject($0, resources: &resources, framebuffersByName: &framebuffersByName)
        }

        resources.framebuffers.formUnion(framebuffersByName.keys)

        return WallpaperEngineSceneRenderPlan(
            canvasSize: canvasSize(for: document),
            clearColor: document.general.clearColor,
            objects: objects,
            framebuffers: framebuffersByName.values.sorted { $0.name < $1.name },
            resources: resources.makeResources()
        )
    }

    private func canvasSize(for document: WallpaperEngineSceneDocument) -> WallpaperEngineSceneVector2? {
        guard let width = document.general.projection.width,
              let height = document.general.projection.height else {
            return nil
        }
        return WallpaperEngineSceneVector2(x: Double(width), y: Double(height))
    }

    private func buildObject(
        _ object: WallpaperEngineSceneObject,
        resources: inout ResourceCollector,
        framebuffersByName: inout [String: WallpaperEngineRenderFramebuffer]
    ) -> WallpaperEngineRenderObject {
        WallpaperEngineRenderObject(
            id: object.id,
            name: object.name,
            kind: object.kind,
            parentID: object.parentID,
            dependencies: object.dependencies,
            transform: WallpaperEngineRenderTransform(
                origin: object.origin,
                scale: object.scale,
                angles: object.angles,
                visible: object.visible,
                alpha: object.alpha,
                size: object.size
            ),
            payload: buildPayload(
                for: object,
                resources: &resources,
                framebuffersByName: &framebuffersByName
            )
        )
    }

    private func buildPayload(
        for object: WallpaperEngineSceneObject,
        resources: inout ResourceCollector,
        framebuffersByName: inout [String: WallpaperEngineRenderFramebuffer]
    ) -> WallpaperEngineRenderObject.Payload {
        if let image = object.image {
            return .image(buildImage(image, resources: &resources, framebuffersByName: &framebuffersByName))
        }
        if let text = object.text {
            if let fontPath = text.fontPath {
                resources.fonts.insert(fontPath)
            }
            return .text(WallpaperEngineTextRenderPlan(
                text: text.text,
                script: text.script,
                fontPath: text.fontPath,
                pointSize: text.pointSize,
                color: text.color,
                alignment: text.alignment,
                verticalAlignment: text.verticalAlignment
            ))
        }
        if let particle = object.particle {
            return .particle(buildParticle(particle, resources: &resources))
        }
        if let sound = object.sound {
            resources.sounds.formUnion(sound.soundPaths)
            return .sound(WallpaperEngineSoundRenderPlan(
                soundPaths: sound.soundPaths,
                playbackMode: sound.playbackMode
            ))
        }
        return .unsupported
    }

    private func buildImage(
        _ image: WallpaperEngineImageObject,
        resources: inout ResourceCollector,
        framebuffersByName: inout [String: WallpaperEngineRenderFramebuffer]
    ) -> WallpaperEngineImageRenderPlan {
        resources.models.insert(image.modelPath)

        let model = image.model
        let material = model?.material
        let materialPath = model?.materialPath
        if let materialPath {
            resources.materials.insert(materialPath)
        }

        return WallpaperEngineImageRenderPlan(
            modelPath: image.modelPath,
            materialPath: materialPath,
            size: modelSize(model),
            basePasses: materialPasses(
                material,
                materialPath: materialPath,
                override: nil,
                resources: &resources
            ),
            effects: image.effects.map {
                buildEffect($0, resources: &resources, framebuffersByName: &framebuffersByName)
            },
            animationLayers: image.animationLayers
        )
    }

    private func buildParticle(
        _ particle: WallpaperEngineParticleObject,
        resources: inout ResourceCollector
    ) -> WallpaperEngineParticleRenderPlan {
        if let particlePath = particle.particlePath {
            resources.particles.insert(particlePath)
        }

        let definition = particle.definition
        if let path = definition?.path {
            resources.particles.insert(path)
        }
        for child in definition?.children ?? [] {
            if let particlePath = child.particlePath {
                resources.particles.insert(particlePath)
            }
        }

        let materialPath = definition?.materialPath
        if let materialPath {
            resources.materials.insert(materialPath)
        }

        return WallpaperEngineParticleRenderPlan(
            particlePath: particle.particlePath,
            materialPath: materialPath,
            maxCount: definition?.maxCount,
            materialPasses: materialPasses(
                definition?.material,
                materialPath: materialPath,
                override: nil,
                resources: &resources
            ),
            emitters: definition?.emitters ?? [],
            initializers: definition?.initializers ?? [],
            operators: definition?.operators ?? [],
            renderers: definition?.renderers ?? [],
            controlPoints: definition?.controlPoints ?? [],
            children: definition?.children ?? []
        )
    }

    private func buildEffect(
        _ imageEffect: WallpaperEngineImageEffect,
        resources: inout ResourceCollector,
        framebuffersByName: inout [String: WallpaperEngineRenderFramebuffer]
    ) -> WallpaperEngineImageEffectRenderPlan {
        resources.effects.insert(imageEffect.filePath)
        guard let effect = imageEffect.effect else {
            return WallpaperEngineImageEffectRenderPlan(
                id: imageEffect.id,
                name: imageEffect.name,
                filePath: imageEffect.filePath,
                visible: imageEffect.visible,
                framebuffers: [],
                passes: []
            )
        }

        for dependency in effect.dependencies {
            resources.effects.insert(dependency)
        }

        let framebuffers = effect.fbos.map { fbo in
            let framebuffer = WallpaperEngineRenderFramebuffer(
                name: fbo.name,
                format: fbo.format,
                scale: fbo.scale,
                unique: fbo.unique
            )
            framebuffersByName[fbo.name] = framebuffer
            return framebuffer
        }

        let passes = effect.passes.enumerated().flatMap { effectPassIndex, effectPass in
            effectPasses(
                effectPass,
                effectPassIndex: effectPassIndex,
                override: imageEffect.passOverrides.indices.contains(effectPassIndex)
                    ? imageEffect.passOverrides[effectPassIndex]
                    : nil,
                resources: &resources,
                framebuffersByName: &framebuffersByName
            )
        }

        return WallpaperEngineImageEffectRenderPlan(
            id: imageEffect.id,
            name: imageEffect.name,
            filePath: imageEffect.filePath,
            visible: imageEffect.visible,
            framebuffers: framebuffers,
            passes: passes
        )
    }

    private func effectPasses(
        _ effectPass: WallpaperEngineEffectPass,
        effectPassIndex: Int,
        override: WallpaperEngineEffectPassOverride?,
        resources: inout ResourceCollector,
        framebuffersByName: inout [String: WallpaperEngineRenderFramebuffer]
    ) -> [WallpaperEngineEffectPassRenderPlan] {
        let binds = effectPass.binds
            .map { WallpaperEngineRenderTextureBinding(index: $0.key, reference: framebufferReference($0.value)) }
            .sorted { $0.index < $1.index }
        registerFramebufferReferences(binds.map(\.reference), framebuffersByName: &framebuffersByName)

        let source = effectPass.source.map(framebufferReference)
        let target = effectPass.target.map(framebufferReference)
        registerFramebufferReferences([source, target].compactMap { $0 }, framebuffersByName: &framebuffersByName)

        guard let material = effectPass.material else {
            return [
                WallpaperEngineEffectPassRenderPlan(
                    effectPassIndex: effectPassIndex,
                    materialPassIndex: nil,
                    command: effectPass.command,
                    source: source,
                    target: target,
                    binds: binds,
                    materialPass: nil
                )
            ]
        }

        if let materialPath = effectPass.materialPath {
            resources.materials.insert(materialPath)
        }

        return material.passes.enumerated().map { materialPassIndex, materialPass in
            WallpaperEngineEffectPassRenderPlan(
                effectPassIndex: effectPassIndex,
                materialPassIndex: materialPassIndex,
                command: effectPass.command,
                source: source,
                target: target,
                binds: binds,
                materialPass: buildMaterialPass(
                    materialPass,
                    materialPath: effectPass.materialPath,
                    override: override,
                    resources: &resources
                )
            )
        }
    }

    private func materialPasses(
        _ material: WallpaperEngineMaterial?,
        materialPath: String?,
        override: WallpaperEngineEffectPassOverride?,
        resources: inout ResourceCollector
    ) -> [WallpaperEngineMaterialPassRenderPlan] {
        material?.passes.map {
            buildMaterialPass($0, materialPath: materialPath, override: override, resources: &resources)
        } ?? []
    }

    private func buildMaterialPass(
        _ pass: WallpaperEngineMaterialPass,
        materialPath: String?,
        override: WallpaperEngineEffectPassOverride?,
        resources: inout ResourceCollector
    ) -> WallpaperEngineMaterialPassRenderPlan {
        resources.shaders.insert(pass.shader)
        if let materialPath {
            resources.materials.insert(materialPath)
        }

        let resolvedTextureBindings = makeTextureBindings(pass.textures, override: override?.textures)
        let resolvedUserTextureBindings = makeTextureBindings(pass.userTextures, override: nil)
        collectTextureAssets(resolvedTextureBindings + resolvedUserTextureBindings, resources: &resources)

        return WallpaperEngineMaterialPassRenderPlan(
            materialPath: materialPath,
            shader: pass.shader,
            blending: pass.blending,
            cullMode: pass.cullMode,
            depthTest: pass.depthTest,
            depthWrite: pass.depthWrite,
            textures: resolvedTextureBindings,
            userTextures: resolvedUserTextureBindings,
            combos: pass.combos.merging(override?.combos ?? [:]) { _, override in override },
            constants: pass.constants.merging(override?.constants ?? [:]) { _, override in override },
            overrideID: override?.id
        )
    }

    private func makeTextureBindings(
        _ baseTextures: [Int: String],
        override: [Int: String]?
    ) -> [WallpaperEngineRenderTextureBinding] {
        baseTextures
            .merging(override ?? [:]) { _, override in override }
            .map {
                WallpaperEngineRenderTextureBinding(index: $0.key, reference: textureReference($0.value))
            }
            .sorted { $0.index < $1.index }
    }

    private func textureReference(_ name: String) -> WallpaperEngineRenderTextureReference {
        let normalized = name.normalizedWallpaperEnginePath
        if normalized == "previous" {
            return .previous
        }
        if normalized.hasPrefix("_rt_") {
            return .framebuffer(normalized)
        }
        if normalized.hasPrefix("_alias_") {
            return .alias(normalized)
        }
        if normalized.wallpaperEnginePathExtension == "tex" {
            return .asset(normalized)
        }
        return .asset("materials/\(normalized).tex")
    }

    private func framebufferReference(_ name: String) -> WallpaperEngineRenderTextureReference {
        let normalized = name.normalizedWallpaperEnginePath
        if normalized == "previous" {
            return .previous
        }
        if normalized.hasPrefix("_alias_") {
            return .alias(normalized)
        }
        if normalized.hasPrefix("_rt_") {
            return .framebuffer(normalized)
        }
        return .framebuffer(normalized)
    }

    private func registerFramebufferReferences(
        _ references: [WallpaperEngineRenderTextureReference],
        framebuffersByName: inout [String: WallpaperEngineRenderFramebuffer]
    ) {
        for reference in references {
            if case .framebuffer(let name) = reference {
                if framebuffersByName[name] == nil {
                    framebuffersByName[name] = WallpaperEngineRenderFramebuffer(
                        name: name,
                        format: "rgba8888",
                        scale: 1,
                        unique: false
                    )
                }
            }
        }
    }

    private func collectTextureAssets(
        _ bindings: [WallpaperEngineRenderTextureBinding],
        resources: inout ResourceCollector
    ) {
        for binding in bindings {
            if case .asset(let path) = binding.reference {
                resources.textures.insert(path)
            }
        }
    }

    private func modelSize(_ model: WallpaperEngineModel?) -> WallpaperEngineSceneVector2? {
        guard let width = model?.width,
              let height = model?.height else {
            return nil
        }
        return WallpaperEngineSceneVector2(x: Double(width), y: Double(height))
    }

    private func renderOrderedObjects(_ objects: [WallpaperEngineSceneObject]) -> [WallpaperEngineSceneObject] {
        let objectsByID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        var temporary = Set<Int>()
        var permanent = Set<Int>()
        var result: [WallpaperEngineSceneObject] = []

        func visit(_ object: WallpaperEngineSceneObject) {
            guard !permanent.contains(object.id) else {
                return
            }
            guard !temporary.contains(object.id) else {
                result.append(object)
                permanent.insert(object.id)
                return
            }

            temporary.insert(object.id)
            for dependencyID in renderDependencies(for: object) {
                if let dependency = objectsByID[dependencyID] {
                    visit(dependency)
                }
            }
            temporary.remove(object.id)
            permanent.insert(object.id)
            if !result.contains(where: { $0.id == object.id }) {
                result.append(object)
            }
        }

        for object in objects {
            visit(object)
        }

        return result
    }

    private func renderDependencies(for object: WallpaperEngineSceneObject) -> [Int] {
        var dependencies = object.dependencies
        if let parentID = object.parentID {
            dependencies.append(parentID)
        }
        return dependencies
    }
}

private struct ResourceCollector {
    var models = Set<String>()
    var materials = Set<String>()
    var textures = Set<String>()
    var shaders = Set<String>()
    var effects = Set<String>()
    var particles = Set<String>()
    var fonts = Set<String>()
    var sounds = Set<String>()
    var framebuffers = Set<String>()

    func makeResources() -> WallpaperEngineRenderResources {
        WallpaperEngineRenderResources(
            models: models.sorted(),
            materials: materials.sorted(),
            textures: textures.sorted(),
            shaders: shaders.sorted(),
            effects: effects.sorted(),
            particles: particles.sorted(),
            fonts: fonts.sorted(),
            sounds: sounds.sorted(),
            framebuffers: framebuffers.sorted()
        )
    }
}
