import Foundation

struct WallpaperEngineSceneVector2: Equatable, Sendable {
    let x: Double
    let y: Double
}

struct WallpaperEngineSceneVector3: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

struct WallpaperEngineSceneVector4: Equatable, Sendable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}

indirect enum WallpaperEngineSceneValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case vector2(WallpaperEngineSceneVector2)
    case vector3(WallpaperEngineSceneVector3)
    case vector4(WallpaperEngineSceneVector4)
    case array([WallpaperEngineSceneValue])
    case object([String: WallpaperEngineSceneValue])
    case user(property: String, value: WallpaperEngineSceneValue?)
    case animation(value: WallpaperEngineSceneValue?, previewValue: WallpaperEngineSceneValue?)
}

struct WallpaperEngineSceneDocument: Equatable, Sendable {
    let project: WallpaperEngineProjectDescriptor
    let sceneFile: String
    let general: WallpaperEngineSceneGeneral
    let camera: WallpaperEngineSceneCamera
    let objects: [WallpaperEngineSceneObject]
}

struct WallpaperEngineProjectProperty: Equatable, Sendable {
    let type: String
    let text: String?
    let value: WallpaperEngineSceneValue?
    let index: Int?
    let order: Int?
    let minimum: WallpaperEngineSceneValue?
    let maximum: WallpaperEngineSceneValue?
    let step: WallpaperEngineSceneValue?
    let precision: Int?
    let fraction: Bool
    let options: [WallpaperEngineProjectPropertyOption]
    let rawFields: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineProjectPropertyOption: Equatable, Sendable {
    let label: String?
    let value: WallpaperEngineSceneValue?
}

struct WallpaperEngineSceneGeneral: Equatable, Sendable {
    let projection: WallpaperEngineSceneProjection
    let clearColor: WallpaperEngineSceneValue?
    let ambientColor: WallpaperEngineSceneValue?
    let skylightColor: WallpaperEngineSceneValue?
    let rawFields: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineSceneProjection: Equatable, Sendable {
    let width: Int?
    let height: Int?
    let isAuto: Bool
}

struct WallpaperEngineSceneCamera: Equatable, Sendable {
    let center: WallpaperEngineSceneValue?
    let eye: WallpaperEngineSceneValue?
    let up: WallpaperEngineSceneValue?
    let nearZ: Double?
    let farZ: Double?
    let fov: Double?
    let rawFields: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineSceneObject: Equatable, Sendable {
    let id: Int
    let name: String
    let kind: WallpaperEngineSceneObjectSummary.Kind
    let parentID: Int?
    let dependencies: [Int]
    let origin: WallpaperEngineSceneValue?
    let scale: WallpaperEngineSceneValue?
    let angles: WallpaperEngineSceneValue?
    let visible: WallpaperEngineSceneValue?
    let alpha: WallpaperEngineSceneValue?
    let size: WallpaperEngineSceneValue?
    let image: WallpaperEngineImageObject?
    let text: WallpaperEngineTextObject?
    let sound: WallpaperEngineSoundObject?
    let particle: WallpaperEngineParticleObject?
}

struct WallpaperEngineImageObject: Equatable, Sendable {
    let modelPath: String
    let model: WallpaperEngineModel?
    let effects: [WallpaperEngineImageEffect]
    let animationLayers: [WallpaperEngineImageAnimationLayer]
}

struct WallpaperEngineTextObject: Equatable, Sendable {
    let text: String
    let script: String?
    let scriptProperties: [String: WallpaperEngineSceneValue]
    let fontPath: String?
    let pointSize: WallpaperEngineSceneValue?
    let color: WallpaperEngineSceneValue?
    let alignment: String?
    let verticalAlignment: String?
}

struct WallpaperEngineSoundObject: Equatable, Sendable {
    let soundPaths: [String]
    let playbackMode: String?
}

struct WallpaperEngineParticleObject: Equatable, Sendable {
    let particlePath: String?
    let definition: WallpaperEngineParticleDefinition?
    let instanceOverride: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineModel: Equatable, Sendable {
    let path: String
    let materialPath: String
    let material: WallpaperEngineMaterial?
    let width: Int?
    let height: Int?
    let solidLayer: Bool
    let fullScreen: Bool
    let passthrough: Bool
    let autoSize: Bool
    let noPadding: Bool
    let puppet: String?
}

struct WallpaperEngineMaterial: Equatable, Sendable {
    let path: String
    let passes: [WallpaperEngineMaterialPass]
}

struct WallpaperEngineMaterialPass: Equatable, Sendable {
    let blending: String
    let cullMode: String
    let depthTest: String
    let depthWrite: String
    let shader: String
    let textures: [Int: String]
    let userTextures: [Int: String]
    let combos: [String: Int]
    let constants: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineImageEffect: Equatable, Sendable {
    let id: Int
    let name: String
    let filePath: String
    let visible: WallpaperEngineSceneValue?
    let effect: WallpaperEngineEffect?
    let passOverrides: [WallpaperEngineEffectPassOverride]
}

struct WallpaperEngineEffect: Equatable, Sendable {
    let path: String
    let name: String
    let description: String
    let group: String
    let preview: String?
    let dependencies: [String]
    let passes: [WallpaperEngineEffectPass]
    let fbos: [WallpaperEngineFBO]
}

struct WallpaperEngineEffectPass: Equatable, Sendable {
    let materialPath: String?
    let material: WallpaperEngineMaterial?
    let binds: [Int: String]
    let command: String?
    let source: String?
    let target: String?
}

struct WallpaperEngineEffectPassOverride: Equatable, Sendable {
    let id: Int
    let combos: [String: Int]
    let constants: [String: WallpaperEngineSceneValue]
    let textures: [Int: String]
}

struct WallpaperEngineFBO: Equatable, Sendable {
    let name: String
    let format: String
    let scale: Double
    let unique: Bool
}

struct WallpaperEngineImageAnimationLayer: Equatable, Sendable {
    let id: Int
    let rate: WallpaperEngineSceneValue?
    let visible: WallpaperEngineSceneValue?
    let blend: WallpaperEngineSceneValue?
    let animation: WallpaperEngineSceneValue?
}

struct WallpaperEngineParticleDefinition: Equatable, Sendable {
    let path: String?
    let materialPath: String?
    let material: WallpaperEngineMaterial?
    let animationMode: String
    let sequenceMultiplier: Double?
    let maxCount: Int?
    let rendererNames: [String]
    let emitters: [WallpaperEngineParticleComponent]
    let initializers: [WallpaperEngineParticleComponent]
    let operators: [WallpaperEngineParticleComponent]
    let renderers: [WallpaperEngineParticleComponent]
    let controlPoints: [WallpaperEngineParticleControlPoint]
    let children: [WallpaperEngineParticleChild]
    let rawFields: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineParticleComponent: Equatable, Sendable {
    let name: String
    let rawFields: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineParticleControlPoint: Equatable, Sendable {
    let index: Int?
    let name: String?
    let rawFields: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineParticleChild: Equatable, Sendable {
    let particlePath: String?
    let rawFields: [String: WallpaperEngineSceneValue]
}
