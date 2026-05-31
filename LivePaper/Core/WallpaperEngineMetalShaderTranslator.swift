import Foundation

struct WallpaperEngineMetalShader: Equatable, Sendable {
    let usage: String
    let shaderName: String
    let vertexFunctionName: String
    let fragmentFunctionName: String
    let source: String
    let textureBindings: [WallpaperEngineShaderTextureBinding]
    let parameterBindings: [WallpaperEngineShaderParameterBinding]
    let builtinUniforms: [WallpaperEngineMetalBuiltinUniform]
    let diagnostics: [String]
}

struct WallpaperEngineMetalBuiltinUniform: Equatable, Sendable {
    let uniformName: String
    let valueType: String
    let textureIndex: Int?
    let kind: WallpaperEngineMetalBuiltinUniformKind
}

enum WallpaperEngineMetalBuiltinUniformKind: String, Equatable, Sendable {
    case daytime
    case modelViewProjectionMatrix
    case time
    case texelSize
    case texelSizeHalf
    case textureReductionScale
    case textureResolution
    case textureRotation
    case textureTranslation
}

struct WallpaperEngineMetalShaderTranslator {
    func translate(
        preparedShader: WallpaperEnginePreparedShader,
        binding: WallpaperEngineShaderBindingPlan
    ) -> WallpaperEngineMetalShader? {
        guard preparedShader.vertexSource != nil || preparedShader.fragmentSource != nil else {
            return nil
        }

        let suffix = functionSuffix(for: preparedShader.usage)
        let vertexFunctionName = "we_vertex_\(suffix)"
        let fragmentFunctionName = "we_fragment_\(suffix)"
        let varyings = vertexVaryings(in: preparedShader.vertexSource)
        let builtinUniforms = builtinUniforms(in: preparedShader)
        let helperFunctions = shaderHelperFunctions(from: preparedShader)
        let helperFunctionNames = Set(helperFunctions.map(\.name))
        let helperExtraArguments = helperContextArguments(textures: binding.textures)
        let uniformFields = uniformFields(for: binding.parameters)
            + uniformFields(for: builtinUniforms)
        let textureArguments = textureArguments(for: binding.textures)
        let fragmentBody = fragmentBody(
            fragmentSource: preparedShader.fragmentSource,
            textures: binding.textures,
            parameters: binding.parameters,
            builtinUniforms: builtinUniforms,
            varyings: varyings,
            helperFunctionNames: helperFunctionNames,
            helperExtraArguments: helperExtraArguments
        )
        let diagnostics = translationDiagnostics(
            preparedShader: preparedShader,
            fragmentBody: fragmentBody
        )

        let source = [
            metalHeader(combos: preparedShader.combos),
            vertexInputStruct(),
            vertexOutputStruct(varyings: varyings),
            uniformStruct(fields: uniformFields),
            helperFunctionSource(
                helperFunctions,
                textures: binding.textures,
                parameters: binding.parameters,
                builtinUniforms: builtinUniforms,
                helperFunctionNames: helperFunctionNames,
                helperExtraArguments: helperExtraArguments
            ),
            vertexFunction(
                name: vertexFunctionName,
                textureArguments: textureArguments,
                varyings: varyings,
                vertexSource: preparedShader.vertexSource,
                parameters: binding.parameters,
                builtinUniforms: builtinUniforms,
                textures: binding.textures,
                helperFunctionNames: helperFunctionNames,
                helperExtraArguments: helperExtraArguments
            ),
            fragmentFunction(
                name: fragmentFunctionName,
                textureArguments: textureArguments,
                body: fragmentBody.body
            )
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        return WallpaperEngineMetalShader(
            usage: preparedShader.usage,
            shaderName: preparedShader.shaderName,
            vertexFunctionName: vertexFunctionName,
            fragmentFunctionName: fragmentFunctionName,
            source: source,
            textureBindings: binding.textures,
            parameterBindings: binding.parameters,
            builtinUniforms: builtinUniforms,
            diagnostics: diagnostics + fragmentBody.diagnostics
        )
    }

    private func metalHeader(combos: [String: Int]) -> String {
        let comboDefines = combos.keys.sorted()
            .map { "#define \($0) \(combos[$0] ?? 0)" }
            .joined(separator: "\n")

        return [
            "#include <metal_stdlib>",
            "using namespace metal;",
            "constant float M_PI = 3.14159265358979323846;",
            "#define CAST2(value) float2(value)",
            "#define CAST3(value) float3(value)",
            "#define CAST4(value) float4(value)",
            "#define frac(value) fract(value)",
            "#define lerp mix",
            "#define saturate(value) clamp(value, 0.0, 1.0)",
            comboDefines
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func vertexInputStruct() -> String {
        """
        struct WEVertexIn {
            float3 a_Position [[attribute(0)]];
            float2 a_TexCoord [[attribute(1)]];
        };
        """
    }

    private func vertexOutputStruct(varyings: [ShaderVarying]) -> String {
        let fields = varyingFields(varyings).map {
            "    \(metalType($0.type)) \($0.outputName);"
        }.joined(separator: "\n")

        return """
        struct WEVertexOut {
            float4 position [[position]];
        \(fields)
        };
        """
    }

    private func uniformStruct(fields: [ShaderUniformField]) -> String {
        let fieldLines = fields.isEmpty
            ? "    float _unused;"
            : fields.map { "    \($0.type) \($0.name);" }.joined(separator: "\n")

        return """
        struct WEUniforms {
        \(fieldLines)
        };
        """
    }

    private func vertexFunction(
        name: String,
        textureArguments: [String],
        varyings: [ShaderVarying],
        vertexSource: String?,
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform],
        textures: [WallpaperEngineShaderTextureBinding],
        helperFunctionNames: Set<String>,
        helperExtraArguments: [String]
    ) -> String {
        let body: String
        if let vertexSource,
           let mainBody = shaderMainBody(in: vertexSource),
           mainBody.contains("gl_Position") {
            body = translateVertexBody(
                mainBody,
                varyings: varyings,
                parameters: parameters,
                builtinUniforms: builtinUniforms,
                textures: textures,
                helperFunctionNames: helperFunctionNames,
                helperExtraArguments: helperExtraArguments
            )
        } else {
            let assignments = varyingFields(varyings).map { varying in
                let expression = varyingExpression(
                    for: varying,
                    vertexSource: vertexSource,
                    parameters: parameters,
                    builtinUniforms: builtinUniforms
                )
                return "    out.\(varying.outputName) = \(expression);"
            }.joined(separator: "\n")
            let positionExpression = vertexPositionExpression(
                vertexSource: vertexSource,
                parameters: parameters,
                builtinUniforms: builtinUniforms
            )
            body = """
                out.position = \(positionExpression);
            \(assignments)
            """
        }

        let arguments = ([
            "WEVertexIn vertexIn [[stage_in]]"
        ] + textureArguments + [
            "constant WEUniforms& uniforms [[buffer(1)]]"
        ])
        .map { "    \($0)" }
        .joined(separator: ",\n")

        return """
        vertex WEVertexOut \(name)(
        \(arguments)
        ) {
            WEVertexOut out;
        \(body)
            return out;
        }
        """
    }

    private func fragmentFunction(
        name: String,
        textureArguments: [String],
        body: String
    ) -> String {
        let arguments = ([
            "WEVertexOut stageIn [[stage_in]]"
        ] + textureArguments + [
            "constant WEUniforms& uniforms [[buffer(1)]]"
        ])
        .map { "    \($0)" }
        .joined(separator: ",\n")

        return """
        fragment float4 \(name)(
        \(arguments)
        ) {
        \(body)
        }
        """
    }

    private func textureArguments(for bindings: [WallpaperEngineShaderTextureBinding]) -> [String] {
        bindings.flatMap { binding -> [String] in
            guard let index = binding.index else {
                return []
            }
            return [
                "texture2d<float> \(binding.uniformName) [[texture(\(index))]]",
                "sampler \(samplerName(for: binding.uniformName)) [[sampler(\(index))]]"
            ]
        }
    }

    private func uniformFields(
        for parameters: [WallpaperEngineShaderParameterBinding]
    ) -> [ShaderUniformField] {
        parameters.map {
            ShaderUniformField(
                name: $0.uniformName,
                type: metalType($0.valueType)
            )
        }
    }

    private func uniformFields(
        for builtinUniforms: [WallpaperEngineMetalBuiltinUniform]
    ) -> [ShaderUniformField] {
        builtinUniforms.map {
            ShaderUniformField(
                name: $0.uniformName,
                type: metalType($0.valueType)
            )
        }
    }

    private func builtinUniforms(
        in preparedShader: WallpaperEnginePreparedShader
    ) -> [WallpaperEngineMetalBuiltinUniform] {
        let source = [preparedShader.vertexSource, preparedShader.fragmentSource]
            .compactMap { $0 }
            .joined(separator: "\n")
        var uniforms: [WallpaperEngineMetalBuiltinUniform] = []
        appendGlobalBuiltin(
            uniformName: "g_Time",
            valueType: "float",
            kind: .time,
            source: source,
            uniforms: &uniforms
        )
        appendGlobalBuiltin(
            uniformName: "g_Daytime",
            valueType: "float",
            kind: .daytime,
            source: source,
            uniforms: &uniforms
        )
        appendGlobalBuiltin(
            uniformName: "g_TextureReductionScale",
            valueType: "float",
            kind: .textureReductionScale,
            source: source,
            uniforms: &uniforms
        )
        appendGlobalBuiltin(
            uniformName: "g_ModelViewProjectionMatrix",
            valueType: "mat4",
            kind: .modelViewProjectionMatrix,
            source: source,
            uniforms: &uniforms
        )
        appendGlobalBuiltin(
            uniformName: "g_TexelSize",
            valueType: "vec2",
            kind: .texelSize,
            source: source,
            uniforms: &uniforms
        )
        appendGlobalBuiltin(
            uniformName: "g_TexelSizeHalf",
            valueType: "vec2",
            kind: .texelSizeHalf,
            source: source,
            uniforms: &uniforms
        )
        uniforms.append(contentsOf: textureBuiltins(
            pattern: #"\bg_Texture(\d+)Resolution\b"#,
            valueType: "vec4",
            kind: .textureResolution,
            source: source
        ))
        uniforms.append(contentsOf: textureBuiltins(
            pattern: #"\bg_Texture(\d+)Rotation\b"#,
            valueType: "vec4",
            kind: .textureRotation,
            source: source
        ))
        uniforms.append(contentsOf: textureBuiltins(
            pattern: #"\bg_Texture(\d+)Translation\b"#,
            valueType: "vec2",
            kind: .textureTranslation,
            source: source
        ))

        var seen = Set<String>()
        return uniforms
            .filter { seen.insert($0.uniformName).inserted }
            .sorted(by: builtinUniformSort)
    }

    private func appendGlobalBuiltin(
        uniformName: String,
        valueType: String,
        kind: WallpaperEngineMetalBuiltinUniformKind,
        source: String,
        uniforms: inout [WallpaperEngineMetalBuiltinUniform]
    ) {
        guard sourceContainsWord(uniformName, in: source) else {
            return
        }
        uniforms.append(WallpaperEngineMetalBuiltinUniform(
            uniformName: uniformName,
            valueType: valueType,
            textureIndex: nil,
            kind: kind
        ))
    }

    private func textureBuiltins(
        pattern: String,
        valueType: String,
        kind: WallpaperEngineMetalBuiltinUniformKind,
        source: String
    ) -> [WallpaperEngineMetalBuiltinUniform] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let matches = regex.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
        return matches.compactMap { match -> WallpaperEngineMetalBuiltinUniform? in
            guard match.numberOfRanges == 2,
                  let nameRange = Range(match.range(at: 0), in: source),
                  let indexRange = Range(match.range(at: 1), in: source),
                  let textureIndex = Int(String(source[indexRange])) else {
                return nil
            }
            let uniformName = String(source[nameRange])
            return WallpaperEngineMetalBuiltinUniform(
                uniformName: uniformName,
                valueType: valueType,
                textureIndex: textureIndex,
                kind: kind
            )
        }
    }

    private func sourceContainsWord(_ token: String, in source: String) -> Bool {
        let escapedToken = NSRegularExpression.escapedPattern(for: token)
        let pattern = #"(?<![A-Za-z0-9_\.])\#(escapedToken)(?![A-Za-z0-9_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }

        return regex.firstMatch(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        ) != nil
    }

    private func builtinUniformSort(
        lhs: WallpaperEngineMetalBuiltinUniform,
        rhs: WallpaperEngineMetalBuiltinUniform
    ) -> Bool {
        let lhsKey = builtinUniformSortKey(lhs)
        let rhsKey = builtinUniformSortKey(rhs)
        return lhsKey == rhsKey
            ? lhs.uniformName < rhs.uniformName
            : lhsKey < rhsKey
    }

    private func builtinUniformSortKey(_ uniform: WallpaperEngineMetalBuiltinUniform) -> String {
        let textureIndex = uniform.textureIndex.map { String(format: "%03d", $0) } ?? "___"
        switch uniform.kind {
        case .time:
            return "000:\(textureIndex)"
        case .daytime:
            return "001:\(textureIndex)"
        case .modelViewProjectionMatrix:
            return "010:\(textureIndex)"
        case .textureReductionScale:
            return "020:\(textureIndex)"
        case .textureResolution:
            return "100:\(textureIndex)"
        case .textureRotation:
            return "110:\(textureIndex)"
        case .textureTranslation:
            return "120:\(textureIndex)"
        case .texelSize:
            return "200:\(textureIndex)"
        case .texelSizeHalf:
            return "210:\(textureIndex)"
        }
    }

    private func vertexVaryings(in source: String?) -> [ShaderVarying] {
        guard let source else {
            return [ShaderVarying(type: "float2", name: "v_TexCoord")]
        }

        let declarations = source.components(separatedBy: .newlines).compactMap { line -> ShaderVarying? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("out ") else {
                return nil
            }
            let declaration = trimmed.dropFirst("out ".count)
                .split(separator: ";", maxSplits: 1)
                .first
                .map(String.init) ?? ""
            let parts = declaration.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else {
                return nil
            }
            return shaderVarying(type: parts[0], rawName: parts[1])
        }

        return declarations.isEmpty
            ? [ShaderVarying(type: "float2", name: "v_TexCoord")]
            : declarations
    }

    private func shaderVarying(type: String, rawName: String) -> ShaderVarying {
        let pattern = #"^([A-Za-z_][A-Za-z0-9_]*)\s*\[\s*(\d+)\s*\]$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: rawName,
                range: NSRange(rawName.startIndex..<rawName.endIndex, in: rawName)
              ),
              match.numberOfRanges == 3,
              let nameRange = Range(match.range(at: 1), in: rawName),
              let countRange = Range(match.range(at: 2), in: rawName),
              let arrayCount = Int(rawName[countRange]) else {
            return ShaderVarying(type: type, name: rawName)
        }
        return ShaderVarying(type: type, name: String(rawName[nameRange]), arrayCount: arrayCount)
    }

