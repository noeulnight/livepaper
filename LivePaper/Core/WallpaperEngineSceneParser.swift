import Foundation

enum WallpaperEngineSceneParserError: LocalizedError, Equatable {
    case missingProject(URL)
    case invalidProject(URL)
    case unsupportedProjectType(String)
    case missingSceneFile(String)
    case invalidSceneJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingProject(let folderURL):
            return "Wallpaper Engine project.json was not found in \(folderURL.path) or its package files."
        case .invalidProject(let folderURL):
            return "Wallpaper Engine project.json could not be parsed in \(folderURL.path)."
        case .unsupportedProjectType(let type):
            return "Wallpaper Engine \(type) projects are not scene projects."
        case .missingSceneFile(let path):
            return "Wallpaper Engine scene file was not found: \(path)"
        case .invalidSceneJSON(let path):
            return "Wallpaper Engine scene file could not be parsed: \(path)"
        }
    }
}

struct WallpaperEngineProjectDescriptor: Equatable, Sendable {
    let title: String?
    let type: String
    let file: String
    let preview: String?
    let workshopID: String?
    let properties: [String: WallpaperEngineProjectProperty]
}

struct WallpaperEngineSceneObjectSummary: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case image
        case text
        case sound
        case particle
        case light
        case volumeLight
        case solid
        case empty
        case unknown
    }

    let id: Int
    let name: String
    let kind: Kind
    let parentID: Int?
    let dependencies: [Int]
}

struct WallpaperEngineSceneAssetReferences: Equatable, Sendable {
    let models: [String]
    let materials: [String]
    let effects: [String]
    let particles: [String]
    let textures: [String]
    let shaders: [String]
    let sounds: [String]
    let fonts: [String]
    let scriptFiles: [String]
    let inlineScriptCount: Int
}

struct WallpaperEngineScenePackageSummary: Equatable, Sendable {
    let filename: String
    let header: String
    let fileCount: Int
}

struct WallpaperEngineSceneManifest: Equatable, Sendable {
    let project: WallpaperEngineProjectDescriptor
    let sceneFile: String
    let packageFiles: [WallpaperEngineScenePackageSummary]
    let packageEntryExtensionCounts: [String: Int]
    let objects: [WallpaperEngineSceneObjectSummary]
    let assets: WallpaperEngineSceneAssetReferences
    let textures: [WallpaperEngineTextureInfo]
    let textureParseFailures: [String]

    var objectKindCounts: [WallpaperEngineSceneObjectSummary.Kind: Int] {
        objects.reduce(into: [:]) { counts, object in
            counts[object.kind, default: 0] += 1
        }
    }
}

struct WallpaperEngineSceneParser {
    private let fileManager: FileManager
    private let packageParser = WallpaperEnginePackageParser()
    private let textureParser = WallpaperEngineTextureParser()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func analyzeProject(in folderURL: URL) throws -> WallpaperEngineSceneManifest {
        let context = try loadSceneContext(in: folderURL)

        var referenceCollector = WallpaperEngineSceneReferenceCollector()
        for object in context.objectsJSON {
            referenceCollector.collect(fromObject: object)
        }
        resolveTransitiveReferences(container: context.container, collector: &referenceCollector)

        var textureInfos: [WallpaperEngineTextureInfo] = []
        var textureParseFailures: [String] = []

        for path in context.container.allAssetPaths.filter({ $0.wallpaperEnginePathExtension == "tex" }).sorted() {
            guard let textureData = context.container.data(for: path) else {
                continue
            }

            do {
                textureInfos.append(try textureParser.parseTexture(data: textureData, path: path))
            } catch {
                textureParseFailures.append(path)
            }
        }

        return WallpaperEngineSceneManifest(
            project: context.project,
            sceneFile: context.sceneFile,
            packageFiles: context.container.packages.map {
                WallpaperEngineScenePackageSummary(
                    filename: $0.url.lastPathComponent,
                    header: $0.header,
                    fileCount: $0.entries.count
                )
            },
            packageEntryExtensionCounts: context.container.packageEntryExtensionCounts,
            objects: context.objectSummaries,
            assets: referenceCollector.makeReferences(),
            textures: textureInfos.sorted { $0.path < $1.path },
            textureParseFailures: textureParseFailures
        )
    }

