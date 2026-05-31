import Foundation

enum WallpaperEngineShaderStage: String, Equatable, Sendable {
    case vertex
    case fragment
    case include
}

struct WallpaperEngineShaderMetadata: Equatable, Sendable {
    let path: String
    let stage: WallpaperEngineShaderStage
    let textures: [WallpaperEngineShaderTexture]
    let parameters: [WallpaperEngineShaderParameter]
    let combos: [WallpaperEngineShaderCombo]
    let includes: [String]
    let requires: [String]
}

struct WallpaperEngineShaderTexture: Equatable, Sendable {
    let index: Int?
    let uniformName: String
    let samplerType: String
    let materialName: String?
    let label: String?
    let mode: String?
    let defaultTexture: String?
    let hidden: Bool
    let metadata: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineShaderParameter: Equatable, Sendable {
    let uniformName: String
    let valueType: String
    let materialName: String?
    let label: String?
    let defaultValue: WallpaperEngineSceneValue?
    let metadata: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineShaderCombo: Equatable, Sendable {
    let name: String
    let materialName: String?
    let defaultValue: WallpaperEngineSceneValue?
    let disabledByDefault: Bool
    let metadata: [String: WallpaperEngineSceneValue]
}

struct WallpaperEngineShaderParser {
    func parseShader(
        source: String,
        path: String,
        stage: WallpaperEngineShaderStage
    ) -> WallpaperEngineShaderMetadata {
        let metadataSource = WallpaperEngineShaderPreprocessor()
            .sourceForMetadataParsing(source: source, stage: stage)
        var textures: [WallpaperEngineShaderTexture] = []
        var parameters: [WallpaperEngineShaderParameter] = []
        var combos: [WallpaperEngineShaderCombo] = []
        var includes: [String] = []
        var requires: [String] = []

        for rawLine in metadataSource.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if let combo = parseCombo(line) {
                combos.append(combo)
            }
            if let include = parseDirective(line, name: "#include") {
                includes.append(include)
            }
            if let require = parseDirective(line, name: "#require") {
                requires.append(require)
            }
            if let uniform = parseUniform(line) {
                switch uniform {
                case .texture(let texture):
                    textures.append(texture)
                case .parameter(let parameter):
                    parameters.append(parameter)
                }
            }
        }

        return WallpaperEngineShaderMetadata(
            path: path.normalizedWallpaperEnginePath,
            stage: stage,
            textures: textures,
            parameters: parameters,
            combos: combos,
            includes: includes,
            requires: requires
        )
    }

    private enum ParsedUniform {
        case texture(WallpaperEngineShaderTexture)
        case parameter(WallpaperEngineShaderParameter)
    }

    private func parseCombo(_ line: String) -> WallpaperEngineShaderCombo? {
        let prefix: String
        let disabledByDefault: Bool

        if line.hasPrefix("// [COMBO] ") {
            prefix = "// [COMBO] "
            disabledByDefault = false
        } else if line.hasPrefix("// [OFF_COMBO] ") {
            prefix = "// [OFF_COMBO] "
            disabledByDefault = true
        } else {
            return nil
        }

        let metadata = parseMetadata(String(line.dropFirst(prefix.count)))
        guard case .string(let name)? = metadata["combo"] else {
            return nil
        }

        return WallpaperEngineShaderCombo(
            name: name,
            materialName: metadata["material"]?.stringValue,
            defaultValue: metadata["default"],
            disabledByDefault: disabledByDefault,
            metadata: metadata
        )
    }

    private func parseDirective(_ line: String, name: String) -> String? {
        guard line.hasPrefix(name) else {
            return nil
        }

        return parseWallpaperEngineShaderDirectivePath(String(line.dropFirst(name.count)))
    }

    private func parseUniform(_ line: String) -> ParsedUniform? {
        guard let uniformRange = line.range(of: "uniform "),
              let semicolonIndex = line.firstIndex(of: ";"),
              let commentRange = line.range(of: "//", range: semicolonIndex..<line.endIndex),
              semicolonIndex < commentRange.lowerBound else {
            return nil
        }

        let declaration = line[uniformRange.upperBound..<semicolonIndex]
        let declarationParts = declaration.split(whereSeparator: \.isWhitespace).map(String.init)
        guard declarationParts.count >= 2 else {
            return nil
        }

        let type = declarationParts[declarationParts.count - 2]
        let uniformName = declarationParts[declarationParts.count - 1]
            .split(separator: "[", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        let metadata = parseMetadata(String(line[commentRange.upperBound...]))

        if type.hasPrefix("sampler") {
            return .texture(WallpaperEngineShaderTexture(
                index: textureIndex(uniformName),
                uniformName: uniformName,
                samplerType: type,
                materialName: metadata["material"]?.stringValue,
                label: metadata["label"]?.stringValue,
                mode: metadata["mode"]?.stringValue,
                defaultTexture: metadata["default"]?.stringValue?.normalizedWallpaperEnginePath,
                hidden: metadata["hidden"]?.boolValue ?? false,
                metadata: metadata
            ))
        }

        return .parameter(WallpaperEngineShaderParameter(
            uniformName: uniformName,
            valueType: type,
            materialName: metadata["material"]?.stringValue,
            label: metadata["label"]?.stringValue,
            defaultValue: metadata["default"],
            metadata: metadata
        ))
    }

    private func textureIndex(_ uniformName: String) -> Int? {
        guard uniformName.hasPrefix("g_Texture") else {
            return nil
        }
        return Int(uniformName.dropFirst("g_Texture".count))
    }

    private func parseMetadata(_ rawValue: String) -> [String: WallpaperEngineSceneValue] {
        guard let start = rawValue.firstIndex(of: "{"),
              let end = rawValue.lastIndex(of: "}"),
              start <= end else {
            return [:]
        }

        let json = String(rawValue[start...end])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        return object.reduce(into: [:]) { result, item in
            result[item.key] = sceneValue(item.value)
        }
    }

    private func sceneValue(_ value: Any?) -> WallpaperEngineSceneValue {
        guard let value else {
            return .null
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
        if let string = value as? String {
            return parseVectorString(string) ?? .string(string)
        }
        if let array = value as? [Any] {
            return .array(array.map(sceneValue))
        }
        if let object = value as? [String: Any] {
            return .object(object.reduce(into: [:]) { result, item in
                result[item.key] = sceneValue(item.value)
            })
        }

        return .null
    }

    private func parseVectorString(_ value: String) -> WallpaperEngineSceneValue? {
        let numbers = value
            .replacingOccurrences(of: ",", with: " ")
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
}

private extension WallpaperEngineSceneValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }
}