    private func varyingFields(_ varyings: [ShaderVarying]) -> [ShaderVaryingField] {
        varyings.flatMap { varying -> [ShaderVaryingField] in
            guard let arrayCount = varying.arrayCount else {
                return [ShaderVaryingField(type: varying.type, sourceName: varying.name, outputName: varying.name)]
            }
            return (0..<arrayCount).map {
                ShaderVaryingField(
                    type: varying.type,
                    sourceName: varying.name,
                    outputName: "\(varying.name)_\($0)",
                    arrayIndex: $0
                )
            }
        }
    }

    private func varyingExpression(
        for varying: ShaderVaryingField,
        vertexSource: String?,
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform]
    ) -> String {
        let source = vertexSource ?? ""
        let assignmentTarget = varying.arrayIndex.map { "\(varying.sourceName)[\($0)]" } ?? varying.sourceName
        if let expression = assignmentExpression(to: assignmentTarget, in: source) {
            return translateVertexExpression(
                expression,
                parameters: parameters,
                builtinUniforms: builtinUniforms
            )
        }

        switch metalType(varying.type) {
        case "float2":
            return "vertexIn.a_TexCoord"
        case "float3":
            return "vertexIn.a_Position"
        case "float4":
            return "float4(vertexIn.a_Position, 1.0)"
        default:
            return "\(metalType(varying.type))(0)"
        }
    }

    private func vertexPositionExpression(
        vertexSource: String?,
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform]
    ) -> String {
        guard let expression = assignmentExpression(to: "gl_Position", in: vertexSource ?? "") else {
            return "float4(vertexIn.a_Position.xy, 0.0, 1.0)"
        }
        return translateVertexExpression(
            expression,
            parameters: parameters,
            builtinUniforms: builtinUniforms
        )
    }

    private func translateVertexExpression(
        _ expression: String,
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform]
    ) -> String {
        var result = stripComments(expression)
        result = replaceGLSLTypes(result)
        result = replaceWord("a_Position", with: "vertexIn.a_Position", in: result)
        result = replaceWord("a_TexCoord", with: "vertexIn.a_TexCoord", in: result)

        for parameter in parameters {
            result = replaceWord(parameter.uniformName, with: "uniforms.\(parameter.uniformName)", in: result)
        }
        for builtinUniform in builtinUniforms {
            result = replaceWord(
                builtinUniform.uniformName,
                with: "uniforms.\(builtinUniform.uniformName)",
                in: result
            )
        }
        result = rewriteMulCalls(in: result)
        return result
    }

    private func fragmentBody(
        fragmentSource: String?,
        textures: [WallpaperEngineShaderTextureBinding],
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform],
        varyings: [ShaderVarying],
        helperFunctionNames: Set<String>,
        helperExtraArguments: [String]
    ) -> (body: String, diagnostics: [String]) {
        let source = fragmentSource ?? ""
        if let mainBody = shaderMainBody(in: source),
           mainBody.contains("gl_FragColor") || mainBody.contains("out_FragColor") {
            return (
                translateFragmentBody(
                    mainBody,
                    textures: textures,
                    parameters: parameters,
                    builtinUniforms: builtinUniforms,
                    varyings: varyings,
                    helperFunctionNames: helperFunctionNames,
                    helperExtraArguments: helperExtraArguments
                ),
                []
            )
        }

        if let expression = assignmentExpression(to: "out_FragColor", in: source)
            ?? assignmentExpression(to: "gl_FragColor", in: source) {
            let translatedExpression = translateFragmentExpression(
                expression,
                textures: textures,
                parameters: parameters,
                builtinUniforms: builtinUniforms,
                varyings: varyings,
                helperFunctionNames: helperFunctionNames,
                helperExtraArguments: helperExtraArguments
            )
            return (
                "    return \(translatedExpression);",
                []
            )
        }

        if let sample = firstTextureSample(in: source) {
            return (
                "    return \(sample.texture).sample(\(samplerName(for: sample.texture)), stageIn.\(sample.coordinate));",
                []
            )
        }

        if let texture0 = textures.first(where: { $0.index == 0 })?.uniformName {
            return (
                "    return \(texture0).sample(\(samplerName(for: texture0)), stageIn.v_TexCoord);",
                ["Fell back to sampling \(texture0) because the fragment body was not recognized."]
            )
        }

        return (
            "    return float4(0.0, 0.0, 0.0, 1.0);",
            ["Fell back to opaque black because the fragment body did not expose a texture sample."]
        )
    }

    private func assignmentExpression(to target: String, in source: String) -> String? {
        let escapedTarget = NSRegularExpression.escapedPattern(for: target)
        let pattern = #"\b\#(escapedTarget)\s*=\s*(.+?);"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ),
        let match = regex.firstMatch(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        ),
        match.numberOfRanges == 2,
        let range = Range(match.range(at: 1), in: source) else {
            return nil
        }

        return String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func translateFragmentExpression(
        _ expression: String,
        textures: [WallpaperEngineShaderTextureBinding],
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform],
        varyings: [ShaderVarying],
        helperFunctionNames: Set<String>,
        helperExtraArguments: [String]
    ) -> String {
        var result = stripComments(expression)
        result = replaceTextureSamples(in: result, textures: textures)
        result = replaceGLSLTypes(result)
        result = replaceWord("texture2D", with: "texSample2D", in: result)

        for parameter in parameters {
            result = replaceWord(parameter.uniformName, with: "uniforms.\(parameter.uniformName)", in: result)
        }
        for builtinUniform in builtinUniforms {
            result = replaceWord(
                builtinUniform.uniformName,
                with: "uniforms.\(builtinUniform.uniformName)",
                in: result
            )
        }
        result = replaceVaryingReferences(in: result, varyings: varyings, prefix: "stageIn")
        result = appendArgumentsToFunctionCalls(
            in: result,
            functionNames: helperFunctionNames,
            extraArguments: helperExtraArguments
        )
        result = rewriteMulCalls(in: result)
        return result
    }

    private func translateVertexBody(
        _ body: String,
        varyings: [ShaderVarying],
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform],
        textures: [WallpaperEngineShaderTextureBinding],
        helperFunctionNames: Set<String>,
        helperExtraArguments: [String]
    ) -> String {
        var result = translateShaderBodySource(
            body,
            textures: textures,
            parameters: parameters,
            builtinUniforms: builtinUniforms
        )
        result = replaceWord("a_Position", with: "vertexIn.a_Position", in: result)
        result = replaceWord("a_TexCoord", with: "vertexIn.a_TexCoord", in: result)
        result = replaceWord("gl_Position", with: "out.position", in: result)
        result = replaceVaryingReferences(in: result, varyings: varyings, prefix: "out")
        result = appendArgumentsToFunctionCalls(
            in: result,
            functionNames: helperFunctionNames,
            extraArguments: helperExtraArguments
        )
        result = rewriteMulCalls(in: result)
        return indentShaderBody(result)
    }

    private func translateFragmentBody(
        _ body: String,
        textures: [WallpaperEngineShaderTextureBinding],
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform],
        varyings: [ShaderVarying],
        helperFunctionNames: Set<String>,
        helperExtraArguments: [String]
    ) -> String {
        var result = translateShaderBodySource(
            body,
            textures: textures,
            parameters: parameters,
            builtinUniforms: builtinUniforms
        )
        result = replaceVaryingReferences(in: result, varyings: varyings, prefix: "stageIn")
        result = coerceVec4VaryingHelperArguments(in: result, varyings: varyings)
        result = replaceFragmentColorReturn(in: result)
        result = appendArgumentsToFunctionCalls(
            in: result,
            functionNames: helperFunctionNames,
            extraArguments: helperExtraArguments
        )
        result = rewriteMulCalls(in: result)
        let aliases = fragmentArrayAliases(for: varyings, in: result)
        if !aliases.isEmpty {
            result = aliases + "\n" + result
        }
        return indentShaderBody(result)
    }

    private func translateShaderBodySource(
        _ body: String,
        textures: [WallpaperEngineShaderTextureBinding],
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform]
    ) -> String {
        var result = stripComments(body)
        result = replaceTextureSamples(in: result, textures: textures)
        result = replaceGLSLTypes(result)
        result = coerceTextureSampleVectorInitializers(in: result)
        result = replaceWord("texture2D", with: "texSample2D", in: result)
        result = replaceWord("fract", with: "fract", in: result)

        for parameter in parameters {
            result = replaceWord(parameter.uniformName, with: "uniforms.\(parameter.uniformName)", in: result)
        }
        for builtinUniform in builtinUniforms {
            result = replaceWord(
                builtinUniform.uniformName,
                with: "uniforms.\(builtinUniform.uniformName)",
                in: result
            )
        }
        return result
    }

    private func replaceVaryingReferences(
        in source: String,
        varyings: [ShaderVarying],
        prefix: String
    ) -> String {
        var result = source
        for varying in varyings {
            if let arrayCount = varying.arrayCount {
                for index in 0..<arrayCount {
                    result = replaceRegex(
                        #"(?<![A-Za-z0-9_\.])\#(NSRegularExpression.escapedPattern(for: varying.name))\s*\[\s*\#(index)\s*\]"#,
                        with: "\(prefix).\(varying.name)_\(index)",
                        in: result
                    )
                }
            } else {
                result = replaceWord(varying.name, with: "\(prefix).\(varying.name)", in: result)
            }
        }
        return result
    }

    private func replaceFragmentColorReturn(in source: String) -> String {
        var result = replaceRegex(
            #"(?m)^\s*(?:gl_FragColor|out_FragColor)\s*=\s*(.+?);\s*$"#,
            with: "return $1;",
            in: source
        )
        result = replaceWord("gl_FragColor", with: "out_FragColor", in: result)
        if result.contains("out_FragColor."), !result.contains("return ") {
            result = "float4 out_FragColor = float4(0.0);\n" + result + "\nreturn out_FragColor;"
        }
        return result
    }

    private func fragmentArrayAliases(for varyings: [ShaderVarying], in source: String) -> String {
        varyingFields(varyings)
            .reduce(into: [String: [ShaderVaryingField]]()) { result, field in
                guard field.arrayIndex != nil else {
                    return
                }
                result[field.sourceName, default: []].append(field)
            }
            .compactMap { sourceName, fields -> String? in
                guard source.contains("\(sourceName)[") else {
                    return nil
                }
                let sortedFields = fields.sorted { ($0.arrayIndex ?? 0) < ($1.arrayIndex ?? 0) }
                guard let first = sortedFields.first else {
                    return nil
                }
                let values = sortedFields
                    .map { "stageIn.\($0.outputName)" }
                    .joined(separator: ", ")
                return "\(metalType(first.type)) \(sourceName)[\(sortedFields.count)] = { \(values) };"
            }
            .joined(separator: "\n")
    }

    private func coerceVec4VaryingHelperArguments(in source: String, varyings: [ShaderVarying]) -> String {
        var result = source
        for varying in varyings where metalType(varying.type) == "float4" && varying.arrayCount == nil {
            result = result.replacingOccurrences(
                of: "rotateVec2(stageIn.\(varying.name),",
                with: "rotateVec2(stageIn.\(varying.name).xy,"
            )
        }
        return result
    }

    private func coerceTextureSampleVectorInitializers(in source: String) -> String {
        replaceRegex(
            #"\bfloat3\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^;\n]*\.sample\([^;\n]+\))\s*;"#,
            with: "float3 $1 = $2.rgb;",
            in: source
        )
    }

    private func indentShaderBody(_ body: String) -> String {
        body.components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "    \(line)"
            }
            .joined(separator: "\n")
    }

    private func shaderMainBody(in source: String) -> String? {
        guard let mainRange = source.range(of: "void main"),
              let openParen = source[mainRange.upperBound...].firstIndex(of: "("),
              let closeParen = matchingClosingParen(in: source, openParen: openParen),
              let openBrace = firstNonWhitespaceIndex(in: source, from: source.index(after: closeParen)),
              openBrace < source.endIndex,
              source[openBrace] == "{",
              let closeBrace = matchingClosingBrace(in: source, openBrace: openBrace) else {
            return nil
        }
        return String(source[source.index(after: openBrace)..<closeBrace])
    }

    private func matchingClosingBrace(
        in source: String,
        openBrace: String.Index
    ) -> String.Index? {
        var depth = 0
        var current = openBrace
        while current < source.endIndex {
            switch source[current] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return current
                }
            default:
                break
            }
            current = source.index(after: current)
        }
        return nil
    }

    private func rewriteMulCalls(in expression: String) -> String {
        var result = expression
        let candidates = [
            "mul(float4(vertexIn.a_Position, 1.0), uniforms.g_ModelViewProjectionMatrix)",
            "mul(float4(vertexIn.a_Position, 1.0), g_ModelViewProjectionMatrix)",
            "mul(float4(a_Position, 1.0), uniforms.g_ModelViewProjectionMatrix)",
            "mul(float4(a_Position, 1.0), g_ModelViewProjectionMatrix)"
        ]

        for candidate in candidates {
            result = result.replacingOccurrences(
                of: candidate,
                with: "uniforms.g_ModelViewProjectionMatrix * float4(vertexIn.a_Position, 1.0)"
            )
        }

        return result
    }

    private func stripComments(_ expression: String) -> String {
        expression.components(separatedBy: .newlines).map { line in
            line.split(separator: "//", maxSplits: 1).first.map(String.init) ?? ""
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func samplerName(for textureUniformName: String) -> String {
        "\(textureUniformName)Sampler"
    }

    private func replaceTextureSamples(
        in expression: String,
        textures: [WallpaperEngineShaderTextureBinding]
    ) -> String {
        var result = expression
        for texture in textures {
            guard texture.index != nil else {
                continue
            }
            result = replaceTextureSampleFunction(
                "texSample2DLod",
                textureName: texture.uniformName,
                includesLevel: true,
                in: result
            )
            result = replaceTextureSampleFunction(
                "textureLod",
                textureName: texture.uniformName,
                includesLevel: true,
                in: result
            )
            result = replaceTextureSampleFunction(
                "texSample2D",
                textureName: texture.uniformName,
                includesLevel: false,
                in: result
            )
            result = replaceTextureSampleFunction(
                "texture2D",
                textureName: texture.uniformName,
                includesLevel: false,
                in: result
            )
            result = replaceTextureSampleFunction(
                "texture",
                textureName: texture.uniformName,
                includesLevel: false,
                in: result
            )
        }
        return result
    }

    private func replaceTextureSampleFunction(
        _ functionName: String,
        textureName: String,
        includesLevel: Bool,
        in expression: String
    ) -> String {
        var output = ""
        var searchIndex = expression.startIndex

        while let functionRange = expression.range(
            of: functionName,
            range: searchIndex..<expression.endIndex
        ) {
            guard isFunctionNameBoundary(functionRange, in: expression),
                  let openParen = firstNonWhitespaceIndex(
                    in: expression,
                    from: functionRange.upperBound
                  ),
                  openParen < expression.endIndex,
                  expression[openParen] == "(",
                  let closeParen = matchingClosingParen(in: expression, openParen: openParen) else {
                output.append(contentsOf: expression[searchIndex..<functionRange.upperBound])
                searchIndex = functionRange.upperBound
                continue
            }

            let argumentsRange = expression.index(after: openParen)..<closeParen
            let arguments = splitTopLevelArguments(expression[argumentsRange])
            guard arguments.count >= (includesLevel ? 3 : 2),
                  arguments[0] == textureName else {
                output.append(contentsOf: expression[searchIndex..<functionRange.upperBound])
                searchIndex = functionRange.upperBound
                continue
            }

            output.append(contentsOf: expression[searchIndex..<functionRange.lowerBound])
            output.append(textureSampleExpression(
                textureName: textureName,
                coordinate: arguments[1],
                level: includesLevel ? arguments[2] : nil
            ))
            searchIndex = expression.index(after: closeParen)
        }

        output.append(contentsOf: expression[searchIndex..<expression.endIndex])
        return output
    }

    private func textureSampleExpression(
        textureName: String,
        coordinate: String,
        level: String?
    ) -> String {
        let base = "\(textureName).sample(\(samplerName(for: textureName)), \(coordinate)"
        guard let level else {
            return "\(base))"
        }
        return "\(base), level(\(level)))"
    }

    private func isFunctionNameBoundary(
        _ range: Range<String.Index>,
        in source: String
    ) -> Bool {
        if range.lowerBound > source.startIndex {
            let previous = source[source.index(before: range.lowerBound)]
            if previous == "." || isShaderIdentifierCharacter(previous) {
                return false
            }
        }
        if range.upperBound < source.endIndex,
           isShaderIdentifierCharacter(source[range.upperBound]) {
            return false
        }
        return true
    }

    private func firstNonWhitespaceIndex(
        in source: String,
        from index: String.Index
    ) -> String.Index? {
        var current = index
        while current < source.endIndex {
            if !source[current].isWhitespace {
                return current
            }
            current = source.index(after: current)
        }
        return nil
    }

    private func matchingClosingParen(
        in source: String,
        openParen: String.Index
    ) -> String.Index? {
        var depth = 0
        var current = openParen
        while current < source.endIndex {
            switch source[current] {
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    return current
                }
            default:
                break
            }
            current = source.index(after: current)
        }
        return nil
    }

    private func splitTopLevelArguments(_ source: Substring) -> [String] {
        var arguments: [String] = []
        var depth = 0
        var argumentStart = source.startIndex
        var current = source.startIndex

        while current < source.endIndex {
            switch source[current] {
            case "(", "[":
                depth += 1
            case ")", "]":
                depth = max(depth - 1, 0)
            case "," where depth == 0:
                arguments.append(trimArgument(source[argumentStart..<current]))
                argumentStart = source.index(after: current)
            default:
                break
            }
            current = source.index(after: current)
        }

        arguments.append(trimArgument(source[argumentStart..<source.endIndex]))
        return arguments
    }

    private func trimArgument(_ argument: Substring) -> String {
        String(argument).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isShaderIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }

    private func isShaderIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0)
        }
    }

    private func replaceWord(_ token: String, with replacement: String, in source: String) -> String {
        let escapedToken = NSRegularExpression.escapedPattern(for: token)
        let pattern = #"(?<![A-Za-z0-9_\.])\#(escapedToken)(?![A-Za-z0-9_])"#
        return replaceRegex(pattern, with: replacement, in: source)
    }

    private func replaceRegex(_ pattern: String, with replacement: String, in source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return source
        }

        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source),
            withTemplate: replacement
        )
    }

    private func firstTextureSample(in source: String) -> TextureSample? {
        let pattern = #"texSample2D\((g_Texture\d+)\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: source,
                range: NSRange(source.startIndex..<source.endIndex, in: source)
              ),
              match.numberOfRanges == 3,
              let textureRange = Range(match.range(at: 1), in: source),
              let coordinateRange = Range(match.range(at: 2), in: source) else {
            return nil
        }

        return TextureSample(
            texture: String(source[textureRange]),
            coordinate: String(source[coordinateRange])
        )
    }

    private func helperFunctionSource(
        _ helpers: [ShaderHelperFunction],
        textures: [WallpaperEngineShaderTextureBinding],
        parameters: [WallpaperEngineShaderParameterBinding],
        builtinUniforms: [WallpaperEngineMetalBuiltinUniform],
        helperFunctionNames: Set<String>,
        helperExtraArguments: [String]
    ) -> String {
        guard !helpers.isEmpty else {
            return ""
        }

        let contextParameters = helperContextParameters(textures: textures)
        let declarations = helpers.map {
            "\(metalType($0.returnType)) \($0.name)(\(helperParameterList($0.parameters, contextParameters: contextParameters)));"
        }
        let definitions = helpers.map { helper -> String in
            var body = translateShaderBodySource(
                helper.body,
                textures: textures,
                parameters: parameters,
                builtinUniforms: builtinUniforms
            )
            body = appendArgumentsToFunctionCalls(
                in: body,
                functionNames: helperFunctionNames,
                extraArguments: helperExtraArguments
            )
            body = rewriteMulCalls(in: body)
            let signature = "\(metalType(helper.returnType)) \(helper.name)(\(helperParameterList(helper.parameters, contextParameters: contextParameters)))"
            return """
            \(signature) {
            \(indentShaderBody(body))
            }
            """
        }

        return (declarations + definitions).joined(separator: "\n")
    }

    private func shaderHelperFunctions(from preparedShader: WallpaperEnginePreparedShader) -> [ShaderHelperFunction] {
        let sources = [preparedShader.vertexSource, preparedShader.fragmentSource].compactMap { $0 }
        var helpers: [ShaderHelperFunction] = []
        var seenSignatures = Set<String>()
        for source in sources {
            for helper in shaderHelperFunctions(in: source) {
                let signature = "\(helper.returnType):\(helper.name):\(helper.parameters)"
                guard seenSignatures.insert(signature).inserted else {
                    continue
                }
                helpers.append(helper)
            }
        }
        return helpers
    }

    private func shaderHelperFunctions(in source: String) -> [ShaderHelperFunction] {
        let returnTypes = ["float", "vec2", "vec3", "vec4", "mat3", "mat4", "int", "bool"]
        let pattern = #"\b(\#(returnTypes.joined(separator: "|")))\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let matches = regex.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
        var helpers: [ShaderHelperFunction] = []
        var consumedRanges: [Range<String.Index>] = []

        for match in matches {
            guard match.numberOfRanges == 3,
                  let matchRange = Range(match.range(at: 0), in: source),
                  let returnTypeRange = Range(match.range(at: 1), in: source),
                  let nameRange = Range(match.range(at: 2), in: source) else {
                continue
            }
            if consumedRanges.contains(where: { $0.contains(matchRange.lowerBound) }) {
                continue
            }

            let name = String(source[nameRange])
            guard name != "main" else {
                continue
            }
            let openParen = source.index(before: matchRange.upperBound)
            guard let closeParen = matchingClosingParen(in: source, openParen: openParen),
                  let openBrace = firstNonWhitespaceIndex(in: source, from: source.index(after: closeParen)),
                  openBrace < source.endIndex,
                  source[openBrace] == "{",
                  let closeBrace = matchingClosingBrace(in: source, openBrace: openBrace) else {
                continue
            }

            consumedRanges.append(matchRange.lowerBound..<source.index(after: closeBrace))
            helpers.append(ShaderHelperFunction(
                returnType: String(source[returnTypeRange]),
                name: name,
                parameters: String(source[source.index(after: openParen)..<closeParen])
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                body: String(source[source.index(after: openBrace)..<closeBrace])
            ))
        }

        return helpers
    }

    private func helperParameterList(
        _ parameters: String,
        contextParameters: [String]
    ) -> String {
        let ownParameters = replaceGLSLTypes(parameters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ([ownParameters].filter { !$0.isEmpty } + contextParameters)
            .joined(separator: ", ")
    }

    private func helperContextParameters(textures: [WallpaperEngineShaderTextureBinding]) -> [String] {
        ["constant WEUniforms& uniforms"] + textures.flatMap { texture -> [String] in
            guard texture.index != nil else {
                return []
            }
            return [
                "texture2d<float> \(texture.uniformName)",
                "sampler \(samplerName(for: texture.uniformName))"
            ]
        }
    }

    private func helperContextArguments(textures: [WallpaperEngineShaderTextureBinding]) -> [String] {
        ["uniforms"] + textures.flatMap { texture -> [String] in
            guard texture.index != nil else {
                return []
            }
            return [
                texture.uniformName,
                samplerName(for: texture.uniformName)
            ]
        }
    }

    private func appendArgumentsToFunctionCalls(
        in source: String,
        functionNames: Set<String>,
        extraArguments: [String]
    ) -> String {
        guard !functionNames.isEmpty, !extraArguments.isEmpty else {
            return source
        }

        var output = ""
        var searchIndex = source.startIndex
        var current = source.startIndex

        while current < source.endIndex {
            if isShaderIdentifierStart(source[current]) {
                let identifierStart = current
                var identifierEnd = source.index(after: current)
                while identifierEnd < source.endIndex,
                      isShaderIdentifierCharacter(source[identifierEnd]) {
                    identifierEnd = source.index(after: identifierEnd)
                }

                let name = String(source[identifierStart..<identifierEnd])
                guard functionNames.contains(name),
                      isFunctionNameBoundary(identifierStart..<identifierEnd, in: source),
                      let openParen = firstNonWhitespaceIndex(in: source, from: identifierEnd),
                      openParen < source.endIndex,
                      source[openParen] == "(",
                      let closeParen = matchingClosingParen(in: source, openParen: openParen) else {
                    current = identifierEnd
                    continue
                }

                let existingArgumentsRange = source.index(after: openParen)..<closeParen
                let existingArguments = String(source[existingArgumentsRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let topLevelArguments = splitTopLevelArguments(source[existingArgumentsRange])
                if topLevelArguments.contains("uniforms") {
                    current = source.index(after: closeParen)
                    continue
                }

                output.append(contentsOf: source[searchIndex..<source.index(after: openParen)])
                if !existingArguments.isEmpty {
                    output.append(existingArguments)
                    output.append(", ")
                }
                output.append(extraArguments.joined(separator: ", "))
                output.append(")")
                searchIndex = source.index(after: closeParen)
                current = searchIndex
            } else {
                current = source.index(after: current)
            }
        }

        output.append(contentsOf: source[searchIndex..<source.endIndex])
        return output
    }

    private func translationDiagnostics(
        preparedShader: WallpaperEnginePreparedShader,
        fragmentBody: (body: String, diagnostics: [String])
    ) -> [String] {
        var diagnostics: [String] = []
        if preparedShader.vertexSource == nil {
            diagnostics.append("Generated a default vertex function because no vertex shader source was resolved.")
        }
        if preparedShader.fragmentSource == nil {
            diagnostics.append("Generated a default fragment function because no fragment shader source was resolved.")
        }
        diagnostics.append(contentsOf: unsupportedTokens(in: preparedShader))
        return diagnostics
    }

    private func unsupportedTokens(in preparedShader: WallpaperEnginePreparedShader) -> [String] {
        let vertexSource = diagnosticSource(preparedShader.vertexSource)
        let fragmentSource = diagnosticSource(preparedShader.fragmentSource)
        let source = [vertexSource, fragmentSource]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        var diagnostics = [
            "discard",
            "dFdx",
            "dFdy",
            "gl_FragCoord"
        ]
            .filter { sourceContainsWord($0, in: source) }
            .map { "MSL translation does not fully support token '\($0)' yet." }

        let hasUnsupportedVertexPosition = sourceContainsWord("gl_Position", in: vertexSource)
            && assignmentExpression(to: "gl_Position", in: vertexSource) == nil
        if sourceContainsWord("gl_Position", in: fragmentSource) || hasUnsupportedVertexPosition {
            diagnostics.append("MSL translation does not fully support token 'gl_Position' yet.")
        }

        return diagnostics
    }

    private func diagnosticSource(_ source: String?) -> String {
        (source ?? "")
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("#") && !trimmed.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    private func replaceGLSLTypes(_ source: String) -> String {
        source
            .replacingOccurrences(of: "vec2", with: "float2")
            .replacingOccurrences(of: "vec3", with: "float3")
            .replacingOccurrences(of: "vec4", with: "float4")
    }

    private func metalType(_ valueType: String) -> String {
        switch valueType.lowercased() {
        case "vec2", "float2":
            return "float2"
        case "vec3", "float3":
            return "float3"
        case "vec4", "float4":
            return "float4"
        case "mat3", "float3x3":
            return "float3x3"
        case "mat4", "float4x4":
            return "float4x4"
        case "int", "uint", "bool":
            return valueType.lowercased()
        default:
            return "float"
        }
    }

    private func functionSuffix(for usage: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = usage.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        return scalars.joined().trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

private struct ShaderVarying {
    let type: String
    let name: String
    let arrayCount: Int?

    init(type: String, name: String, arrayCount: Int? = nil) {
        self.type = type
        self.name = name
        self.arrayCount = arrayCount
    }
}

private struct ShaderVaryingField {
    let type: String
    let sourceName: String
    let outputName: String
    let arrayIndex: Int?

    init(type: String, sourceName: String, outputName: String, arrayIndex: Int? = nil) {
        self.type = type
        self.sourceName = sourceName
        self.outputName = outputName
        self.arrayIndex = arrayIndex
    }
}

private struct ShaderUniformField {
    let name: String
    let type: String
}

private struct ShaderHelperFunction {
    let returnType: String
    let name: String
    let parameters: String
    let body: String
}

private struct TextureSample {
    let texture: String
    let coordinate: String
}