    func parseProject(in folderURL: URL) throws -> WallpaperEngineSceneDocument {
        let context = try loadSceneContext(in: folderURL)
        let generalJSON = context.scene["general"] as? [String: Any] ?? [:]
        let cameraJSON = context.scene["camera"] as? [String: Any] ?? [:]

        return WallpaperEngineSceneDocument(
            project: context.project,
            sceneFile: context.sceneFile,
            general: parseGeneral(generalJSON),
            camera: parseCamera(cameraJSON),
            objects: context.objectsJSON.map { parseDocumentObject($0, container: context.container) }
        )
    }

    private func loadSceneContext(in folderURL: URL) throws -> WallpaperEngineSceneParseContext {
        let container = try WallpaperEngineSceneAssetStore(
            folderURL: folderURL,
            fileManager: fileManager,
            packageParser: packageParser
        )

        guard let projectData = container.data(for: "project.json") else {
            throw WallpaperEngineSceneParserError.missingProject(folderURL)
        }

        let project = try parseProject(projectData, folderURL: folderURL)
        guard project.type == "scene" else {
            throw WallpaperEngineSceneParserError.unsupportedProjectType(project.type)
        }

        let sceneFile = project.file.normalizedWallpaperEnginePath
        guard let sceneData = container.data(for: sceneFile) else {
            throw WallpaperEngineSceneParserError.missingSceneFile(sceneFile)
        }

        let scene = try parseJSONObject(sceneData, source: sceneFile)
        let objectsJSON = scene["objects"] as? [[String: Any]] ?? []

        return WallpaperEngineSceneParseContext(
            container: container,
            project: project,
            sceneFile: sceneFile,
            scene: scene,
            objectsJSON: objectsJSON,
            objectSummaries: objectsJSON.map(parseObjectSummary)
        )
    }

    private func parseProject(_ data: Data, folderURL: URL) throws -> WallpaperEngineProjectDescriptor {
        guard let json = try? parseJSONObject(data, source: "project.json"),
              let type = (json["type"] as? String)?.lowercased(),
              let file = json["file"] as? String else {
            throw WallpaperEngineSceneParserError.invalidProject(folderURL)
        }

        let workshopID: String?
        if let value = json["workshopid"] as? String {
            workshopID = value
        } else if let value = json["workshopid"] as? NSNumber {
            workshopID = value.stringValue
        } else {
            workshopID = nil
        }

        return WallpaperEngineProjectDescriptor(
            title: json["title"] as? String,
            type: type,
            file: file.normalizedWallpaperEnginePath,
            preview: (json["preview"] as? String)?.normalizedWallpaperEnginePath,
            workshopID: workshopID,
            properties: parseProjectProperties(json)
        )
    }

