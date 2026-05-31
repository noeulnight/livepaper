import Foundation

struct WallpaperEngineSceneRenderCommandPlan: Equatable, Sendable {
    let canvasSize: WallpaperEngineSceneVector2?
    let clearColor: WallpaperEngineSceneValue?
    let sceneFramebuffer: String
    let framebuffers: [WallpaperEngineRenderFramebuffer]
    let objectFramebuffers: [WallpaperEngineObjectFramebuffer]
    let commands: [WallpaperEngineRenderCommand]
}

struct WallpaperEngineObjectFramebuffer: Equatable, Sendable {
    let objectID: Int
    let slot: WallpaperEngineObjectFramebufferSlot
    let size: WallpaperEngineSceneVector2?
}

struct WallpaperEngineRenderCommand: Equatable, Sendable {
    let id: String
    let kind: WallpaperEngineRenderCommandKind
    let objectID: Int
    let objectName: String
    let effectID: Int?
    let effectPassIndex: Int?
    let materialPassIndex: Int
    let usage: String
    let target: WallpaperEngineRenderCommandTarget
    let input: WallpaperEngineRenderCommandTexture?
    let previousInput: WallpaperEngineRenderCommandTexture?
    let source: WallpaperEngineRenderTextureReference?
    let materialPass: WallpaperEngineMaterialPassRenderPlan?
    let shaderBinding: WallpaperEngineShaderBindingPlan?
}

enum WallpaperEngineRenderCommandKind: Equatable, Sendable {
    case drawImageBase
    case drawImageEffect
    case drawParticle
}

enum WallpaperEngineRenderCommandTarget: Equatable, Sendable {
    case framebuffer(String)
    case objectFramebuffer(objectID: Int, slot: WallpaperEngineObjectFramebufferSlot)
}

enum WallpaperEngineRenderCommandTexture: Equatable, Sendable {
    case asset(String)
    case framebuffer(String)
    case objectFramebuffer(objectID: Int, slot: WallpaperEngineObjectFramebufferSlot)
    case previous
    case alias(String)
    case named(String)
}

enum WallpaperEngineObjectFramebufferSlot: String, Equatable, Sendable {
    case main
    case sub
}

struct WallpaperEngineRenderCommandPlanner {
    private let sceneFramebufferName: String

    init(sceneFramebufferName: String = "_rt_FullFrameBuffer") {
        self.sceneFramebufferName = sceneFramebufferName
    }