    private func parseJSONObject(_ data: Data, source: String) throws -> [String: Any] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WallpaperEngineSceneParserError.invalidSceneJSON(source)
        }

        return json
    }

    private func parseObjectSummary(_ object: [String: Any]) -> WallpaperEngineSceneObjectSummary {
        WallpaperEngineSceneObjectSummary(
            id: object["id"] as? Int ?? -1,
            name: objectStringName(object["name"]),
            kind: objectKind(object),
            parentID: object["parent"] as? Int,
            dependencies: object["dependencies"] as? [Int] ?? []
        )
    }

    private func objectStringName(_ rawValue: Any?) -> String {
        if let value = rawValue as? String {
            return value
        }
        if let value = rawValue as? NSNumber {
            return value.stringValue
        }
        return "unknown"
    }

    private func objectKind(_ object: [String: Any]) -> WallpaperEngineSceneObjectSummary.Kind {
        if object["image"] is String {
            return .image
        }
        if object["sound"] is [Any] {
            return .sound
        }
        if object["particle"] != nil {
            return .particle
        }
        if object["text"] != nil {
            return .text
        }
        if object["light"] != nil {
            return .light
        }
        if object["shape"] != nil {
            return .volumeLight
        }
        if object["solid"] as? Bool == true {
            return .solid
        }
        if object["dependencies"] != nil || object["parent"] != nil {
            return .empty
        }
        return .unknown
    }

    private func parseGeneral(_ json: [String: Any]) -> WallpaperEngineSceneGeneral {
        let projectionJSON = json["orthogonalprojection"] as? [String: Any] ?? [:]

        return WallpaperEngineSceneGeneral(
            projection: WallpaperEngineSceneProjection(
                width: intValue(projectionJSON["width"]),
                height: intValue(projectionJSON["height"]),
                isAuto: boolValue(projectionJSON["auto"]) ?? false
            ),
            clearColor: sceneValue(json["clearcolor"]),
            ambientColor: sceneValue(json["ambientcolor"]),
            skylightColor: sceneValue(json["skylightcolor"]),
            rawFields: sceneObjectValue(json)
        )
    }

    private func parseCamera(_ json: [String: Any]) -> WallpaperEngineSceneCamera {
        WallpaperEngineSceneCamera(
            center: sceneValue(json["center"]),
            eye: sceneValue(json["eye"]),
            up: sceneValue(json["up"]),
            nearZ: doubleValue(json["nearz"]),
            farZ: doubleValue(json["farz"]),
            fov: doubleValue(json["fov"]),
            rawFields: sceneObjectValue(json)
        )
    }

    private func parseDocumentObject(
        _ json: [String: Any],
        container: WallpaperEngineSceneAssetStore
    ) -> WallpaperEngineSceneObject {
        WallpaperEngineSceneObject(
            id: json["id"] as? Int ?? -1,
            name: objectStringName(json["name"]),
            kind: objectKind(json),
            parentID: json["parent"] as? Int,
            dependencies: json["dependencies"] as? [Int] ?? [],
            origin: sceneValue(json["origin"]),
            scale: sceneValue(json["scale"]),
            angles: sceneValue(json["angles"]),
            visible: sceneValue(json["visible"]),
            alpha: sceneValue(json["alpha"]),
            size: sceneValue(json["size"]),
            image: (json["image"] as? String).map {
                parseImageObject(path: $0, json: json, container: container)
            },
            text: parseTextObject(json),
            sound: parseSoundObject(json),
            particle: parseParticleObject(json, container: container)
        )
    }

    private func parseImageObject(
        path: String,
        json: [String: Any],
        container: WallpaperEngineSceneAssetStore
    ) -> WallpaperEngineImageObject {
        let modelPath = path.normalizedWallpaperEnginePath

        return WallpaperEngineImageObject(
            modelPath: modelPath,
            model: parseModel(path: modelPath, container: container),
            effects: (json["effects"] as? [[String: Any]] ?? []).compactMap {
                parseImageEffect($0, container: container)
            },
            animationLayers: (json["animationlayers"] as? [[String: Any]] ?? []).map(parseImageAnimationLayer)
        )
    }

    private func parseTextObject(_ json: [String: Any]) -> WallpaperEngineTextObject? {
        guard let rawText = json["text"] else {
            return nil
        }

        let text: String
        let script: String?
        let scriptProperties: [String: WallpaperEngineSceneValue]

        if let stringText = rawText as? String {
            text = stringText
            script = nil
            scriptProperties = [:]
        } else if let objectText = rawText as? [String: Any] {
            text = objectText["value"] as? String ?? ""
            script = objectText["script"] as? String
            scriptProperties = sceneObjectValue(objectText["scriptproperties"] as? [String: Any] ?? [:])
        } else {
            text = ""
            script = nil
            scriptProperties = [:]
        }

        return WallpaperEngineTextObject(
            text: text,
            script: script,
            scriptProperties: scriptProperties,
            fontPath: (json["font"] as? String)?.normalizedWallpaperEnginePath,
            pointSize: sceneValue(json["pointsize"]),
            color: sceneValue(json["color"]),
            alignment: json["horizontalalign"] as? String ?? json["alignment"] as? String,
            verticalAlignment: json["verticalalign"] as? String
        )
    }

    private func parseSoundObject(_ json: [String: Any]) -> WallpaperEngineSoundObject? {
        guard let sounds = json["sound"] as? [Any] else {
            return nil
        }

        return WallpaperEngineSoundObject(
            soundPaths: sounds.compactMap { ($0 as? String)?.normalizedWallpaperEnginePath },
            playbackMode: json["playbackmode"] as? String
        )
    }

    private func parseParticleObject(
        _ json: [String: Any],
        container: WallpaperEngineSceneAssetStore
    ) -> WallpaperEngineParticleObject? {
        guard let particle = json["particle"] else {
            return nil
        }

        if let path = particle as? String {
            let normalizedPath = path.normalizedWallpaperEnginePath
            return WallpaperEngineParticleObject(
                particlePath: normalizedPath,
                definition: parseParticleDefinition(path: normalizedPath, json: nil, container: container),
                instanceOverride: sceneObjectValue(json["instanceoverride"] as? [String: Any] ?? [:])
            )
        }

        if let particleJSON = particle as? [String: Any] {
            return WallpaperEngineParticleObject(
                particlePath: nil,
                definition: parseParticleDefinition(path: nil, json: particleJSON, container: container),
                instanceOverride: sceneObjectValue(json["instanceoverride"] as? [String: Any] ?? [:])
            )
        }

        return nil
    }

    private func parseModel(
        path: String,
        container: WallpaperEngineSceneAssetStore
    ) -> WallpaperEngineModel? {
        guard let json = container.jsonObject(for: path),
              let materialPath = (json["material"] as? String)?.normalizedWallpaperEnginePath else {
            return nil
        }

        return WallpaperEngineModel(
            path: path.normalizedWallpaperEnginePath,
            materialPath: materialPath,
            material: parseMaterial(path: materialPath, container: container),
            width: intValue(json["width"]),
            height: intValue(json["height"]),
            solidLayer: boolValue(json["solidlayer"]) ?? false,
            fullScreen: boolValue(json["fullscreen"]) ?? false,
            passthrough: boolValue(json["passthrough"]) ?? false,
            autoSize: boolValue(json["autosize"]) ?? false,
            noPadding: boolValue(json["nopadding"]) ?? false,
            puppet: json["puppet"] as? String
        )
    }

    private func parseMaterial(
        path: String,
        container: WallpaperEngineSceneAssetStore
    ) -> WallpaperEngineMaterial? {
        guard let json = container.jsonObject(for: path) else {
            return nil
        }

        return WallpaperEngineMaterial(
            path: path.normalizedWallpaperEnginePath,
            passes: (json["passes"] as? [[String: Any]] ?? []).map(parseMaterialPass)
        )
    }

    private func parseMaterialPass(_ json: [String: Any]) -> WallpaperEngineMaterialPass {
        WallpaperEngineMaterialPass(
            blending: json["blending"] as? String ?? "normal",
            cullMode: json["cullmode"] as? String ?? "nocull",
            depthTest: json["depthtest"] as? String ?? "disabled",
            depthWrite: json["depthwrite"] as? String ?? "disabled",
            shader: json["shader"] as? String ?? "",
            textures: textureMap(json["textures"]),
            userTextures: textureMap(json["usertextures"]),
            combos: intMap(json["combos"]),
            constants: sceneObjectValue(json["constantshadervalues"] as? [String: Any] ?? [:])
        )
    }

    private func parseImageEffect(
        _ json: [String: Any],
        container: WallpaperEngineSceneAssetStore
    ) -> WallpaperEngineImageEffect? {
        guard let filePath = (json["file"] as? String)?.normalizedWallpaperEnginePath else {
            return nil
        }

        return WallpaperEngineImageEffect(
            id: json["id"] as? Int ?? -1,
            name: json["name"] as? String ?? "",
            filePath: filePath,
            visible: sceneValue(json["visible"]),
            effect: parseEffect(path: filePath, container: container),
            passOverrides: (json["passes"] as? [[String: Any]] ?? []).map(parseEffectPassOverride)
        )
    }

    private func parseEffect(
        path: String,
        container: WallpaperEngineSceneAssetStore
    ) -> WallpaperEngineEffect? {
        guard let json = container.jsonObject(for: path) else {
            return nil
        }

        return WallpaperEngineEffect(
            path: path.normalizedWallpaperEnginePath,
            name: json["name"] as? String ?? "",
            description: json["description"] as? String ?? "",
            group: json["group"] as? String ?? "",
            preview: (json["preview"] as? String)?.normalizedWallpaperEnginePath,
            dependencies: (json["dependencies"] as? [Any] ?? []).compactMap {
                ($0 as? String)?.normalizedWallpaperEnginePath
            },
            passes: (json["passes"] as? [[String: Any]] ?? []).map {
                parseEffectPass($0, container: container)
            },
            fbos: (json["fbos"] as? [[String: Any]] ?? []).compactMap(parseFBO)
        )
    }

    private func parseEffectPass(
        _ json: [String: Any],
        container: WallpaperEngineSceneAssetStore
    ) -> WallpaperEngineEffectPass {
        let materialPath = (json["material"] as? String)?.normalizedWallpaperEnginePath

        return WallpaperEngineEffectPass(
            materialPath: materialPath,
            material: materialPath.flatMap { parseMaterial(path: $0, container: container) },
            binds: bindMap(json["bind"]),
            command: json["command"] as? String,
            source: json["source"] as? String,
            target: json["target"] as? String
        )
    }

    private func parseEffectPassOverride(_ json: [String: Any]) -> WallpaperEngineEffectPassOverride {
        WallpaperEngineEffectPassOverride(
            id: json["id"] as? Int ?? -1,
            combos: intMap(json["combos"]),
            constants: sceneObjectValue(json["constantshadervalues"] as? [String: Any] ?? [:]),
            textures: textureMap(json["textures"])
        )
    }

    private func parseFBO(_ json: [String: Any]) -> WallpaperEngineFBO? {
        guard let name = json["name"] as? String else {
            return nil
        }

        return WallpaperEngineFBO(
            name: name,
            format: json["format"] as? String ?? "rgba8888",
            scale: doubleValue(json["scale"]) ?? 1,
            unique: boolValue(json["unique"]) ?? false
        )
    }

    private func parseImageAnimationLayer(_ json: [String: Any]) -> WallpaperEngineImageAnimationLayer {
        WallpaperEngineImageAnimationLayer(
            id: json["id"] as? Int ?? -1,
            rate: sceneValue(json["rate"]),
            visible: sceneValue(json["visible"]),
            blend: sceneValue(json["blend"]),
            animation: sceneValue(json["animation"])
        )
    }

    private func parseParticleDefinition(
        path: String?,
        json inlineJSON: [String: Any]?,
        container: WallpaperEngineSceneAssetStore,
        visitedPaths: Set<String> = []
    ) -> WallpaperEngineParticleDefinition? {
        if let path {
            let normalizedPath = path.normalizedWallpaperEnginePath
            guard !visitedPaths.contains(normalizedPath) else {
                return nil
            }
        }

        guard let json = inlineJSON ?? path.flatMap({ container.jsonObject(for: $0) }) else {
            return nil
        }

        let materialPath = (json["material"] as? String)?.normalizedWallpaperEnginePath
        let normalizedPath = path?.normalizedWallpaperEnginePath
        let renderers = parseParticleComponents(json["renderer"])

        return WallpaperEngineParticleDefinition(
            path: normalizedPath,
            materialPath: materialPath,
            material: materialPath.flatMap { parseMaterial(path: $0, container: container) },
            animationMode: json["animationmode"] as? String ?? "sequence",
            sequenceMultiplier: doubleValue(json["sequencemultiplier"]),
            maxCount: intValue(json["maxcount"]),
            rendererNames: renderers.map(\.name),
            emitters: parseParticleComponents(json["emitter"]),
            initializers: parseParticleComponents(json["initializer"]),
            operators: parseParticleComponents(json["operator"]),
            renderers: renderers,
            controlPoints: parseParticleControlPoints(json["controlpoint"]),
            children: parseParticleChildren(json["children"]),
            rawFields: sceneObjectValue(json)
        )
    }

    private func resolveTransitiveReferences(
        container: WallpaperEngineSceneAssetStore,
        collector: inout WallpaperEngineSceneReferenceCollector
    ) {
        var processedModels = Set<String>()
        var processedMaterials = Set<String>()
        var processedEffects = Set<String>()
        var processedParticles = Set<String>()

        var madeProgress = true
        while madeProgress {
            madeProgress = false

            for model in collector.models.subtracting(processedModels).sorted() {
                processedModels.insert(model)
                madeProgress = true
                guard let json = container.jsonObject(for: model),
                      let material = json["material"] as? String else {
                    continue
                }
                collector.materials.insert(material.normalizedWallpaperEnginePath)
            }

            for material in collector.materials.subtracting(processedMaterials).sorted() {
                processedMaterials.insert(material)
                madeProgress = true
                guard let json = container.jsonObject(for: material),
                      let passes = json["passes"] as? [[String: Any]] else {
                    continue
                }

                for pass in passes {
                    if let shader = pass["shader"] as? String {
                        collector.shaders.insert(shader.normalizedWallpaperEnginePath)
                    }
                    collector.collectTextureArray(pass["textures"])
                    collector.collectTextureArray(pass["usertextures"])
                }
            }

            for effect in collector.effects.subtracting(processedEffects).sorted() {
                processedEffects.insert(effect)
                madeProgress = true
                guard let json = container.jsonObject(for: effect),
                      let passes = json["passes"] as? [[String: Any]] else {
                    continue
                }

                if let dependencies = json["dependencies"] as? [String] {
                    for dependency in dependencies {
                        collector.effects.insert(dependency.normalizedWallpaperEnginePath)
                    }
                }

                for pass in passes {
                    if let material = pass["material"] as? String {
                        collector.materials.insert(material.normalizedWallpaperEnginePath)
                    }
                }
            }

            for particle in collector.particles.subtracting(processedParticles).sorted() {
                processedParticles.insert(particle)
                madeProgress = true
                guard let json = container.jsonObject(for: particle) else {
                    continue
                }

                if let material = json["material"] as? String {
                    collector.materials.insert(material.normalizedWallpaperEnginePath)
                }
                if let children = json["children"] as? [[String: Any]] {
                    for child in children {
                        if let childParticle = child["particle"] as? String {
                            collector.particles.insert(childParticle.normalizedWallpaperEnginePath)
                        }
                    }
                }
            }
        }
    }

    private func sceneObjectValue(_ json: [String: Any]) -> [String: WallpaperEngineSceneValue] {
        json.reduce(into: [:]) { result, item in
            result[item.key] = sceneValue(item.value)
        }
    }

    private func parseProjectProperties(_ projectJSON: [String: Any]) -> [String: WallpaperEngineProjectProperty] {
        guard let general = projectJSON["general"] as? [String: Any],
              let properties = general["properties"] as? [String: Any] else {
            return [:]
        }

        return properties.reduce(into: [:]) { result, item in
            guard let propertyJSON = item.value as? [String: Any] else {
                return
            }
            result[item.key] = WallpaperEngineProjectProperty(
                type: propertyJSON["type"] as? String ?? "unknown",
                text: propertyJSON["text"] as? String,
                value: sceneValue(propertyJSON["value"]),
                index: intValue(propertyJSON["index"]),
                order: intValue(propertyJSON["order"]),
                minimum: sceneValue(propertyJSON["min"]),
                maximum: sceneValue(propertyJSON["max"]),
                step: sceneValue(propertyJSON["step"]),
                precision: intValue(propertyJSON["precision"]),
                fraction: boolValue(propertyJSON["fraction"]) ?? false,
                options: parseProjectPropertyOptions(propertyJSON["options"]),
                rawFields: sceneObjectValue(propertyJSON)
            )
        }
    }

    private func parseProjectPropertyOptions(_ rawValue: Any?) -> [WallpaperEngineProjectPropertyOption] {
        guard let options = rawValue as? [[String: Any]] else {
            return []
        }

        return options.map {
            WallpaperEngineProjectPropertyOption(
                label: $0["label"] as? String,
                value: sceneValue($0["value"])
            )
        }
    }

    private func parseParticleComponents(_ rawValue: Any?) -> [WallpaperEngineParticleComponent] {
        guard let components = rawValue as? [[String: Any]] else {
            return []
        }

        return components.map {
            WallpaperEngineParticleComponent(
                name: $0["name"] as? String ?? $0["type"] as? String ?? "unknown",
                rawFields: sceneObjectValue($0)
            )
        }
    }

    private func parseParticleControlPoints(_ rawValue: Any?) -> [WallpaperEngineParticleControlPoint] {
        guard let controlPoints = rawValue as? [[String: Any]] else {
            return []
        }

        return controlPoints.map {
            WallpaperEngineParticleControlPoint(
                index: intValue($0["index"]),
                name: $0["name"] as? String,
                rawFields: sceneObjectValue($0)
            )
        }
    }

    private func parseParticleChildren(_ rawValue: Any?) -> [WallpaperEngineParticleChild] {
        guard let children = rawValue as? [[String: Any]] else {
            return []
        }

        return children.map { child in
            WallpaperEngineParticleChild(
                particlePath: (child["particle"] as? String)?.normalizedWallpaperEnginePath,
                rawFields: sceneObjectValue(child)
            )
        }
    }

    private func sceneValue(_ value: Any?) -> WallpaperEngineSceneValue? {
        guard let value else {
            return nil
        }

        if value is NSNull {
            return .null
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }

            let double = number.doubleValue
            if double.rounded() == double {
                return .int(number.intValue)
            }
            return .double(double)
        }
        if let bool = value as? Bool {
            return .bool(bool)
        }
        if let int = value as? Int {
            return .int(int)
        }
        if let double = value as? Double {
            if double.rounded() == double {
                return .int(Int(double))
            }
            return .double(double)
        }
        if let string = value as? String {
            return parseVectorString(string) ?? .string(string)
        }
        if let array = value as? [Any] {
            return .array(array.map { sceneValue($0) ?? .null })
        }
        if let object = value as? [String: Any] {
            if let user = object["user"] as? String {
                return .user(property: user, value: sceneValue(object["value"]))
            }
            if let animation = object["animation"] as? [String: Any] {
                return .animation(
                    value: sceneValue(object["value"]),
                    previewValue: sceneValue(animation["previewvalue"])
                )
            }
            return .object(sceneObjectValue(object))
        }

        return nil
    }

    private func parseVectorString(_ value: String) -> WallpaperEngineSceneValue? {
        let numbers = value
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }

        switch numbers.count {
        case 2:
            return .vector2(WallpaperEngineSceneVector2(x: numbers[0], y: numbers[1]))
        case 3:
            return .vector3(WallpaperEngineSceneVector3(x: numbers[0], y: numbers[1], z: numbers[2]))
        case 4:
            return .vector4(WallpaperEngineSceneVector4(x: numbers[0], y: numbers[1], z: numbers[2], w: numbers[3]))
        default:
            return nil
        }
    }

    private func textureMap(_ rawValue: Any?) -> [Int: String] {
        guard let values = rawValue as? [Any] else {
            return [:]
        }

        var result: [Int: String] = [:]
        for (index, value) in values.enumerated() {
            if let texture = value as? String, !texture.isEmpty {
                result[index] = texture.normalizedWallpaperEnginePath
            } else if let object = value as? [String: Any],
                      let texture = object["name"] as? String,
                      !texture.isEmpty {
                result[index] = texture.normalizedWallpaperEnginePath
            }
        }
        return result
    }

    private func bindMap(_ rawValue: Any?) -> [Int: String] {
        guard let values = rawValue as? [[String: Any]] else {
            return [:]
        }

        return values.reduce(into: [:]) { result, bind in
            guard let index = intValue(bind["index"]),
                  let name = bind["name"] as? String else {
                return
            }
            result[index] = name
        }
    }

    private func intMap(_ rawValue: Any?) -> [String: Int] {
        guard let object = rawValue as? [String: Any] else {
            return [:]
        }

        return object.reduce(into: [:]) { result, item in
            if let value = intValue(item.value) {
                result[item.key] = value
            }
        }
    }

    private func boolValue(_ rawValue: Any?) -> Bool? {
        if let value = rawValue as? Bool {
            return value
        }
        if let value = rawValue as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    private func intValue(_ rawValue: Any?) -> Int? {
        if let value = rawValue as? Int {
            return value
        }
        if let value = rawValue as? NSNumber {
            return value.intValue
        }
        if let value = rawValue as? String {
            return Int(value)
        }
        return nil
    }

    private func doubleValue(_ rawValue: Any?) -> Double? {
        if let value = rawValue as? Double {
            return value
        }
        if let value = rawValue as? NSNumber {
            return value.doubleValue
        }
        if let value = rawValue as? String {
            return Double(value)
        }
        return nil
    }
}

private struct WallpaperEngineSceneParseContext {
    let container: WallpaperEngineSceneAssetStore
    let project: WallpaperEngineProjectDescriptor
    let sceneFile: String
    let scene: [String: Any]
    let objectsJSON: [[String: Any]]
    let objectSummaries: [WallpaperEngineSceneObjectSummary]
}

private struct WallpaperEngineSceneReferenceCollector {
    var models = Set<String>()
    var materials = Set<String>()
    var effects = Set<String>()
    var particles = Set<String>()
    var textures = Set<String>()
    var shaders = Set<String>()
    var sounds = Set<String>()
    var fonts = Set<String>()
    var scriptFiles = Set<String>()
    var inlineScriptCount = 0

    mutating func collect(fromObject object: [String: Any]) {
        if let image = object["image"] as? String {
            models.insert(image.normalizedWallpaperEnginePath)
        }

        if let soundArray = object["sound"] as? [Any] {
            for case let sound as String in soundArray {
                sounds.insert(sound.normalizedWallpaperEnginePath)
            }
        }

        if let particle = object["particle"] as? String {
            particles.insert(particle.normalizedWallpaperEnginePath)
        }

        if let font = object["font"] as? String {
            fonts.insert(font.normalizedWallpaperEnginePath)
        }

        if let text = object["text"] as? [String: Any],
           let script = text["script"] as? String {
            collectScript(script)
        }

        if let effectsArray = object["effects"] as? [[String: Any]] {
            for effect in effectsArray {
                if let file = effect["file"] as? String {
                    effects.insert(file.normalizedWallpaperEnginePath)
                }
                if let passes = effect["passes"] as? [[String: Any]] {
                    for pass in passes {
                        collectTextureArray(pass["textures"])
                    }
                }
            }
        }
    }