    func buildCommandPlan(
        plan: WallpaperEngineSceneRenderPlan,
        shaderBindings: [WallpaperEngineShaderBindingPlan]
    ) -> WallpaperEngineSceneRenderCommandPlan {
        let bindingsByUsage = Dictionary(
            shaderBindings.map { ($0.usage, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let renderCommands = plan.objects.flatMap { object in
            commands(for: object, bindingsByUsage: bindingsByUsage)
        }

        return WallpaperEngineSceneRenderCommandPlan(
            canvasSize: plan.canvasSize,
            clearColor: plan.clearColor,
            sceneFramebuffer: sceneFramebufferName,
            framebuffers: plan.framebuffers,
            objectFramebuffers: objectFramebuffers(in: plan),
            commands: renderCommands
        )
    }

    private func objectFramebuffers(in plan: WallpaperEngineSceneRenderPlan) -> [WallpaperEngineObjectFramebuffer] {
        plan.objects.flatMap { object -> [WallpaperEngineObjectFramebuffer] in
            guard case .image(let image) = object.payload,
                  !image.basePasses.isEmpty || image.effects.contains(where: { !$0.passes.isEmpty }) else {
                return []
            }

            return [
                WallpaperEngineObjectFramebuffer(objectID: object.id, slot: .main, size: image.size),
                WallpaperEngineObjectFramebuffer(objectID: object.id, slot: .sub, size: image.size)
            ]
        }
    }

    private func commands(
        for object: WallpaperEngineRenderObject,
        bindingsByUsage: [String: WallpaperEngineShaderBindingPlan]
    ) -> [WallpaperEngineRenderCommand] {
        switch object.payload {
        case .image(let image):
            return imageCommands(for: object, image: image, bindingsByUsage: bindingsByUsage)
        case .particle(let particle):
            return particleCommands(for: object, particle: particle, bindingsByUsage: bindingsByUsage)
        case .sound, .text, .unsupported:
            return []
        }
    }

    private func imageCommands(
        for object: WallpaperEngineRenderObject,
        image: WallpaperEngineImageRenderPlan,
        bindingsByUsage: [String: WallpaperEngineShaderBindingPlan]
    ) -> [WallpaperEngineRenderCommand] {
        let passes = imagePasses(for: object, image: image)
        guard !passes.isEmpty else {
            return []
        }

        var commands: [WallpaperEngineRenderCommand] = []
        var drawTarget: WallpaperEngineRenderCommandTarget = .objectFramebuffer(objectID: object.id, slot: .main)
        var currentInput = initialInput(for: passes[0].materialPass)
        var inTargetEffectSequence = false
        var effectInput: WallpaperEngineRenderCommandTexture?

        for (index, pass) in passes.enumerated() {
            let previousDrawTarget = drawTarget
            let target = pass.target.flatMap(commandTarget)
            let writesToExplicitTarget = target != nil

            if let target {
                if !inTargetEffectSequence {
                    effectInput = currentInput
                    inTargetEffectSequence = true
                }
                drawTarget = target
            } else if shouldRenderFinalPass(object: object, isLastPass: index == passes.count - 1) {
                drawTarget = .framebuffer(sceneFramebufferName)
            }

            let previousInput = inTargetEffectSequence ? effectInput : nil
            let command = WallpaperEngineRenderCommand(
                id: pass.usage,
                kind: pass.kind,
                objectID: object.id,
                objectName: object.name,
                effectID: pass.effectID,
                effectPassIndex: pass.effectPassIndex,
                materialPassIndex: pass.materialPassIndex,
                usage: pass.usage,
                target: drawTarget,
                input: currentInput,
                previousInput: previousInput,
                source: pass.source,
                materialPass: pass.materialPass,
                shaderBinding: bindingsByUsage[pass.usage]
            )
            commands.append(command)

            if writesToExplicitTarget {
                currentInput = texture(from: drawTarget)
                drawTarget = previousDrawTarget
            } else {
                drawTarget = previousDrawTarget
                pingPongFramebuffers(
                    objectID: object.id,
                    nextTarget: &drawTarget,
                    nextInput: &currentInput
                )
                inTargetEffectSequence = false
                effectInput = nil
            }
        }

        return commands
    }

    private func particleCommands(
        for object: WallpaperEngineRenderObject,
        particle: WallpaperEngineParticleRenderPlan,
        bindingsByUsage: [String: WallpaperEngineShaderBindingPlan]
    ) -> [WallpaperEngineRenderCommand] {
        particle.materialPasses.enumerated().map { materialPassIndex, materialPass in
            let usage = "object:\(object.id):particle:material:\(materialPassIndex)"
            return WallpaperEngineRenderCommand(
                id: usage,
                kind: .drawParticle,
                objectID: object.id,
                objectName: object.name,
                effectID: nil,
                effectPassIndex: nil,
                materialPassIndex: materialPassIndex,
                usage: usage,
                target: .framebuffer(sceneFramebufferName),
                input: initialInput(for: materialPass),
                previousInput: nil,
                source: nil,
                materialPass: materialPass,
                shaderBinding: bindingsByUsage[usage]
            )
        }
    }

    private func imagePasses(
        for object: WallpaperEngineRenderObject,
        image: WallpaperEngineImageRenderPlan
    ) -> [ImagePassContext] {
        let basePasses = image.basePasses.enumerated().map { index, materialPass in
            ImagePassContext(
                kind: .drawImageBase,
                effectID: nil,
                effectPassIndex: nil,
                materialPassIndex: index,
                usage: "object:\(object.id):image:base:\(index)",
                target: nil,
                source: nil,
                materialPass: materialPass
            )
        }
        let effectPasses = image.effects.flatMap { effect in
            effect.passes.compactMap { effectPass -> ImagePassContext? in
                guard let materialPass = effectPass.materialPass else {
                    return nil
                }
                let materialPassIndex = effectPass.materialPassIndex ?? 0
                return ImagePassContext(
                    kind: .drawImageEffect,
                    effectID: effect.id,
                    effectPassIndex: effectPass.effectPassIndex,
                    materialPassIndex: materialPassIndex,
                    usage: "object:\(object.id):image:effect:\(effect.id):pass:\(effectPass.effectPassIndex):material:\(materialPassIndex)",
                    target: effectPass.target,
                    source: effectPass.source,
                    materialPass: materialPass
                )
            }
        }
        return basePasses + effectPasses
    }

    private func initialInput(
        for materialPass: WallpaperEngineMaterialPassRenderPlan
    ) -> WallpaperEngineRenderCommandTexture? {
        let explicitInput = materialPass.textures.first { $0.index == 0 }
            ?? materialPass.textures.first
        return explicitInput.map { texture(from: $0.reference) }
    }

    private func shouldRenderFinalPass(
        object: WallpaperEngineRenderObject,
        isLastPass: Bool
    ) -> Bool {
        isLastPass && isVisible(object.transform.visible)
    }

    private func isVisible(_ value: WallpaperEngineSceneValue?) -> Bool {
        guard let value else {
            return true
        }

        switch value {
        case .bool(let bool):
            return bool
        case .int(let int):
            return int != 0
        case .double(let double):
            return double != 0
        default:
            return true
        }
    }

    private func pingPongFramebuffers(
        objectID: Int,
        nextTarget: inout WallpaperEngineRenderCommandTarget,
        nextInput: inout WallpaperEngineRenderCommandTexture?
    ) {
        let inputSlot: WallpaperEngineObjectFramebufferSlot
        let targetSlot: WallpaperEngineObjectFramebufferSlot

        switch nextTarget {
        case .objectFramebuffer(_, .main):
            inputSlot = .main
            targetSlot = .sub
        case .objectFramebuffer(_, .sub):
            inputSlot = .sub
            targetSlot = .main
        case .framebuffer:
            inputSlot = .main
            targetSlot = .sub
        }

        nextInput = .objectFramebuffer(objectID: objectID, slot: inputSlot)
        nextTarget = .objectFramebuffer(objectID: objectID, slot: targetSlot)
    }

    private func commandTarget(
        from reference: WallpaperEngineRenderTextureReference
    ) -> WallpaperEngineRenderCommandTarget? {
        switch reference {
        case .framebuffer(let name):
            return .framebuffer(name)
        case .alias(let name):
            return .framebuffer(name)
        case .named(let name):
            return .framebuffer(name)
        case .asset, .previous:
            return nil
        }
    }

    private func texture(
        from target: WallpaperEngineRenderCommandTarget
    ) -> WallpaperEngineRenderCommandTexture {
        switch target {
        case .framebuffer(let name):
            return .framebuffer(name)
        case .objectFramebuffer(let objectID, let slot):
            return .objectFramebuffer(objectID: objectID, slot: slot)
        }
    }

    private func texture(
        from reference: WallpaperEngineRenderTextureReference
    ) -> WallpaperEngineRenderCommandTexture {
        switch reference {
        case .asset(let path):
            return .asset(path)
        case .framebuffer(let name):
            return .framebuffer(name)
        case .previous:
            return .previous
        case .alias(let name):
            return .alias(name)
        case .named(let name):
            return .named(name)
        }
    }
}

private struct ImagePassContext {
    let kind: WallpaperEngineRenderCommandKind
    let effectID: Int?
    let effectPassIndex: Int?
    let materialPassIndex: Int
    let usage: String
    let target: WallpaperEngineRenderTextureReference?
    let source: WallpaperEngineRenderTextureReference?
    let materialPass: WallpaperEngineMaterialPassRenderPlan
}