    mutating func collectTextureArray(_ rawValue: Any?) {
        guard let values = rawValue as? [Any] else {
            return
        }

        for value in values {
            if let texture = value as? String, !texture.isEmpty {
                textures.insert(textureReferencePath(texture))
            } else if let object = value as? [String: Any],
                      let texture = object["name"] as? String,
                      !texture.isEmpty {
                textures.insert(textureReferencePath(texture))
            }
        }
    }

    func makeReferences() -> WallpaperEngineSceneAssetReferences {
        WallpaperEngineSceneAssetReferences(
            models: models.sorted(),
            materials: materials.sorted(),
            effects: effects.sorted(),
            particles: particles.sorted(),
            textures: textures.sorted(),
            shaders: shaders.sorted(),
            sounds: sounds.sorted(),
            fonts: fonts.sorted(),
            scriptFiles: scriptFiles.sorted(),
            inlineScriptCount: inlineScriptCount
        )
    }

    private mutating func collectScript(_ script: String) {
        if script.contains("\n") || script.contains("return ") || script.contains("function ") {
            inlineScriptCount += 1
        } else {
            scriptFiles.insert(script.normalizedWallpaperEnginePath)
        }
    }

    private func textureReferencePath(_ value: String) -> String {
        let normalized = value.normalizedWallpaperEnginePath
        if normalized.wallpaperEnginePathExtension == "tex" {
            return normalized
        }
        if normalized.hasPrefix("_rt_") || normalized.hasPrefix("_alias_") {
            return normalized
        }
        return "materials/\(normalized).tex"
    }
}
