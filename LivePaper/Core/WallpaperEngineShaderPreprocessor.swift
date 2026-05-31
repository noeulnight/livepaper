import Foundation

struct WallpaperEnginePreparedShader: Equatable, Sendable {
    let usage: String
    let shaderName: String
    let combos: [String: Int]
    let vertexSource: String?
    let fragmentSource: String?
    let includedPaths: [String]
    let unresolvedIncludes: [String]
}

struct WallpaperEnginePreparedShaderStage: Equatable, Sendable {
    let source: String
    let includedPaths: [String]
    let unresolvedIncludes: [String]
}

struct WallpaperEngineShaderPreprocessor {
    func sourceForMetadataParsing(
        source: String,
        stage: WallpaperEngineShaderStage
    ) -> String {
        var definitions = ShaderPreprocessorDefinitions(initialValues: compatibilityDefines(stage: stage))
        return evaluatePotentialConditionalBranches(
            source: source,
            definitions: &definitions
        )
    }

    func prepare(
        shader: WallpaperEngineResolvedShader,
        usage: String,
        materialCombos: [String: Int],
        textureBindings: [WallpaperEngineRenderTextureBinding],
        includes: [String: WallpaperEngineResolvedShaderInclude]
    ) -> WallpaperEnginePreparedShader {
        let linkedMetadata = [shader.vertexMetadata, shader.fragmentMetadata].compactMap { $0 }
        let vertex = prepareStage(
            source: shader.vertexSource,
            metadata: shader.vertexMetadata,
            stage: .vertex,
            linkedMetadata: linkedMetadata,
            materialCombos: materialCombos,
            textureBindings: textureBindings,
            includes: includes
        )
        let fragment = prepareStage(
            source: shader.fragmentSource,
            metadata: shader.fragmentMetadata,
            stage: .fragment,
            linkedMetadata: linkedMetadata,
            materialCombos: materialCombos,
            textureBindings: textureBindings,
            includes: includes
        )
        let comboMetadata = ([shader.vertexMetadata, shader.fragmentMetadata].compactMap { $0 })
            + includedMetadata(from: vertex, includes: includes)
            + includedMetadata(from: fragment, includes: includes)
        let combos = resolvedCombos(
            metadata: comboMetadata,
            materialCombos: materialCombos,
            textureBindings: textureBindings
        )

        return WallpaperEnginePreparedShader(
            usage: usage,
            shaderName: shader.name,
            combos: combos,
            vertexSource: vertex?.source,
            fragmentSource: fragment?.source,
            includedPaths: Array(Set((vertex?.includedPaths ?? []) + (fragment?.includedPaths ?? []))).sorted(),
            unresolvedIncludes: Array(Set((vertex?.unresolvedIncludes ?? []) + (fragment?.unresolvedIncludes ?? []))).sorted()
        )
    }

    private func prepareStage(
        source: String?,
        metadata: WallpaperEngineShaderMetadata?,
        stage: WallpaperEngineShaderStage,
        linkedMetadata: [WallpaperEngineShaderMetadata],
        materialCombos: [String: Int],
        textureBindings: [WallpaperEngineRenderTextureBinding],
        includes: [String: WallpaperEngineResolvedShaderInclude]
    ) -> WallpaperEnginePreparedShaderStage? {
        guard let source,
              let metadata else {
            return nil
        }

        let metadataList = ([metadata] + linkedMetadata)
            + linkedMetadata.flatMap { transitiveIncludedMetadata(from: $0, includes: includes) }
        let combos = resolvedCombos(
            metadata: metadataList,
            materialCombos: materialCombos,
            textureBindings: textureBindings
        )
        var includedPaths: [String] = []
        var unresolvedIncludes: [String] = []
        var definitions = ShaderPreprocessorDefinitions(
            initialValues: compatibilityDefines(stage: stage).merging(combos) { _, combo in combo }
        )
        let body = preprocessBranchesAndIncludes(
            source: source,
            definitions: &definitions,
            includes: includes,
            visited: [],
            includedPaths: &includedPaths,
            unresolvedIncludes: &unresolvedIncludes
        )
        let preparedSource = [
            compatibilityHeader(stage: stage, path: metadata.path),
            comboDefines(combos),
            normalizeShaderSyntax(body, stage: stage)
        ].filter { !$0.isEmpty }.joined(separator: "\n")

        return WallpaperEnginePreparedShaderStage(
            source: preparedSource,
            includedPaths: Array(Set(includedPaths)).sorted(),
            unresolvedIncludes: Array(Set(unresolvedIncludes)).sorted()
        )
    }

    private func preprocessBranchesAndIncludes(
        source: String,
        definitions: inout ShaderPreprocessorDefinitions,
        includes: [String: WallpaperEngineResolvedShaderInclude],
        visited: Set<String>,
        includedPaths: inout [String],
        unresolvedIncludes: inout [String]
    ) -> String {
        var branches = ShaderActiveConditionalBranchStack()
        var output: [String] = []

        for line in logicalPreprocessorLines(source) {
            guard let directive = preprocessorDirective(in: line) else {
                if branches.isActive {
                    output.append(line)
                }
                continue
            }

            if let branchDirective = shaderBranchDirective(from: directive) {
                branches.apply(
                    branchDirective,
                    definitions: definitions,
                    evaluateExpression: evaluateConditionalExpression
                )
                continue
            }

            switch directive.name {
            case "define":
                if branches.isActive {
                    if let define = parseDefine(directive.argument) {
                        definitions.define(define.definition, named: define.name)
                    }
                    output.append(line)
                }
            case "undef":
                if branches.isActive {
                    definitions.undefine(directive.argument.trimmedShaderDirectiveArgument)
                    output.append(line)
                }
            case "include":
                guard branches.isActive else {
                    continue
                }
                output.append(expandActiveInclude(
                    argument: directive.argument,
                    originalLine: line,
                    definitions: &definitions,
                    includes: includes,
                    visited: visited,
                    includedPaths: &includedPaths,
                    unresolvedIncludes: &unresolvedIncludes
                ))
            case "require":
                if branches.isActive {
                    output.append(expandRequiredModule(directive.argument))
                }
            default:
                if branches.isActive {
                    output.append(line)
                }
            }
        }

        return output.joined(separator: "\n")
    }

    private func expandActiveInclude(
        argument: String,
        originalLine: String,
        definitions: inout ShaderPreprocessorDefinitions,
        includes: [String: WallpaperEngineResolvedShaderInclude],
        visited: Set<String>,
        includedPaths: inout [String],
        unresolvedIncludes: inout [String]
    ) -> String {
        guard let include = definitions.directivePath(from: argument) else {
            return originalLine
        }

        let normalizedInclude = include
        guard !visited.contains(normalizedInclude) else {
            return "// skipped recursive include \(normalizedInclude)"
        }
        guard let resolved = includes[normalizedInclude] else {
            unresolvedIncludes.append(normalizedInclude)
            return "// unresolved include \(normalizedInclude)"
        }

        includedPaths.append(normalizedInclude)
        var nextVisited = visited
        nextVisited.insert(normalizedInclude)
        let expanded = preprocessBranchesAndIncludes(
            source: resolved.source,
            definitions: &definitions,
            includes: includes,
            visited: nextVisited,
            includedPaths: &includedPaths,
            unresolvedIncludes: &unresolvedIncludes
        )

        return [
            "// begin include \(resolved.resolvedPath)",
            expanded,
            "// end include \(resolved.resolvedPath)"
        ].joined(separator: "\n")
    }

    private func expandRequiredModule(_ argument: String) -> String {
        let moduleName = argument.trimmedShaderDirectiveArgument
        switch moduleName {
        case "LightingV1":
            return [
                "// begin generated module LightingV1",
                "vec3 PerformLighting_V1(vec3 worldPos, vec3 albedo, vec3 normal, vec3 viewDir, vec3 specularTint, vec3 baseReflectance, float roughness, float metallic) { return vec3(0.0); }",
                "// end generated module LightingV1"
            ].joined(separator: "\n")
        case "":
            return "// malformed #require directive"
        default:
            return "// unresolved #require \(moduleName)"
        }
    }

    private func includedMetadata(
        from stage: WallpaperEnginePreparedShaderStage?,
        includes: [String: WallpaperEngineResolvedShaderInclude]
    ) -> [WallpaperEngineShaderMetadata] {
        stage?.includedPaths.compactMap { includes[$0]?.metadata } ?? []
    }

    private func transitiveIncludedMetadata(
        from metadata: WallpaperEngineShaderMetadata,
        includes: [String: WallpaperEngineResolvedShaderInclude]
    ) -> [WallpaperEngineShaderMetadata] {
        var result: [WallpaperEngineShaderMetadata] = []
        var queue = metadata.includes
        var visited = Set<String>()

        while !queue.isEmpty {
            let includePath = queue.removeFirst().normalizedWallpaperEnginePath
            guard !visited.contains(includePath) else {
                continue
            }
            visited.insert(includePath)

            guard let include = includes[includePath] else {
                continue
            }
            result.append(include.metadata)
            queue.append(contentsOf: include.metadata.includes)
        }

        return result
    }

    private func resolvedCombos(
        metadata: [WallpaperEngineShaderMetadata],
        materialCombos: [String: Int],
        textureBindings: [WallpaperEngineRenderTextureBinding]
    ) -> [String: Int] {
        let declaredCombos = declaredComboValues(metadata: metadata, materialCombos: materialCombos)
        var combos = textureComboValues(
            metadata: metadata,
            textureBindings: textureBindings,
            comboValues: declaredCombos
        )
        for (name, value) in declaredCombos {
            combos[name] = value
        }
        return combos
    }

    private func declaredComboValues(
        metadata: [WallpaperEngineShaderMetadata],
        materialCombos: [String: Int]
    ) -> [String: Int] {
        var combos: [String: Int] = [:]
        for combo in metadata.flatMap(\.combos) {
            let name = canonicalComboName(combo.name)
            combos[name] = comboValue(named: combo.name, in: materialCombos)
                ?? intValue(combo.defaultValue)
                ?? (combo.disabledByDefault ? 0 : 0)
        }
        for (name, value) in materialCombos {
            combos[canonicalComboName(name)] = value
        }
        return combos
    }

    private func textureComboValues(
        metadata: [WallpaperEngineShaderMetadata],
        textureBindings: [WallpaperEngineRenderTextureBinding],
        comboValues: [String: Int]
    ) -> [String: Int] {
        let boundTextureIndices = Set(textureBindings.map(\.index))
        var combos: [String: Int] = [:]

        for texture in metadata.flatMap(\.textures) {
            guard case .string(let rawComboName)? = texture.metadata["combo"] else {
                continue
            }
            let comboName = canonicalComboName(rawComboName)

            let isBound = texture.index.map { boundTextureIndices.contains($0) } ?? false
            if isBound {
                combos[comboName] = 1
                continue
            }

            if let requirementMatches = textureComboRequirementMatches(
                texture.metadata["require"],
                requireAny: boolValue(texture.metadata["requireany"]) ?? false,
                comboValues: comboValues
            ), !requirementMatches {
                combos[comboName] = 0
                continue
            }

            combos[comboName] = textureDefaultComboValue(texture) ?? 0
        }

        return combos
    }

    private func textureComboRequirementMatches(
        _ requirement: WallpaperEngineSceneValue?,
        requireAny: Bool,
        comboValues: [String: Int]
    ) -> Bool? {
        guard case .object(let requirements)? = requirement else {
            return nil
        }
        guard !requirements.isEmpty else {
            return true
        }

        let matches = requirements.map { name, value in
            comboValue(named: name, in: comboValues) == intValue(value)
        }
        return requireAny ? matches.contains(true) : matches.allSatisfy { $0 }
    }

    private func comboValue(named name: String, in comboValues: [String: Int]) -> Int? {
        comboValues[name]
            ?? comboValues[name.uppercased()]
            ?? comboValues[name.lowercased()]
    }

    private func canonicalComboName(_ name: String) -> String {
        name.uppercased()
    }

    private func textureDefaultComboValue(_ texture: WallpaperEngineShaderTexture) -> Int? {
        intValue(texture.metadata["default"]) ?? (texture.defaultTexture == nil ? nil : 1)
    }

    private func intValue(_ value: WallpaperEngineSceneValue?) -> Int? {
        guard let value else {
            return nil
        }

        switch value {
        case .bool(let bool):
            return bool ? 1 : 0
        case .int(let int):
            return int
        case .double(let double) where double.rounded() == double:
            return Int(double)
        case .string(let string):
            return Int(string)
        default:
            return nil
        }
    }

    private func boolValue(_ value: WallpaperEngineSceneValue?) -> Bool? {
        guard let value else {
            return nil
        }

        switch value {
        case .bool(let bool):
            return bool
        case .int(let int):
            return int != 0
        case .double(let double):
            return double != 0
        case .string(let string):
            return Bool(string) ?? Int(string).map { $0 != 0 }
        default:
            return nil
        }
    }

    private func compatibilityHeader(stage: WallpaperEngineShaderStage, path: String) -> String {
        var lines = [
            "// Prepared Wallpaper Engine shader: \(path)",
            "#define lerp mix",
            "#define frac fract",
            "#define saturate(value) clamp(value, 0.0, 1.0)",
            "#define texSample2D texture",
            "#define texSample2DLod textureLod",
            "#define CAST2(value) vec2(value)",
            "#define CAST3(value) vec3(value)",
            "#define CAST4(value) vec4(value)",
            "#define float2 vec2",
            "#define float3 vec3",
            "#define float4 vec4",
            "#define GLSL 1"
        ]

        if stage == .fragment {
            lines.append("out vec4 out_FragColor;")
        }

        return lines.joined(separator: "\n")
    }

    private func compatibilityDefines(stage: WallpaperEngineShaderStage) -> [String: Int] {
        var defines = ["GLSL": 1]
        if stage == .vertex {
            defines["VERTEXSHADER"] = 1
        } else if stage == .fragment {
            defines["FRAGMENTSHADER"] = 1
        }
        return defines
    }

    private func comboDefines(_ combos: [String: Int]) -> String {
        combos.keys.sorted()
            .map { "#define \($0) \(combos[$0] ?? 0)" }
            .joined(separator: "\n")
    }

    private func evaluatePotentialConditionalBranches(
        source: String,
        definitions: inout ShaderPreprocessorDefinitions
    ) -> String {
        var branches = ShaderPotentialConditionalBranchStack()
        var output: [String] = []

        for line in logicalPreprocessorLines(source) {
            guard let directive = preprocessorDirective(in: line) else {
                if branches.isPossible {
                    output.append(line)
                }
                continue
            }

            if let branchDirective = shaderBranchDirective(from: directive) {
                let effectiveDefinitions = branches.definitionsForCurrentArm(fallback: definitions)
                let exhaustiveOutcomes = branches.apply(
                    branchDirective,
                    definitions: effectiveDefinitions,
                    branchCondition: potentialBranchCondition
                )
                for (name, outcome) in exhaustiveOutcomes {
                    if branches.isCertain {
                        definitions.applyExhaustiveConditionalOutcome(outcome, named: name)
                    }
                    if branches.isPossible {
                        branches.recordOutcome(named: name, outcome: outcome)
                    }
                }
                continue
            }

            switch directive.name {
            case "define":
                if branches.isPossible {
                    if let define = parseDefine(directive.argument) {
                        definitions.define(
                            define.definition,
                            named: define.name,
                            isCertain: branches.isCertain
                        )
                        branches.recordDefine(named: define.name, definition: define.definition)
                    }
                    output.append(line)
                }
            case "undef":
                if branches.isPossible {
                    let name = directive.argument.trimmedShaderDirectiveArgument
                    definitions.undefine(name, isCertain: branches.isCertain)
                    branches.recordUndefine(named: name)
                    output.append(line)
                }
            case "include":
                if branches.isPossible {
                    let effectiveDefinitions = branches.definitionsForCurrentArm(fallback: definitions)
                    let potentialIncludes = effectiveDefinitions.potentialDirectivePaths(from: directive.argument)
                    if !potentialIncludes.isEmpty {
                        for include in potentialIncludes {
                            output.append(#"#include "\#(include)""#)
                        }
                    } else if let include = effectiveDefinitions.directivePath(from: directive.argument) {
                        output.append(#"#include "\#(include)""#)
                    } else {
                        output.append(line)
                    }
                }
            default:
                if branches.isPossible {
                    output.append(line)
                }
            }
        }

        return output.joined(separator: "\n")
    }

    private func shaderBranchDirective(from directive: ShaderPreprocessorDirective) -> ShaderBranchDirective? {
        switch directive.name {
        case "if":
            return .ifExpression(directive.argument)
        case "ifdef":
            return .ifdef(directive.argument.trimmedShaderDirectiveArgument)
        case "ifndef":
            return .ifndef(directive.argument.trimmedShaderDirectiveArgument)
        case "elif":
            return .elifExpression(directive.argument)
        case "elifdef":
            return .elifdef(directive.argument.trimmedShaderDirectiveArgument)
        case "elifndef":
            return .elifndef(directive.argument.trimmedShaderDirectiveArgument)
        case "else":
            return .elseBranch
        case "endif":
            return .endif
        default:
            return nil
        }
    }

    private func conditionalPossibility(
        _ expression: String,
        definitions: ShaderPreprocessorDefinitions
    ) -> ShaderConditionalPossibility {
        var parser = ShaderPotentialConditionalExpressionParser(expression: expression, definitions: definitions)
        switch parser.evaluate().boolNormalized {
        case .known(0):
            return .alwaysFalse
        case .known:
            return .alwaysTrue
        case .oneOf:
            return .maybe
        case .unknown:
            return .maybe
        }
    }

    private func potentialBranchCondition(
        _ expression: String,
        definitions: ShaderPreprocessorDefinitions
    ) -> ShaderPotentialBranchCondition {
        ShaderPotentialBranchCondition(
            possibility: conditionalPossibility(expression, definitions: definitions),
            finiteValueCoverage: finiteValueBranchCoverage(expression, definitions: definitions)
                ?? definednessBranchCoverage(expression, definitions: definitions)
        )
    }

    private func finiteValueBranchCoverage(
        _ expression: String,
        definitions: ShaderPreprocessorDefinitions
    ) -> ShaderFiniteValueBranchCoverage? {
        let expandedExpression = definitions.expandingFunctionCalls(
            in: expression,
            expandObjectMacros: true,
            preserveDefinedOperands: true
        )
        let tokens = ShaderConditionalTokenizer(source: expandedExpression).tokens
        guard !tokens.contains(.identifier("defined")) else {
            return nil
        }

        let candidateNames = Set<String>(tokens.compactMap { token in
            guard case .identifier(let name) = token,
                  !["defined", "true", "false"].contains(name),
                  let values = definitions.finitePotentialValues(for: name),
                  values.count > 1 else {
                return nil
            }
            return name
        })
        guard candidateNames.count == 1,
              let name = candidateNames.first,
              let allValues = definitions.finitePotentialValues(for: name),
              !allValues.isEmpty,
              allValues.count <= 16 else {
            return nil
        }

        var possibleMatchingValues = Set<Int>()
        var guaranteedMatchingValues = Set<Int>()
        for value in allValues {
            let scopedDefinitions = definitions.assigningPotentialValue(value, named: name)
            var parser = ShaderPotentialConditionalExpressionParser(
                expression: expression,
                definitions: scopedDefinitions
            )
            switch parser.evaluate().boolNormalized {
            case .known(0):
                break
            case .known:
                possibleMatchingValues.insert(value)
                guaranteedMatchingValues.insert(value)
            case .oneOf(let values):
                if values.contains(where: { $0 != 0 }) {
                    possibleMatchingValues.insert(value)
                }
                if !values.contains(0) {
                    guaranteedMatchingValues.insert(value)
                }
            case .unknown:
                possibleMatchingValues.insert(value)
            }
        }

        return ShaderFiniteValueBranchCoverage(
            name: name,
            constrainsDefinedness: false,
            allValues: allValues,
            possibleMatchingValues: possibleMatchingValues,
            guaranteedMatchingValues: guaranteedMatchingValues
        )
    }

    private func definednessBranchCoverage(
        _ expression: String,
        definitions: ShaderPreprocessorDefinitions
    ) -> ShaderFiniteValueBranchCoverage? {
        let expandedExpression = definitions.expandingFunctionCalls(
            in: expression,
            expandObjectMacros: true,
            preserveDefinedOperands: true
        )
        let tokens = ShaderConditionalTokenizer(source: expandedExpression).tokens
        let extractedOperands = definedOperands(in: tokens)
        guard extractedOperands.names.count == 1,
              let name = extractedOperands.names.first,
              definitions.potentialDefinedPossibility(for: name) == .maybe else {
            return nil
        }

        let allValues: Set<Int> = [0, 1]
        var possibleMatchingValues = Set<Int>()
        var guaranteedMatchingValues = Set<Int>()
        for value in allValues {
            let scopedDefinitions = definitions.assigningPotentialDefinedState(value != 0, named: name)
            var parser = ShaderPotentialConditionalExpressionParser(
                expression: expression,
                definitions: scopedDefinitions
            )
            switch parser.evaluate().boolNormalized {
            case .known(0):
                break
            case .known:
                possibleMatchingValues.insert(value)
                guaranteedMatchingValues.insert(value)
            case .oneOf(let values):
                if values.contains(where: { $0 != 0 }) {
                    possibleMatchingValues.insert(value)
                }
                if !values.contains(0) {
                    guaranteedMatchingValues.insert(value)
                }
            case .unknown:
                possibleMatchingValues.insert(value)
            }
        }

        return ShaderFiniteValueBranchCoverage(
            name: name,
            constrainsDefinedness: true,
            allValues: allValues,
            possibleMatchingValues: possibleMatchingValues,
            guaranteedMatchingValues: guaranteedMatchingValues
        )
    }

    private func definedOperands(
        in tokens: [ShaderConditionalToken]
    ) -> (names: Set<String>, operandTokenOffsets: Set<Int>) {
        var names = Set<String>()
        var operandTokenOffsets = Set<Int>()
        var index = 0

        while index < tokens.count {
            guard tokens[index] == .identifier("defined") else {
                index += 1
                continue
            }

            let nextIndex = index + 1
            if nextIndex < tokens.count,
               tokens[nextIndex] == .operator("("),
               nextIndex + 1 < tokens.count,
               case .identifier(let name) = tokens[nextIndex + 1] {
                names.insert(name)
                operandTokenOffsets.insert(nextIndex + 1)
                index = nextIndex + 2
                continue
            }

            if nextIndex < tokens.count,
               case .identifier(let name) = tokens[nextIndex] {
                names.insert(name)
                operandTokenOffsets.insert(nextIndex)
                index = nextIndex + 1
                continue
            }

            index += 1
        }

        return (names, operandTokenOffsets)
    }

    private func preprocessorDirective(in line: String) -> ShaderPreprocessorDirective? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else {
            return nil
        }

        var directiveStart = trimmed.index(after: trimmed.startIndex)
        while directiveStart < trimmed.endIndex,
              trimmed[directiveStart].isWhitespace {
            directiveStart = trimmed.index(after: directiveStart)
        }

        var nameEnd = directiveStart
        while nameEnd < trimmed.endIndex,
              trimmed[nameEnd].isLetter {
            nameEnd = trimmed.index(after: nameEnd)
        }
        guard directiveStart < nameEnd else {
            return nil
        }

        let name = String(trimmed[directiveStart..<nameEnd])
        let argument = String(trimmed[nameEnd...])
            .strippingShaderDirectiveComments()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ShaderPreprocessorDirective(name: name, argument: argument)
    }

    private func logicalPreprocessorLines(_ source: String) -> [String] {
        var lines: [String] = []
        var pending = ""
        var isInBlockComment = false

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.removingShaderBlockComments(isInBlockComment: &isInBlockComment)
            let trimmedRight = line.trimmingCharacters(in: .whitespaces)
            let continues = trimmedRight.hasSuffix("\\")
            let content = continues ? String(trimmedRight.dropLast()) : line

            if pending.isEmpty {
                pending = content
            } else {
                pending += " " + content.trimmingCharacters(in: .whitespaces)
            }

            if !continues {
                lines.append(pending)
                pending = ""
            }
        }

        if !pending.isEmpty {
            lines.append(pending)
        }

        return lines
    }

    private func parseDefine(_ argument: String) -> (name: String, definition: ShaderMacroDefinition)? {
        let trimmed = argument.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }

        var nameEnd = trimmed.startIndex
        while nameEnd < trimmed.endIndex {
            let character = trimmed[nameEnd]
            if character.isWhitespace || character == "(" {
                break
            }
            nameEnd = trimmed.index(after: nameEnd)
        }
        guard trimmed.startIndex < nameEnd else {
            return nil
        }

        let name = String(trimmed[trimmed.startIndex..<nameEnd])
        let valueStart: String.Index
        if nameEnd < trimmed.endIndex, trimmed[nameEnd] == "(" {
            guard let closeParen = matchingClosingParen(in: trimmed, openParen: nameEnd) else {
                return (name, .function(parameters: [], body: ""))
            }
            let parameters = trimmed[trimmed.index(after: nameEnd)..<closeParen]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let body = String(trimmed[trimmed.index(after: closeParen)...])
                .trimmingCharacters(in: .whitespaces)
            return (name, .function(parameters: parameters, body: body))
        } else {
            valueStart = nameEnd
        }

        let rawValue = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespaces)
        return (name, .object(rawValue.isEmpty ? "1" : rawValue))
    }

    private func evaluateConditionalExpression(_ expression: String, definitions: ShaderPreprocessorDefinitions) -> Bool {
        var parser = ShaderConditionalExpressionParser(expression: expression, definitions: definitions)
        return parser.evaluate() != 0
    }

    private func matchingClosingParen(in source: String, openParen: String.Index) -> String.Index? {
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

    private func normalizeShaderSyntax(_ source: String, stage: WallpaperEngineShaderStage) -> String {
        var normalized = source.replacingOccurrences(of: "gl_FragColor", with: "out_FragColor")

        if stage == .vertex {
            normalized = normalized.replacingOccurrences(of: "attribute ", with: "in ")
            normalized = normalized.replacingOccurrences(of: "varying ", with: "out ")
        } else if stage == .fragment {
            normalized = normalized.replacingOccurrences(of: "varying ", with: "in ")
        }

        return normalized
    }
}

private struct ShaderPreprocessorDirective {
    let name: String
    let argument: String
}

func parseWallpaperEngineShaderDirectivePath(_ argument: String) -> String? {
    let rest = argument
        .strippingShaderDirectiveComments()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rest.isEmpty else {
        return nil
    }

    if rest.hasPrefix("\""),
       let end = rest.dropFirst().firstIndex(of: "\"") {
        return String(rest[rest.index(after: rest.startIndex)..<end]).normalizedWallpaperEnginePath
    }

    if rest.hasPrefix("<"),
       let end = rest.dropFirst().firstIndex(of: ">") {
        return String(rest[rest.index(after: rest.startIndex)..<end]).normalizedWallpaperEnginePath
    }

    let token = rest.split(whereSeparator: \.isWhitespace).first.map(String.init)
    return token?
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"<>"))
        .normalizedWallpaperEnginePath
}

private enum ShaderMacroDefinition: Equatable {
    case object(String)
    case function(parameters: [String], body: String)
}

private struct ShaderPossibleMacroDefinition {
    private(set) var definitions: [ShaderMacroDefinition]

    init(definition: ShaderMacroDefinition) {
        self.definitions = [definition]
    }

    mutating func merge(_ nextDefinition: ShaderMacroDefinition) {
        if !definitions.contains(nextDefinition) {
            definitions.append(nextDefinition)
        }
    }
}

private struct ShaderPotentialMacroOutcome {
    private(set) var definitions: [ShaderMacroDefinition] = []
    private(set) var canBeUndefined = false

    mutating func define(_ definition: ShaderMacroDefinition) {
        definitions = [definition]
        canBeUndefined = false
    }

    mutating func undefine() {
        definitions = []
        canBeUndefined = true
    }

    mutating func merge(_ outcome: ShaderPotentialMacroOutcome) {
        for definition in outcome.definitions where !definitions.contains(definition) {
            definitions.append(definition)
        }
        canBeUndefined = canBeUndefined || outcome.canBeUndefined
    }
}

private struct ShaderPreprocessorDefinitions {
    private var macros: [String: ShaderMacroDefinition]
    private var explicitlyUndefinedMacros = Set<String>()
    private var possiblyDefinedMacros: [String: ShaderPossibleMacroDefinition] = [:]
    private var possiblyUndefinedMacros = Set<String>()
    private var conditionallyAlwaysDefinedMacros = Set<String>()

    init(initialValues: [String: Int]) {
        self.macros = initialValues.mapValues { .object(String($0)) }
    }

    func isDefined(_ name: String) -> Bool {
        macros[name] != nil
    }

    func isExplicitlyUndefined(_ name: String) -> Bool {
        explicitlyUndefinedMacros.contains(name)
    }

    func potentialDefinedPossibility(for name: String) -> ShaderConditionalPossibility {
        if isDefined(name) {
            return possiblyUndefinedMacros.contains(name) ? .maybe : .alwaysTrue
        }
        if conditionallyAlwaysDefinedMacros.contains(name) {
            return possiblyUndefinedMacros.contains(name) ? .maybe : .alwaysTrue
        }
        if isExplicitlyUndefined(name) {
            return possiblyDefinedMacros[name] == nil ? .alwaysFalse : .maybe
        }
        return .maybe
    }

    func potentialNotDefinedPossibility(for name: String) -> ShaderConditionalPossibility {
        if isDefined(name) {
            return possiblyUndefinedMacros.contains(name) ? .maybe : .alwaysFalse
        }
        if conditionallyAlwaysDefinedMacros.contains(name) {
            return possiblyUndefinedMacros.contains(name) ? .maybe : .alwaysFalse
        }
        if isExplicitlyUndefined(name) {
            return possiblyDefinedMacros[name] == nil ? .alwaysTrue : .maybe
        }
        return .maybe
    }

    func definednessBranchCoverage(
        named name: String,
        matchesDefinedState: Bool
    ) -> ShaderFiniteValueBranchCoverage? {
        guard potentialDefinedPossibility(for: name) == .maybe else {
            return nil
        }
        return ShaderFiniteValueBranchCoverage(
            name: name,
            constrainsDefinedness: true,
            allValues: [0, 1],
            possibleMatchingValues: [matchesDefinedState ? 1 : 0],
            guaranteedMatchingValues: [matchesDefinedState ? 1 : 0]
        )
    }

    func objectExpression(for name: String) -> String? {
        guard case .object(let expression)? = macros[name] else {
            return nil
        }
        return expression
    }

    func directivePath(from argument: String, expanding: Set<String> = []) -> String? {
        let stripped = argument
            .strippingShaderDirectiveComments()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else {
            return nil
        }

        let token = stripped.trimmedShaderDirectiveArgument
        if !expanding.contains(token),
           let expression = objectExpression(for: token),
           let expandedPath = directivePath(from: expression, expanding: expanding.union([token])) {
            return expandedPath
        }

        let functionExpanded = expandingFunctionCalls(
            in: stripped,
            expanding: expanding,
            wrapFunctionExpansions: false
        )
        if functionExpanded != stripped,
           let expandedPath = directivePath(from: functionExpanded, expanding: expanding) {
            return expandedPath
        }

        return parseWallpaperEngineShaderDirectivePath(stripped)
    }

    func potentialDirectivePaths(from argument: String) -> [String] {
        potentialDirectivePaths(
            from: argument,
            expanding: [],
            visitedExpressions: []
        )
    }

    private func potentialDirectivePaths(
        from argument: String,
        expanding: Set<String>,
        visitedExpressions: Set<String>
    ) -> [String] {
        let stripped = argument
            .strippingShaderDirectiveComments()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else {
            return []
        }
        guard !visitedExpressions.contains(stripped) else {
            return []
        }

        let nextVisitedExpressions = visitedExpressions.union([stripped])
        let token = stripped.trimmedShaderDirectiveArgument
        var paths: [String] = []
        if let tokenName = shaderSingleIdentifier(token),
           !expanding.contains(tokenName) {
            for expression in potentialObjectExpressions(for: tokenName) {
                paths.append(contentsOf: potentialDirectivePaths(
                    from: expression,
                    expanding: expanding.union([tokenName]),
                    visitedExpressions: nextVisitedExpressions
                ))
            }
        }

        for expandedExpression in potentialFunctionExpandedExpressions(in: stripped, expanding: expanding)
            where expandedExpression != stripped {
            paths.append(contentsOf: potentialDirectivePaths(
                from: expandedExpression,
                expanding: expanding,
                visitedExpressions: nextVisitedExpressions
            ))
        }

        if paths.isEmpty,
           let directPath = directivePath(from: stripped, expanding: expanding) {
            paths.append(directPath)
        }

        return Array(Set(paths)).sorted()
    }

    mutating func define(_ definition: ShaderMacroDefinition, named name: String) {
        macros[name] = definition
        explicitlyUndefinedMacros.remove(name)
        possiblyDefinedMacros.removeValue(forKey: name)
        possiblyUndefinedMacros.remove(name)
        conditionallyAlwaysDefinedMacros.remove(name)
    }

    mutating func define(_ definition: ShaderMacroDefinition, named name: String, isCertain: Bool) {
        if isCertain {
            define(definition, named: name)
            return
        }

        if var possible = possiblyDefinedMacros[name] {
            possible.merge(definition)
            possiblyDefinedMacros[name] = possible
        } else {
            possiblyDefinedMacros[name] = ShaderPossibleMacroDefinition(definition: definition)
        }
    }

    mutating func applyExhaustiveConditionalOutcome(
        _ outcome: ShaderPotentialMacroOutcome,
        named name: String
    ) {
        macros.removeValue(forKey: name)
        explicitlyUndefinedMacros.remove(name)
        possiblyDefinedMacros.removeValue(forKey: name)
        possiblyUndefinedMacros.remove(name)
        conditionallyAlwaysDefinedMacros.remove(name)

        guard !outcome.definitions.isEmpty else {
            if outcome.canBeUndefined {
                explicitlyUndefinedMacros.insert(name)
            }
            return
        }

        if outcome.definitions.count == 1,
           !outcome.canBeUndefined,
           let definition = outcome.definitions.first {
            define(definition, named: name)
            return
        }

        var possible = ShaderPossibleMacroDefinition(definition: outcome.definitions[0])
        for definition in outcome.definitions.dropFirst() {
            possible.merge(definition)
        }
        possiblyDefinedMacros[name] = possible
        if outcome.canBeUndefined {
            possiblyUndefinedMacros.insert(name)
        } else {
            conditionallyAlwaysDefinedMacros.insert(name)
        }
    }

    func applyingPotentialOutcomes(
        _ outcomes: [String: ShaderPotentialMacroOutcome]
    ) -> ShaderPreprocessorDefinitions {
        var definitions = self
        for (name, outcome) in outcomes {
            definitions.applyExhaustiveConditionalOutcome(outcome, named: name)
        }
        return definitions
    }

    func applyingBranchArmConstraints(
        _ constraints: [ShaderBranchArmConstraint]
    ) -> ShaderPreprocessorDefinitions {
        var definitions = self
        for constraint in constraints {
            definitions.applyBranchArmConstraint(constraint)
        }
        return definitions
    }

    private mutating func applyBranchArmConstraint(_ constraint: ShaderBranchArmConstraint) {
        guard !constraint.values.isEmpty else {
            return
        }

        if constraint.constrainsDefinedness {
            if constraint.values == [1] {
                constrainDefined(constraint.name)
            } else if constraint.values == [0] {
                undefine(constraint.name)
            }
            return
        }

        let canForceValueConstraint = !constraint.values.contains(0)
            || potentialDefinedPossibility(for: constraint.name) == .alwaysTrue
        guard canForceValueConstraint else {
            return
        }

        var merged = ShaderPotentialMacroOutcome()
        for value in constraint.values.sorted() {
            var outcome = ShaderPotentialMacroOutcome()
            outcome.define(.object(String(value)))
            merged.merge(outcome)
        }
        applyExhaustiveConditionalOutcome(merged, named: constraint.name)
    }

    private mutating func constrainDefined(_ name: String) {
        explicitlyUndefinedMacros.remove(name)
        possiblyUndefinedMacros.remove(name)
        conditionallyAlwaysDefinedMacros.insert(name)
    }

    func constrainingUndefinedForUnresolvedNames<S: Sequence<String>>(
        _ names: S
    ) -> ShaderPreprocessorDefinitions {
        var definitions = self
        for name in names
            where definitions.macros[name] == nil
                && definitions.possiblyDefinedMacros[name] == nil
                && !definitions.conditionallyAlwaysDefinedMacros.contains(name) {
            definitions.explicitlyUndefinedMacros.insert(name)
        }
        return definitions
    }

    mutating func undefine(_ name: String) {
        macros.removeValue(forKey: name)
        explicitlyUndefinedMacros.insert(name)
        possiblyDefinedMacros.removeValue(forKey: name)
        possiblyUndefinedMacros.remove(name)
        conditionallyAlwaysDefinedMacros.remove(name)
    }

    mutating func undefine(_ name: String, isCertain: Bool) {
        if isCertain {
            undefine(name)
            return
        }

        if macros[name] != nil {
            possiblyUndefinedMacros.insert(name)
        }
    }

    func value(for name: String, expanding: Set<String> = []) -> Int {
        guard let definition = macros[name],
              !expanding.contains(name) else {
            return 0
        }

        switch definition {
        case .function:
            return 0
        case .object(let expression):
            var parser = ShaderConditionalExpressionParser(
                expression: expression,
                definitions: self,
                expanding: expanding.union([name])
            )
            return parser.evaluate()
        }
    }

    func potentialValue(for name: String, expanding: Set<String> = []) -> ShaderPotentialValue {
        let candidateValues = potentialValues(for: name, expanding: expanding)
        guard !candidateValues.isEmpty else {
            return .unknown
        }
        return ShaderPotentialValue.union(candidateValues)
    }

    func finitePotentialValues(for name: String) -> Set<Int>? {
        potentialValue(for: name).finiteValues
    }

    func assigningPotentialValue(_ value: Int, named name: String) -> ShaderPreprocessorDefinitions {
        var definitions = self
        definitions.define(.object(String(value)), named: name)
        return definitions
    }

    func assigningPotentialDefinedState(
        _ isDefined: Bool,
        named name: String
    ) -> ShaderPreprocessorDefinitions {
        var definitions = self
        if isDefined {
            definitions.define(.object("1"), named: name)
        } else {
            definitions.undefine(name)
        }
        return definitions
    }

    private func potentialValues(for name: String, expanding: Set<String>) -> [ShaderPotentialValue] {
        var values: [ShaderPotentialValue] = []
        if let definition = macros[name] {
            values.append(potentialValue(for: definition, name: name, expanding: expanding))
        } else if !conditionallyAlwaysDefinedMacros.contains(name),
                  possiblyDefinedMacros[name] != nil || explicitlyUndefinedMacros.contains(name) {
            values.append(.known(0))
        }

        if possiblyUndefinedMacros.contains(name) {
            values.append(.known(0))
        }

        for definition in possiblyDefinedMacros[name]?.definitions ?? [] {
            values.append(potentialValue(for: definition, name: name, expanding: expanding))
        }

        return values
    }

    private func potentialValue(
        for definition: ShaderMacroDefinition,
        name: String,
        expanding: Set<String>
    ) -> ShaderPotentialValue {
        guard !expanding.contains(name) else {
            return .known(0)
        }

        switch definition {
        case .function:
            return .known(0)
        case .object(let expression):
            var parser = ShaderPotentialConditionalExpressionParser(
                expression: expression,
                definitions: self,
                expanding: expanding.union([name])
            )
            return parser.evaluate()
        }
    }

    private func potentialObjectExpressions(for name: String) -> [String] {
        var expressions: [String] = []
        if case .object(let expression)? = macros[name] {
            expressions.append(expression)
        }
        for definition in possiblyDefinedMacros[name]?.definitions ?? [] {
            if case .object(let expression) = definition,
               !expressions.contains(expression) {
                expressions.append(expression)
            }
        }
        return expressions
    }

    func hasPossibleFunctionMacro(named name: String, expanding: Set<String> = []) -> Bool {
        !possibleFunctionMacros(named: name, expanding: expanding).isEmpty
    }

    private func potentialFunctionExpandedExpressions(
        in expression: String,
        expanding: Set<String> = []
    ) -> [String] {
        var expansions: [String] = []
        var index = expression.startIndex

        while index < expression.endIndex {
            let character = expression[index]
            guard character.isShaderIdentifierStart else {
                index = expression.index(after: index)
                continue
            }

            let nameStart = index
            repeat {
                index = expression.index(after: index)
            } while index < expression.endIndex && expression[index].isShaderIdentifierContinue

            let name = String(expression[nameStart..<index])
            var callStart = index
            while callStart < expression.endIndex && expression[callStart].isWhitespace {
                callStart = expression.index(after: callStart)
            }

            guard !expanding.contains(name),
                  callStart < expression.endIndex,
                  expression[callStart] == "(",
                  let callEnd = expression.matchingShaderClosingParen(openParen: callStart) else {
                continue
            }

            let functionMacros = possibleFunctionMacros(named: name)
            guard !functionMacros.isEmpty else {
                continue
            }

            let arguments = splitShaderMacroArguments(
                expression[expression.index(after: callStart)..<callEnd]
            )
            let prefix = String(expression[..<nameStart])
            let suffix = String(expression[expression.index(after: callEnd)...])

            for functionMacro in functionMacros {
                let substitution = substituteShaderMacroParameters(
                    parameters: functionMacro.parameters,
                    arguments: arguments,
                    in: functionMacro.body,
                    definitions: self,
                    expanding: expanding.union([name]),
                    preserveDefinedOperands: false
                )
                let expandedSubstitution = expandingFunctionCalls(
                    in: resolveShaderMacroTokenPastes(in: substitution),
                    expanding: expanding.union([name]),
                    wrapFunctionExpansions: false,
                    expandObjectMacros: true
                )
                let candidate = prefix + expandedSubstitution + suffix
                expansions.append(candidate)
                expansions.append(contentsOf: potentialFunctionExpandedExpressions(
                    in: candidate,
                    expanding: expanding.union([name])
                ))
            }
        }

        return Array(Set(expansions)).sorted()
    }

    private func possibleFunctionMacros(
        named name: String,
        expanding: Set<String> = []
    ) -> [(parameters: [String], body: String)] {
        guard !expanding.contains(name) else {
            return []
        }

        var functions: [(parameters: [String], body: String)] = []
        let nextExpanding = expanding.union([name])

        for definition in possiblyDefinedMacros[name]?.definitions ?? [] {
            switch definition {
            case .function(let parameters, let body):
                functions.append((parameters, body))
            case .object(let expression):
                guard let alias = shaderSingleIdentifier(expression) else {
                    continue
                }
                if case .function(let parameters, let body)? = macros[alias] {
                    functions.append((parameters, body))
                }
                functions.append(contentsOf: possibleFunctionMacros(
                    named: alias,
                    expanding: nextExpanding
                ))
            }
        }

        return functions
    }

    func expandingFunctionCalls(
        in expression: String,
        expanding: Set<String> = [],
        wrapFunctionExpansions: Bool = true,
        expandObjectMacros: Bool = false,
        preserveDefinedOperands: Bool = false
    ) -> String {
        var output = ""
        var index = expression.startIndex

        while index < expression.endIndex {
            let character = expression[index]
            guard character.isShaderIdentifierStart else {
                output.append(character)
                index = expression.index(after: index)
                continue
            }

            let nameStart = index
            repeat {
                index = expression.index(after: index)
            } while index < expression.endIndex && expression[index].isShaderIdentifierContinue

            let name = String(expression[nameStart..<index])
            let afterName = index
            var callStart = afterName
            while callStart < expression.endIndex && expression[callStart].isWhitespace {
                callStart = expression.index(after: callStart)
            }

            if preserveDefinedOperands,
               name == "defined" {
                if callStart < expression.endIndex,
                   expression[callStart] == "(",
                   let callEnd = expression.matchingShaderClosingParen(openParen: callStart) {
                    output += expression[nameStart...callEnd]
                    index = expression.index(after: callEnd)
                    continue
                }

                var operandEnd = callStart
                if operandEnd < expression.endIndex,
                   expression[operandEnd].isShaderIdentifierStart {
                    repeat {
                        operandEnd = expression.index(after: operandEnd)
                    } while operandEnd < expression.endIndex && expression[operandEnd].isShaderIdentifierContinue

                    output += expression[nameStart..<operandEnd]
                    index = operandEnd
                    continue
                }

                output += name
                continue
            }

            if let functionMacro = functionMacroInvocation(named: name, expanding: expanding),
               callStart < expression.endIndex,
               expression[callStart] == "(",
               let callEnd = expression.matchingShaderClosingParen(openParen: callStart) {
                let arguments = splitShaderMacroArguments(
                    expression[expression.index(after: callStart)..<callEnd]
                )
                let substitution = substituteShaderMacroParameters(
                    parameters: functionMacro.parameters,
                    arguments: arguments,
                    in: functionMacro.body,
                    definitions: self,
                    expanding: functionMacro.expanding,
                    preserveDefinedOperands: preserveDefinedOperands
                )
                let pastedSubstitution = resolveShaderMacroTokenPastes(in: substitution)
                let expandedSubstitution = expandingFunctionCalls(
                    in: pastedSubstitution,
                    expanding: functionMacro.expanding,
                    wrapFunctionExpansions: wrapFunctionExpansions,
                    expandObjectMacros: expandObjectMacros,
                    preserveDefinedOperands: preserveDefinedOperands
                )
                let chainedCall = expandChainedFunctionCall(
                    callableSource: expandedSubstitution,
                    in: expression,
                    after: expression.index(after: callEnd),
                    expanding: functionMacro.expanding,
                    wrapFunctionExpansions: wrapFunctionExpansions,
                    expandObjectMacros: expandObjectMacros,
                    preserveDefinedOperands: preserveDefinedOperands
                )
                if wrapFunctionExpansions {
                    output += "("
                }
                output += chainedCall?.source ?? expandedSubstitution
                if wrapFunctionExpansions {
                    output += ")"
                }
                index = chainedCall?.end ?? expression.index(after: callEnd)
            } else if expandObjectMacros,
                      case .object(let expression)? = macros[name],
                      !expanding.contains(name) {
                output += expandingFunctionCalls(
                    in: expression,
                    expanding: expanding.union([name]),
                    wrapFunctionExpansions: wrapFunctionExpansions,
                    expandObjectMacros: true,
                    preserveDefinedOperands: preserveDefinedOperands
                )
            } else {
                output += name
            }
        }

        return output
    }

    private func expandChainedFunctionCall(
        callableSource: String,
        in expression: String,
        after index: String.Index,
        expanding: Set<String>,
        wrapFunctionExpansions: Bool,
        expandObjectMacros: Bool,
        preserveDefinedOperands: Bool
    ) -> (source: String, end: String.Index)? {
        guard let callableName = shaderSingleCallableIdentifier(callableSource),
              let functionMacro = functionMacroInvocation(named: callableName, expanding: expanding) else {
            return nil
        }

        var callStart = index
        while callStart < expression.endIndex && expression[callStart].isWhitespace {
            callStart = expression.index(after: callStart)
        }

        guard callStart < expression.endIndex,
              expression[callStart] == "(",
              let callEnd = expression.matchingShaderClosingParen(openParen: callStart) else {
            return nil
        }

        let arguments = splitShaderMacroArguments(
            expression[expression.index(after: callStart)..<callEnd]
        )
        let substitution = substituteShaderMacroParameters(
            parameters: functionMacro.parameters,
            arguments: arguments,
            in: functionMacro.body,
            definitions: self,
            expanding: functionMacro.expanding,
            preserveDefinedOperands: preserveDefinedOperands
        )
        let pastedSubstitution = resolveShaderMacroTokenPastes(in: substitution)
        return (
            source: expandingFunctionCalls(
                in: pastedSubstitution,
                expanding: functionMacro.expanding,
                wrapFunctionExpansions: wrapFunctionExpansions,
                expandObjectMacros: expandObjectMacros,
                preserveDefinedOperands: preserveDefinedOperands
            ),
            end: expression.index(after: callEnd)
        )
    }

    private func functionMacroInvocation(
        named name: String,
        expanding: Set<String>
    ) -> (name: String, parameters: [String], body: String, expanding: Set<String>)? {
        guard let functionName = functionMacroInvocationName(named: name, expanding: expanding),
              case .function(let parameters, let body)? = macros[functionName] else {
            return nil
        }

        return (
            name: functionName,
            parameters: parameters,
            body: body,
            expanding: expanding.union([name, functionName])
        )
    }

    private func functionMacroInvocationName(
        named name: String,
        expanding: Set<String>
    ) -> String? {
        if case .function? = macros[name],
           !expanding.contains(name) {
            return name
        }

        guard !expanding.contains(name),
              case .object(let expression)? = macros[name],
              let aliasName = shaderSingleIdentifier(expression) else {
            return nil
        }

        if case .function? = macros[aliasName],
           !expanding.contains(aliasName) {
            return aliasName
        }

        return functionMacroInvocationName(
            named: aliasName,
            expanding: expanding.union([name])
        )
    }
}

private enum ShaderBranchDirective {
    case ifExpression(String)
    case ifdef(String)
    case ifndef(String)
    case elifExpression(String)
    case elifdef(String)
    case elifndef(String)
    case elseBranch
    case endif
}

private struct ShaderActiveConditionalBranchStack {
    private var frames: [ShaderConditionalFrame] = []

    var isActive: Bool {
        frames.last?.isActive ?? true
    }

    mutating func apply(
        _ directive: ShaderBranchDirective,
        definitions: ShaderPreprocessorDefinitions,
        evaluateExpression: (String, ShaderPreprocessorDefinitions) -> Bool
    ) {
        switch directive {
        case .ifExpression(let expression):
            push(condition: evaluateExpression(expression, definitions))
        case .ifdef(let name):
            push(condition: definitions.isDefined(name))
        case .ifndef(let name):
            push(condition: !definitions.isDefined(name))
        case .elifExpression(let expression):
            updateElif(condition: evaluateExpression(expression, definitions))
        case .elifdef(let name):
            updateElif(condition: definitions.isDefined(name))
        case .elifndef(let name):
            updateElif(condition: !definitions.isDefined(name))
        case .elseBranch:
            updateElse()
        case .endif:
            pop()
        }
    }

    private mutating func push(condition: Bool) {
        let parentActive = isActive
        let isActive = parentActive && condition
        frames.append(ShaderConditionalFrame(
            parentActive: parentActive,
            isActive: isActive,
            branchMatched: isActive,
            hasElse: false
        ))
    }

    private mutating func updateElif(condition: Bool) {
        guard !frames.isEmpty else {
            return
        }

        var frame = frames.removeLast()
        if frame.hasElse {
            frame.isActive = false
        } else {
            let isActive = frame.parentActive && !frame.branchMatched && condition
            frame.isActive = isActive
            frame.branchMatched = frame.branchMatched || isActive
        }
        frames.append(frame)
    }

    private mutating func updateElse() {
        guard !frames.isEmpty else {
            return
        }

        var frame = frames.removeLast()
        frame.isActive = frame.parentActive && !frame.branchMatched && !frame.hasElse
        frame.branchMatched = true
        frame.hasElse = true
        frames.append(frame)
    }

    private mutating func pop() {
        if !frames.isEmpty {
            frames.removeLast()
        }
    }
}

private struct ShaderPotentialConditionalBranchStack {
    private var frames: [ShaderPotentialConditionalFrame] = []

    var isPossible: Bool {
        frames.last?.isPossible ?? true
    }

    var isCertain: Bool {
        frames.last?.isCertain ?? true
    }

    func definitionsForCurrentArm(
        fallback definitions: ShaderPreprocessorDefinitions
    ) -> ShaderPreprocessorDefinitions {
        guard let frame = frames.last,
              frame.currentArmPossible else {
            return definitions
        }
        return frame.branchStartDefinitions
            .constrainingUndefinedForUnresolvedNames(frame.completedSiblingOutcomeNames)
            .applyingBranchArmConstraints(frame.currentArmConstraints)
            .applyingPotentialOutcomes(frame.currentArmOutcomes)
    }

    private func definitionsForNextSiblingArm(
        fallback definitions: ShaderPreprocessorDefinitions
    ) -> ShaderPreprocessorDefinitions {
        guard let frame = frames.last else {
            return definitions
        }
        return frame.branchStartDefinitions
            .constrainingUndefinedForUnresolvedNames(frame.allSiblingOutcomeNamesIncludingCurrent)
    }

    mutating func apply(
        _ directive: ShaderBranchDirective,
        definitions: ShaderPreprocessorDefinitions,
        branchCondition: (String, ShaderPreprocessorDefinitions) -> ShaderPotentialBranchCondition
    ) -> [String: ShaderPotentialMacroOutcome] {
        switch directive {
        case .ifExpression(let expression):
            push(
                condition: branchCondition(expression, definitions),
                branchStartDefinitions: definitions
            )
            return [:]
        case .ifdef(let name):
            push(
                condition: ShaderPotentialBranchCondition(
                    possibility: definitions.potentialDefinedPossibility(for: name),
                    finiteValueCoverage: definitions.definednessBranchCoverage(
                        named: name,
                        matchesDefinedState: true
                    )
                ),
                branchStartDefinitions: definitions
            )
            return [:]
        case .ifndef(let name):
            push(
                condition: ShaderPotentialBranchCondition(
                    possibility: definitions.potentialNotDefinedPossibility(for: name),
                    finiteValueCoverage: definitions.definednessBranchCoverage(
                        named: name,
                        matchesDefinedState: false
                    )
                ),
                branchStartDefinitions: definitions
            )
            return [:]
        case .elifExpression(let expression):
            let branchDefinitions = definitionsForNextSiblingArm(fallback: definitions)
            updateElif(condition: branchCondition(expression, branchDefinitions))
            return [:]
        case .elifdef(let name):
            let branchDefinitions = definitionsForNextSiblingArm(fallback: definitions)
            updateElif(condition: ShaderPotentialBranchCondition(
                possibility: branchDefinitions.potentialDefinedPossibility(for: name),
                finiteValueCoverage: branchDefinitions.definednessBranchCoverage(
                    named: name,
                    matchesDefinedState: true
                )
            ))
            return [:]
        case .elifndef(let name):
            let branchDefinitions = definitionsForNextSiblingArm(fallback: definitions)
            updateElif(condition: ShaderPotentialBranchCondition(
                possibility: branchDefinitions.potentialNotDefinedPossibility(for: name),
                finiteValueCoverage: branchDefinitions.definednessBranchCoverage(
                    named: name,
                    matchesDefinedState: false
                )
            ))
            return [:]
        case .elseBranch:
            updateElse()
            return [:]
        case .endif:
            return pop()
        }
    }

    mutating func recordDefine(named name: String, definition: ShaderMacroDefinition) {
        guard !frames.isEmpty,
              frames[frames.index(before: frames.endIndex)].currentArmPossible else {
            return
        }
        var outcome = ShaderPotentialMacroOutcome()
        outcome.define(definition)
        frames[frames.index(before: frames.endIndex)].currentArmOutcomes[name] = outcome
    }

    mutating func recordUndefine(named name: String) {
        guard !frames.isEmpty,
              frames[frames.index(before: frames.endIndex)].currentArmPossible else {
            return
        }
        var outcome = ShaderPotentialMacroOutcome()
        outcome.undefine()
        frames[frames.index(before: frames.endIndex)].currentArmOutcomes[name] = outcome
    }

    mutating func recordOutcome(named name: String, outcome: ShaderPotentialMacroOutcome) {
        guard !frames.isEmpty,
              frames[frames.index(before: frames.endIndex)].currentArmPossible else {
            return
        }
        frames[frames.index(before: frames.endIndex)].currentArmOutcomes[name] = outcome
    }

    private mutating func push(
        condition: ShaderPotentialBranchCondition,
        branchStartDefinitions: ShaderPreprocessorDefinitions
    ) {
        let parentPossible = isPossible
        let parentCertain = isCertain
        let evaluatedCondition = condition.evaluated(
            with: [:],
            parentAlreadyExhausted: false
        )
        let isPossible = parentPossible && evaluatedCondition.canBeTrue
        frames.append(ShaderPotentialConditionalFrame(
            branchStartDefinitions: branchStartDefinitions,
            parentPossible: parentPossible,
            parentCertain: parentCertain,
            isPossible: isPossible,
            isCertain: parentCertain && evaluatedCondition.isAlwaysTrueIfReached,
            branchExhausted: parentPossible && evaluatedCondition.exhaustsRemainingValues,
            priorBranchCanBeTrue: isPossible,
            currentArmPossible: isPossible,
            currentArmConstraints: isPossible ? evaluatedCondition.currentArmConstraints : [],
            currentArmOutcomes: [:],
            completedPossibleArmOutcomes: [],
            finiteValueCoverageStates: evaluatedCondition.coverageStates,
            hasElse: false
        ))
    }

    private mutating func updateElif(condition: ShaderPotentialBranchCondition) {
        guard !frames.isEmpty else {
            return
        }

        var frame = frames.removeLast()
        frame.finishCurrentArm()
        if frame.hasElse || frame.branchExhausted {
            frame.isPossible = false
            frame.isCertain = false
            frame.currentArmPossible = false
        } else {
            let evaluatedCondition = condition.evaluated(
                with: frame.finiteValueCoverageStates,
                parentAlreadyExhausted: frame.branchExhausted
            )
            frame.isPossible = frame.parentPossible && evaluatedCondition.canBeTrue
            frame.isCertain = frame.parentCertain
                && !frame.priorBranchCanBeTrue
                && evaluatedCondition.isAlwaysTrueIfReached
            frame.priorBranchCanBeTrue = frame.priorBranchCanBeTrue || frame.isPossible
            frame.branchExhausted = frame.parentPossible && evaluatedCondition.exhaustsRemainingValues
            frame.currentArmPossible = frame.isPossible
            frame.currentArmConstraints = frame.isPossible ? evaluatedCondition.currentArmConstraints : []
            frame.finiteValueCoverageStates = evaluatedCondition.coverageStates
        }
        if !frame.currentArmPossible {
            frame.currentArmConstraints = []
        }
        frame.currentArmOutcomes = [:]
        frames.append(frame)
    }

    private mutating func updateElse() {
        guard !frames.isEmpty else {
            return
        }

        var frame = frames.removeLast()
        frame.finishCurrentArm()
        let elseArmConstraints = frame.remainingBranchArmConstraints
        frame.isPossible = frame.parentPossible && !frame.branchExhausted && !frame.hasElse
        frame.isCertain = frame.parentCertain && !frame.priorBranchCanBeTrue && !frame.hasElse
        frame.branchExhausted = true
        frame.priorBranchCanBeTrue = true
        frame.currentArmPossible = frame.isPossible
        frame.currentArmConstraints = frame.isPossible ? elseArmConstraints : []
        frame.currentArmOutcomes = [:]
        frame.hasElse = true
        frames.append(frame)
    }

    private mutating func pop() -> [String: ShaderPotentialMacroOutcome] {
        guard !frames.isEmpty else {
            return [:]
        }
        var frame = frames.removeLast()
        frame.finishCurrentArm()
        guard frame.parentPossible,
              frame.exhaustsParent,
              !frame.completedPossibleArmOutcomes.isEmpty else {
            return [:]
        }

        let firstArm = frame.completedPossibleArmOutcomes[0]
        let commonNames = firstArm.keys.filter { name in
            frame.completedPossibleArmOutcomes.allSatisfy { $0[name] != nil }
        }

        var outcomes: [String: ShaderPotentialMacroOutcome] = [:]
        for name in commonNames {
            var merged = ShaderPotentialMacroOutcome()
            for arm in frame.completedPossibleArmOutcomes {
                if let outcome = arm[name] {
                    merged.merge(outcome)
                }
            }
            outcomes[name] = merged
        }
        return outcomes
    }
}

private struct ShaderConditionalFrame {
    let parentActive: Bool
    var isActive: Bool
    var branchMatched: Bool
    var hasElse: Bool
}

private struct ShaderPotentialConditionalFrame {
    let branchStartDefinitions: ShaderPreprocessorDefinitions
    let parentPossible: Bool
    let parentCertain: Bool
    var isPossible: Bool
    var isCertain: Bool
    var branchExhausted: Bool
    var priorBranchCanBeTrue: Bool
    var currentArmPossible: Bool
    var currentArmConstraints: [ShaderBranchArmConstraint]
    var currentArmOutcomes: [String: ShaderPotentialMacroOutcome]
    var completedPossibleArmOutcomes: [[String: ShaderPotentialMacroOutcome]]
    var finiteValueCoverageStates: [String: ShaderFiniteValueBranchCoverageState]
    var hasElse: Bool

    var exhaustsParent: Bool {
        branchExhausted || hasElse
    }

    var completedSiblingOutcomeNames: Set<String> {
        Set(completedPossibleArmOutcomes.flatMap(\.keys))
    }

    var allSiblingOutcomeNamesIncludingCurrent: Set<String> {
        completedSiblingOutcomeNames.union(currentArmOutcomes.keys)
    }

    var remainingBranchArmConstraints: [ShaderBranchArmConstraint] {
        finiteValueCoverageStates.values.compactMap { state in
            let remainingValues = state.remainingValues
            guard !remainingValues.isEmpty else {
                return nil
            }
            return ShaderBranchArmConstraint(
                name: state.name,
                constrainsDefinedness: state.constrainsDefinedness,
                values: remainingValues
            )
        }
        .sorted {
            if $0.name == $1.name {
                return !$0.constrainsDefinedness && $1.constrainsDefinedness
            }
            return $0.name < $1.name
        }
    }

    mutating func finishCurrentArm() {
        guard currentArmPossible else {
            currentArmConstraints = []
            currentArmOutcomes = [:]
            return
        }
        completedPossibleArmOutcomes.append(currentArmOutcomes)
        currentArmConstraints = []
        currentArmOutcomes = [:]
    }
}

private struct ShaderPotentialBranchCondition {
    let possibility: ShaderConditionalPossibility
    let finiteValueCoverage: ShaderFiniteValueBranchCoverage?

    init(
        possibility: ShaderConditionalPossibility,
        finiteValueCoverage: ShaderFiniteValueBranchCoverage? = nil
    ) {
        self.possibility = possibility
        self.finiteValueCoverage = finiteValueCoverage
    }

    func evaluated(
        with coverageStates: [String: ShaderFiniteValueBranchCoverageState],
        parentAlreadyExhausted: Bool
    ) -> ShaderEvaluatedPotentialBranchCondition {
        var nextCoverageStates = coverageStates
        var canBeTrue = possibility.canBeTrue
        var isAlwaysTrueIfReached = possibility == .alwaysTrue
        var exhaustsRemainingValues = possibility == .alwaysTrue
        var currentArmConstraints: [ShaderBranchArmConstraint] = []

        if let finiteValueCoverage {
            let priorCoverage = coverageStates[finiteValueCoverage.stateKey]
            let previouslyCovered = priorCoverage?.coveredValues ?? []
            let remainingValues = finiteValueCoverage.allValues.subtracting(previouslyCovered)
            let newlyPossibleValues = finiteValueCoverage.possibleMatchingValues.intersection(remainingValues)
            let newlyGuaranteedValues = finiteValueCoverage.guaranteedMatchingValues.intersection(remainingValues)

            if newlyPossibleValues.isEmpty {
                canBeTrue = false
            }
            if !remainingValues.isEmpty,
               finiteValueCoverage.guaranteedMatchingValues.isSuperset(of: remainingValues) {
                isAlwaysTrueIfReached = true
                exhaustsRemainingValues = true
            }

            if !newlyGuaranteedValues.isEmpty {
                let existingState = priorCoverage ?? ShaderFiniteValueBranchCoverageState(
                    name: finiteValueCoverage.name,
                    constrainsDefinedness: finiteValueCoverage.constrainsDefinedness,
                    allValues: finiteValueCoverage.allValues,
                    coveredValues: []
                )
                nextCoverageStates[finiteValueCoverage.stateKey] = existingState
                    .covering(newlyGuaranteedValues)
            }

            if !newlyPossibleValues.isEmpty {
                currentArmConstraints.append(ShaderBranchArmConstraint(
                    name: finiteValueCoverage.name,
                    constrainsDefinedness: finiteValueCoverage.constrainsDefinedness,
                    values: newlyPossibleValues
                ))
            }
        }

        if parentAlreadyExhausted {
            canBeTrue = false
            isAlwaysTrueIfReached = false
            exhaustsRemainingValues = true
        }
        if !canBeTrue {
            currentArmConstraints = []
        }

        return ShaderEvaluatedPotentialBranchCondition(
            canBeTrue: canBeTrue,
            isAlwaysTrueIfReached: isAlwaysTrueIfReached,
            exhaustsRemainingValues: exhaustsRemainingValues,
            coverageStates: nextCoverageStates,
            currentArmConstraints: currentArmConstraints
        )
    }
}

private struct ShaderEvaluatedPotentialBranchCondition {
    let canBeTrue: Bool
    let isAlwaysTrueIfReached: Bool
    let exhaustsRemainingValues: Bool
    let coverageStates: [String: ShaderFiniteValueBranchCoverageState]
    let currentArmConstraints: [ShaderBranchArmConstraint]
}

private struct ShaderBranchArmConstraint {
    let name: String
    let constrainsDefinedness: Bool
    let values: Set<Int>
}

private struct ShaderFiniteValueBranchCoverage {
    let name: String
    let constrainsDefinedness: Bool
    let allValues: Set<Int>
    let possibleMatchingValues: Set<Int>
    let guaranteedMatchingValues: Set<Int>

    var stateKey: String {
        "\(constrainsDefinedness ? "defined" : "value"):\(name)"
    }
}

private struct ShaderFiniteValueBranchCoverageState {
    let name: String
    let constrainsDefinedness: Bool
    let allValues: Set<Int>
    var coveredValues: Set<Int>

    var remainingValues: Set<Int> {
        allValues.subtracting(coveredValues)
    }

    func covering(_ values: Set<Int>) -> ShaderFiniteValueBranchCoverageState {
        var state = self
        state.coveredValues.formUnion(values)
        state.coveredValues.formIntersection(allValues)
        return state
    }
}

private enum ShaderConditionalPossibility {
    case alwaysFalse
    case maybe
    case alwaysTrue

    var canBeTrue: Bool {
        self != .alwaysFalse
    }
}

private enum ShaderPotentialValue: Equatable {
    case known(Int)
    case oneOf(Set<Int>)
    case unknown

    var boolNormalized: ShaderPotentialValue {
        switch self {
        case .known(let value):
            return .known(value == 0 ? 0 : 1)
        case .oneOf(let values):
            return Self.union(values.map { .known($0 == 0 ? 0 : 1) })
        case .unknown:
            return .unknown
        }
    }

    var finiteValues: Set<Int>? {
        switch self {
        case .known(let value):
            return [value]
        case .oneOf(let values):
            return values
        case .unknown:
            return nil
        }
    }

    static func knownBool(_ value: Bool) -> ShaderPotentialValue {
        .known(value ? 1 : 0)
    }

    static func union<S: Sequence>(_ values: S) -> ShaderPotentialValue where S.Element == ShaderPotentialValue {
        var unioned = Set<Int>()
        for value in values {
            guard let finiteValues = value.finiteValues else {
                return .unknown
            }
            unioned.formUnion(finiteValues)
            if unioned.count > 16 {
                return .unknown
            }
        }
        if let only = unioned.first, unioned.count == 1 {
            return .known(only)
        }
        return unioned.isEmpty ? .known(0) : .oneOf(unioned)
    }
}

private struct ShaderPotentialConditionalExpressionParser {
    private let tokens: [ShaderConditionalToken]
    private let definitions: ShaderPreprocessorDefinitions
    private let expanding: Set<String>
    private var index = 0

    init(
        expression: String,
        definitions: ShaderPreprocessorDefinitions,
        expanding: Set<String> = []
    ) {
        self.definitions = definitions
        self.expanding = expanding
        self.tokens = ShaderConditionalTokenizer(
            source: definitions.expandingFunctionCalls(
                in: expression,
                expanding: expanding,
                expandObjectMacros: true,
                preserveDefinedOperands: true
            )
        ).tokens
    }

    mutating func evaluate() -> ShaderPotentialValue {
        parseConditional()
    }

    private mutating func parseConditional() -> ShaderPotentialValue {
        let condition = parseOr()
        guard consumeOperator("?") else {
            return condition
        }

        let trueValue = parseConditional()
        _ = consumeOperator(":")
        let falseValue = parseConditional()

        switch condition.boolNormalized {
        case .known(0):
            return falseValue
        case .known:
            return trueValue
        case .oneOf(let values):
            let canUseTrueValue = values.contains { $0 != 0 }
            let canUseFalseValue = values.contains(0)

            switch (canUseTrueValue, canUseFalseValue) {
            case (true, true):
                return ShaderPotentialValue.union([trueValue, falseValue])
            case (true, false):
                return trueValue
            case (false, true):
                return falseValue
            case (false, false):
                return .unknown
            }
        case .unknown:
            return trueValue == falseValue ? trueValue : .unknown
        }
    }

    private mutating func parseOr() -> ShaderPotentialValue {
        var value = parseAnd()
        while consumeOperator("||") {
            value = logicalOr(value, parseAnd())
        }
        return value
    }

    private mutating func parseAnd() -> ShaderPotentialValue {
        var value = parseBitwiseOr()
        while consumeOperator("&&") {
            value = logicalAnd(value, parseBitwiseOr())
        }
        return value
    }

    private mutating func parseBitwiseOr() -> ShaderPotentialValue {
        var value = parseBitwiseXor()
        while consumeOperator("|") {
            value = binary(value, parseBitwiseXor()) { $0 | $1 }
        }
        return value
    }

    private mutating func parseBitwiseXor() -> ShaderPotentialValue {
        var value = parseBitwiseAnd()
        while consumeOperator("^") {
            value = binary(value, parseBitwiseAnd()) { $0 ^ $1 }
        }
        return value
    }

    private mutating func parseBitwiseAnd() -> ShaderPotentialValue {
        var value = parseEquality()
        while consumeOperator("&") {
            value = bitwiseAnd(value, parseEquality())
        }
        return value
    }

    private mutating func parseEquality() -> ShaderPotentialValue {
        var value = parseComparison()
        while true {
            if consumeOperator("==") {
                value = comparison(value, parseComparison()) { $0 == $1 }
            } else if consumeOperator("!=") {
                value = comparison(value, parseComparison()) { $0 != $1 }
            } else {
                return value
            }
        }
    }

    private mutating func parseComparison() -> ShaderPotentialValue {
        var value = parseShift()
        while true {
            if consumeOperator(">=") {
                value = comparison(value, parseShift()) { $0 >= $1 }
            } else if consumeOperator("<=") {
                value = comparison(value, parseShift()) { $0 <= $1 }
            } else if consumeOperator(">") {
                value = comparison(value, parseShift()) { $0 > $1 }
            } else if consumeOperator("<") {
                value = comparison(value, parseShift()) { $0 < $1 }
            } else {
                return value
            }
        }
    }

    private mutating func parseShift() -> ShaderPotentialValue {
        var value = parseAdditive()
        while true {
            if consumeOperator("<<") {
                value = binary(value, parseAdditive()) { $0 << max($1, 0) }
            } else if consumeOperator(">>") {
                value = binary(value, parseAdditive()) { $0 >> max($1, 0) }
            } else {
                return value
            }
        }
    }

    private mutating func parseAdditive() -> ShaderPotentialValue {
        var value = parseMultiplicative()
        while true {
            if consumeOperator("+") {
                value = binary(value, parseMultiplicative()) { $0 + $1 }
            } else if consumeOperator("-") {
                value = binary(value, parseMultiplicative()) { $0 - $1 }
            } else {
                return value
            }
        }
    }

    private mutating func parseMultiplicative() -> ShaderPotentialValue {
        var value = parseUnary()
        while true {
            if consumeOperator("*") {
                value = multiply(value, parseUnary())
            } else if consumeOperator("/") {
                value = binary(value, parseUnary()) { $1 == 0 ? 0 : $0 / $1 }
            } else if consumeOperator("%") {
                value = binary(value, parseUnary()) { $1 == 0 ? 0 : $0 % $1 }
            } else {
                return value
            }
        }
    }

    private mutating func parseUnary() -> ShaderPotentialValue {
        if consumeOperator("!") {
            switch parseUnary().boolNormalized {
            case .known(0):
                return .known(1)
            case .known:
                return .known(0)
            case .oneOf(let values):
                return ShaderPotentialValue.union(values.map { .known($0 == 0 ? 1 : 0) })
            case .unknown:
                return .unknown
            }
        }
        if consumeOperator("+") {
            return parseUnary()
        }
        if consumeOperator("-") {
            return unary(parseUnary()) { -$0 }
        }
        if consumeOperator("~") {
            return unary(parseUnary()) { ~$0 }
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> ShaderPotentialValue {
        if consumeOperator("(") {
            let value = parseConditional()
            _ = consumeOperator(")")
            return value
        }

        guard let token = peek() else {
            return .known(0)
        }

        switch token {
        case .number(let value):
            index += 1
            return .known(value)
        case .identifier("defined"):
            index += 1
            return parseDefined()
        case .identifier("true"):
            index += 1
            return .known(1)
        case .identifier("false"):
            index += 1
            return .known(0)
        case .identifier(let name):
            index += 1
            if definitions.hasPossibleFunctionMacro(named: name),
               consumeFunctionCallArguments() {
                return .unknown
            }
            return macroValue(for: name)
        case .operator:
            return .known(0)
        }
    }

    private mutating func parseDefined() -> ShaderPotentialValue {
        if consumeOperator("(") {
            let name = consumeIdentifier()
            _ = consumeOperator(")")
            return potentialDefinedValue(for: name)
        }

        return potentialDefinedValue(for: consumeIdentifier())
    }

    private func potentialDefinedValue(for name: String?) -> ShaderPotentialValue {
        guard let name else {
            return .known(0)
        }
        switch definitions.potentialDefinedPossibility(for: name) {
        case .alwaysFalse:
            return .known(0)
        case .alwaysTrue:
            return .known(1)
        case .maybe:
            return .oneOf([0, 1])
        }
    }

    private func macroValue(for name: String) -> ShaderPotentialValue {
        definitions.potentialValue(for: name, expanding: expanding)
    }

    private func logicalOr(
        _ lhs: ShaderPotentialValue,
        _ rhs: ShaderPotentialValue
    ) -> ShaderPotentialValue {
        let lhs = lhs.boolNormalized
        let rhs = rhs.boolNormalized
        if let lhsValues = lhs.finiteValues,
           let rhsValues = rhs.finiteValues {
            return ShaderPotentialValue.union(lhsValues.flatMap { lhsValue in
                rhsValues.map { rhsValue in
                    ShaderPotentialValue.known(lhsValue != 0 || rhsValue != 0 ? 1 : 0)
                }
            })
        }

        switch (lhs, rhs) {
        case (.known(let lhsValue), _) where lhsValue != 0:
            return .known(1)
        case (.known(0), let rhsValue):
            return rhsValue
        case (_, .known(let rhsValue)) where rhsValue != 0:
            return .known(1)
        default:
            return .unknown
        }
    }

    private func logicalAnd(
        _ lhs: ShaderPotentialValue,
        _ rhs: ShaderPotentialValue
    ) -> ShaderPotentialValue {
        let lhs = lhs.boolNormalized
        let rhs = rhs.boolNormalized
        if let lhsValues = lhs.finiteValues,
           let rhsValues = rhs.finiteValues {
            return ShaderPotentialValue.union(lhsValues.flatMap { lhsValue in
                rhsValues.map { rhsValue in
                    ShaderPotentialValue.known(lhsValue != 0 && rhsValue != 0 ? 1 : 0)
                }
            })
        }

        switch (lhs, rhs) {
        case (.known(0), _), (_, .known(0)):
            return .known(0)
        case (.known, let rhsValue):
            return rhsValue
        case (let lhsValue, .known):
            return lhsValue
        default:
            return .unknown
        }
    }

    private func bitwiseAnd(
        _ lhs: ShaderPotentialValue,
        _ rhs: ShaderPotentialValue
    ) -> ShaderPotentialValue {
        if let lhsValues = lhs.finiteValues,
           let rhsValues = rhs.finiteValues {
            return ShaderPotentialValue.union(lhsValues.flatMap { lhsValue in
                rhsValues.map { rhsValue in
                    ShaderPotentialValue.known(lhsValue & rhsValue)
                }
            })
        }

        switch (lhs, rhs) {
        case (.known(0), _), (_, .known(0)):
            return .known(0)
        case (.known(let lhsValue), .known(let rhsValue)):
            return .known(lhsValue & rhsValue)
        default:
            return .unknown
        }
    }

    private func multiply(
        _ lhs: ShaderPotentialValue,
        _ rhs: ShaderPotentialValue
    ) -> ShaderPotentialValue {
        if let lhsValues = lhs.finiteValues,
           let rhsValues = rhs.finiteValues {
            return ShaderPotentialValue.union(lhsValues.flatMap { lhsValue in
                rhsValues.map { rhsValue in
                    ShaderPotentialValue.known(lhsValue * rhsValue)
                }
            })
        }

        switch (lhs, rhs) {
        case (.known(0), _), (_, .known(0)):
            return .known(0)
        case (.known(let lhsValue), .known(let rhsValue)):
            return .known(lhsValue * rhsValue)
        default:
            return .unknown
        }
    }

    private func unary(
        _ value: ShaderPotentialValue,
        _ operation: (Int) -> Int
    ) -> ShaderPotentialValue {
        guard let values = value.finiteValues else {
            return .unknown
        }
        return ShaderPotentialValue.union(values.map { .known(operation($0)) })
    }

    private func binary(
        _ lhs: ShaderPotentialValue,
        _ rhs: ShaderPotentialValue,
        _ operation: (Int, Int) -> Int
    ) -> ShaderPotentialValue {
        guard let lhsValues = lhs.finiteValues,
              let rhsValues = rhs.finiteValues else {
            return .unknown
        }
        return ShaderPotentialValue.union(lhsValues.flatMap { lhsValue in
            rhsValues.map { rhsValue in
                ShaderPotentialValue.known(operation(lhsValue, rhsValue))
            }
        })
    }

    private func comparison(
        _ lhs: ShaderPotentialValue,
        _ rhs: ShaderPotentialValue,
        _ operation: (Int, Int) -> Bool
    ) -> ShaderPotentialValue {
        guard let lhsValues = lhs.finiteValues,
              let rhsValues = rhs.finiteValues else {
            return .unknown
        }
        return ShaderPotentialValue.union(lhsValues.flatMap { lhsValue in
            rhsValues.map { rhsValue in
                ShaderPotentialValue.knownBool(operation(lhsValue, rhsValue))
            }
        })
    }

    private func peek() -> ShaderConditionalToken? {
        guard index < tokens.count else {
            return nil
        }
        return tokens[index]
    }

    private mutating func consumeOperator(_ value: String) -> Bool {
        guard case .operator(let operatorValue)? = peek(),
              operatorValue == value else {
            return false
        }
        index += 1
        return true
    }

    private mutating func consumeIdentifier() -> String? {
        guard case .identifier(let value)? = peek() else {
            return nil
        }
        index += 1
        return value
    }

    private mutating func consumeFunctionCallArguments() -> Bool {
        guard consumeOperator("(") else {
            return false
        }

        var depth = 1
        while let token = peek() {
            index += 1
            switch token {
            case .operator("("):
                depth += 1
            case .operator(")"):
                depth -= 1
                if depth == 0 {
                    return true
                }
            default:
                break
            }
        }

        return true
    }
}

private struct ShaderConditionalExpressionParser {
    private let tokens: [ShaderConditionalToken]
    private let definitions: ShaderPreprocessorDefinitions
    private let expanding: Set<String>
    private var index = 0

    init(
        expression: String,
        definitions: ShaderPreprocessorDefinitions,
        expanding: Set<String> = []
    ) {
        self.definitions = definitions
        self.expanding = expanding
        self.tokens = ShaderConditionalTokenizer(
            source: definitions.expandingFunctionCalls(
                in: expression,
                expanding: expanding,
                expandObjectMacros: true,
                preserveDefinedOperands: true
            )
        ).tokens
    }

    mutating func evaluate() -> Int {
        parseConditional()
    }

    private mutating func parseConditional() -> Int {
        let condition = parseOr()
        guard consumeOperator("?") else {
            return condition
        }

        let trueValue = parseConditional()
        _ = consumeOperator(":")
        let falseValue = parseConditional()
        return condition != 0 ? trueValue : falseValue
    }

    private mutating func parseOr() -> Int {
        var value = parseAnd()
        while consumeOperator("||") {
            let rhs = parseAnd()
            value = (value != 0 || rhs != 0) ? 1 : 0
        }
        return value
    }

    private mutating func parseAnd() -> Int {
        var value = parseBitwiseOr()
        while consumeOperator("&&") {
            let rhs = parseBitwiseOr()
            value = (value != 0 && rhs != 0) ? 1 : 0
        }
        return value
    }

    private mutating func parseBitwiseOr() -> Int {
        var value = parseBitwiseXor()
        while consumeOperator("|") {
            value = value | parseBitwiseXor()
        }
        return value
    }

    private mutating func parseBitwiseXor() -> Int {
        var value = parseBitwiseAnd()
        while consumeOperator("^") {
            value = value ^ parseBitwiseAnd()
        }
        return value
    }

    private mutating func parseBitwiseAnd() -> Int {
        var value = parseEquality()
        while consumeOperator("&") {
            value = value & parseEquality()
        }
        return value
    }

    private mutating func parseEquality() -> Int {
        var value = parseComparison()
        while true {
            if consumeOperator("==") {
                value = value == parseComparison() ? 1 : 0
            } else if consumeOperator("!=") {
                value = value != parseComparison() ? 1 : 0
            } else {
                return value
            }
        }
    }

    private mutating func parseComparison() -> Int {
        var value = parseShift()
        while true {
            if consumeOperator(">=") {
                value = value >= parseShift() ? 1 : 0
            } else if consumeOperator("<=") {
                value = value <= parseShift() ? 1 : 0
            } else if consumeOperator(">") {
                value = value > parseShift() ? 1 : 0
            } else if consumeOperator("<") {
                value = value < parseShift() ? 1 : 0
            } else {
                return value
            }
        }
    }

    private mutating func parseShift() -> Int {
        var value = parseAdditive()
        while true {
            if consumeOperator("<<") {
                value = value << max(parseAdditive(), 0)
            } else if consumeOperator(">>") {
                value = value >> max(parseAdditive(), 0)
            } else {
                return value
            }
        }
    }

    private mutating func parseAdditive() -> Int {
        var value = parseMultiplicative()
        while true {
            if consumeOperator("+") {
                value += parseMultiplicative()
            } else if consumeOperator("-") {
                value -= parseMultiplicative()
            } else {
                return value
            }
        }
    }

    private mutating func parseMultiplicative() -> Int {
        var value = parseUnary()
        while true {
            if consumeOperator("*") {
                value *= parseUnary()
            } else if consumeOperator("/") {
                let divisor = parseUnary()
                value = divisor == 0 ? 0 : value / divisor
            } else if consumeOperator("%") {
                let divisor = parseUnary()
                value = divisor == 0 ? 0 : value % divisor
            } else {
                return value
            }
        }
    }

    private mutating func parseUnary() -> Int {
        if consumeOperator("!") {
            return parseUnary() == 0 ? 1 : 0
        }
        if consumeOperator("+") {
            return parseUnary()
        }
        if consumeOperator("-") {
            return -parseUnary()
        }
        if consumeOperator("~") {
            return ~parseUnary()
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Int {
        if consumeOperator("(") {
            let value = parseConditional()
            _ = consumeOperator(")")
            return value
        }

        guard let token = peek() else {
            return 0
        }

        switch token {
        case .number(let value):
            index += 1
            return value
        case .identifier("defined"):
            index += 1
            return parseDefined()
        case .identifier("true"):
            index += 1
            return 1
        case .identifier("false"):
            index += 1
            return 0
        case .identifier(let name):
            index += 1
            return definitions.value(for: name, expanding: expanding)
        case .operator:
            return 0
        }
    }

    private mutating func parseDefined() -> Int {
        if consumeOperator("(") {
            let name = consumeIdentifier()
            _ = consumeOperator(")")
            return name.map { definitions.isDefined($0) } == true ? 1 : 0
        }

        return consumeIdentifier().map { definitions.isDefined($0) } == true ? 1 : 0
    }

    private func peek() -> ShaderConditionalToken? {
        guard index < tokens.count else {
            return nil
        }
        return tokens[index]
    }

    private mutating func consumeOperator(_ value: String) -> Bool {
        guard case .operator(let operatorValue)? = peek(),
              operatorValue == value else {
            return false
        }
        index += 1
        return true
    }

    private mutating func consumeIdentifier() -> String? {
        guard case .identifier(let value)? = peek() else {
            return nil
        }
        index += 1
        return value
    }
}

private enum ShaderConditionalToken: Equatable {
    case identifier(String)
    case number(Int)
    case `operator`(String)
}

private struct ShaderMacroArgumentReplacement {
    let raw: String
    let expanded: String
}

private func shaderSingleIdentifier(_ source: String) -> String? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first,
          first.isShaderIdentifierStart else {
        return nil
    }

    guard trimmed.allSatisfy(\.isShaderIdentifierContinue) else {
        return nil
    }

    return trimmed
}

private func shaderSingleCallableIdentifier(_ source: String) -> String? {
    var trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)

    while trimmed.first == "(",
          let closingParen = trimmed.matchingShaderClosingParen(openParen: trimmed.startIndex),
          closingParen == trimmed.index(before: trimmed.endIndex) {
        trimmed = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingParen])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return shaderSingleIdentifier(trimmed)
}

private func splitShaderMacroArguments(_ source: Substring) -> [String] {
    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return []
    }

    var arguments: [String] = []
    var argumentStart = source.startIndex
    var depth = 0
    var index = source.startIndex

    while index < source.endIndex {
        let character = source[index]
        switch character {
        case "(":
            depth += 1
        case ")":
            depth = max(depth - 1, 0)
        case "," where depth == 0:
            arguments.append(source[argumentStart..<index].trimmingCharacters(in: .whitespacesAndNewlines))
            argumentStart = source.index(after: index)
        default:
            break
        }
        index = source.index(after: index)
    }

    arguments.append(source[argumentStart..<source.endIndex].trimmingCharacters(in: .whitespacesAndNewlines))
    return arguments
}

private func substituteShaderMacroParameters(
    parameters: [String],
    arguments: [String],
    in body: String,
    definitions: ShaderPreprocessorDefinitions,
    expanding: Set<String>,
    preserveDefinedOperands: Bool
) -> String {
    let replacements = shaderMacroArgumentReplacements(
        parameters: parameters,
        arguments: arguments,
        definitions: definitions,
        expanding: expanding,
        preserveDefinedOperands: preserveDefinedOperands
    )
    var output = ""
    var index = body.startIndex

    while index < body.endIndex {
        let character = body[index]
        if character == "#" {
            let next = body.index(after: index)
            if next < body.endIndex, body[next] == "#" {
                output += "##"
                index = body.index(after: next)
                continue
            }

            var nameStart = next
            while nameStart < body.endIndex, body[nameStart].isWhitespace {
                nameStart = body.index(after: nameStart)
            }
            if nameStart < body.endIndex, body[nameStart].isShaderIdentifierStart {
                var nameEnd = body.index(after: nameStart)
                while nameEnd < body.endIndex && body[nameEnd].isShaderIdentifierContinue {
                    nameEnd = body.index(after: nameEnd)
                }
                let name = String(body[nameStart..<nameEnd])
                if let replacement = replacements[name] {
                    output += shaderStringifiedMacroArgument(replacement.raw)
                    index = nameEnd
                    continue
                }
            }
        }

        guard character.isShaderIdentifierStart else {
            output.append(character)
            index = body.index(after: index)
            continue
        }

        let nameStart = index
        repeat {
            index = body.index(after: index)
        } while index < body.endIndex && body[index].isShaderIdentifierContinue

        let name = String(body[nameStart..<index])
        if let replacement = replacements[name] {
            let shouldUseRawArgument = shaderMacroParameterTouchesTokenPaste(
                nameStart..<index,
                in: body
            ) || (
                preserveDefinedOperands &&
                shaderMacroParameterIsDefinedOperand(nameStart..<index, in: body)
            )
            output += shouldUseRawArgument ? replacement.raw : replacement.expanded
        } else {
            output += name
        }
    }

    return output
}

private func shaderStringifiedMacroArgument(_ argument: String) -> String {
    let normalized = argument
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    let escaped = normalized
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func shaderMacroArgumentReplacements(
    parameters: [String],
    arguments: [String],
    definitions: ShaderPreprocessorDefinitions,
    expanding: Set<String>,
    preserveDefinedOperands: Bool
) -> [String: ShaderMacroArgumentReplacement] {
    var replacements: [String: ShaderMacroArgumentReplacement] = [:]

    for (index, rawParameter) in parameters.enumerated() {
        let parameter = rawParameter.trimmingCharacters(in: .whitespacesAndNewlines)
        if parameter == "..." {
            replacements["__VA_ARGS__"] = shaderMacroArgumentReplacement(
                raw: arguments.dropFirst(index).joined(separator: ", "),
                expandedArguments: arguments.dropFirst(index),
                definitions: definitions,
                expanding: expanding,
                preserveDefinedOperands: preserveDefinedOperands
            )
        } else if parameter.hasSuffix("...") {
            let variadicName = String(parameter.dropLast(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let variadicArguments = arguments.dropFirst(index).joined(separator: ", ")
            let variadicReplacement = shaderMacroArgumentReplacement(
                raw: variadicArguments,
                expandedArguments: arguments.dropFirst(index),
                definitions: definitions,
                expanding: expanding,
                preserveDefinedOperands: preserveDefinedOperands
            )
            if !variadicName.isEmpty {
                replacements[variadicName] = variadicReplacement
            }
            replacements["__VA_ARGS__"] = variadicReplacement
        } else {
            let raw = index < arguments.count ? arguments[index] : ""
            replacements[parameter] = shaderMacroArgumentReplacement(
                raw: raw,
                expandedArguments: CollectionOfOne(raw),
                definitions: definitions,
                expanding: expanding,
                preserveDefinedOperands: preserveDefinedOperands
            )
        }
    }

    return replacements
}

private func shaderMacroArgumentReplacement<S: Sequence<String>>(
    raw: String,
    expandedArguments: S,
    definitions: ShaderPreprocessorDefinitions,
    expanding: Set<String>,
    preserveDefinedOperands: Bool
) -> ShaderMacroArgumentReplacement {
    ShaderMacroArgumentReplacement(
        raw: raw,
        expanded: expandedArguments.map {
            definitions.expandingFunctionCalls(
                in: $0,
                expanding: expanding,
                wrapFunctionExpansions: false,
                expandObjectMacros: true,
                preserveDefinedOperands: preserveDefinedOperands
            )
        }.joined(separator: ", ")
    )
}

private func shaderMacroParameterTouchesTokenPaste(
    _ range: Range<String.Index>,
    in body: String
) -> Bool {
    var before = range.lowerBound
    while before > body.startIndex {
        let previous = body.index(before: before)
        guard body[previous].isWhitespace else {
            break
        }
        before = previous
    }

    if before > body.startIndex {
        let firstHash = body.index(before: before)
        if firstHash > body.startIndex,
           body[body.index(before: firstHash)] == "#",
           body[firstHash] == "#" {
            return true
        }
    }

    var after = range.upperBound
    while after < body.endIndex, body[after].isWhitespace {
        after = body.index(after: after)
    }

    if after < body.endIndex,
       body[after] == "#" {
        let secondHash = body.index(after: after)
        if secondHash < body.endIndex, body[secondHash] == "#" {
            return true
        }
    }

    return false
}

private func shaderMacroParameterIsDefinedOperand(
    _ range: Range<String.Index>,
    in body: String
) -> Bool {
    if shaderMacroParameterIsParenthesizedDefinedOperand(range, in: body) {
        return true
    }

    return shaderIdentifierBefore(range.lowerBound, in: body) == "defined"
}

private func shaderMacroParameterIsParenthesizedDefinedOperand(
    _ range: Range<String.Index>,
    in body: String
) -> Bool {
    var beforeOperand = range.lowerBound
    while beforeOperand > body.startIndex {
        let previous = body.index(before: beforeOperand)
        guard body[previous].isWhitespace else {
            break
        }
        beforeOperand = previous
    }

    guard beforeOperand > body.startIndex else {
        return false
    }

    let openParen = body.index(before: beforeOperand)
    guard body[openParen] == "(" else {
        return false
    }

    var afterOperand = range.upperBound
    while afterOperand < body.endIndex, body[afterOperand].isWhitespace {
        afterOperand = body.index(after: afterOperand)
    }

    guard afterOperand < body.endIndex, body[afterOperand] == ")" else {
        return false
    }

    return shaderIdentifierBefore(openParen, in: body) == "defined"
}

private func shaderIdentifierBefore(_ index: String.Index, in source: String) -> String? {
    var end = index
    while end > source.startIndex {
        let previous = source.index(before: end)
        guard source[previous].isWhitespace else {
            break
        }
        end = previous
    }

    var start = end
    while start > source.startIndex {
        let previous = source.index(before: start)
        guard source[previous].isShaderIdentifierContinue else {
            break
        }
        start = previous
    }

    guard start < end,
          source[start].isShaderIdentifierStart else {
        return nil
    }

    return String(source[start..<end])
}

private func resolveShaderMacroTokenPastes(in source: String) -> String {
    var result = source
    while let pasteRange = result.range(of: "##") {
        if let commaPasteRange = shaderEmptyVariadicCommaPasteRange(around: pasteRange, in: result) {
            result.replaceSubrange(commaPasteRange, with: "")
            continue
        }

        guard let left = shaderPasteOperandBefore(pasteRange.lowerBound, in: result),
              let right = shaderPasteOperandAfter(pasteRange.upperBound, in: result) else {
            result.replaceSubrange(pasteRange, with: "")
            continue
        }

        let pasted = String(result[left]) + String(result[right])
        result.replaceSubrange(left.lowerBound..<right.upperBound, with: pasted)
    }
    return result
}

private func shaderEmptyVariadicCommaPasteRange(
    around pasteRange: Range<String.Index>,
    in source: String
) -> Range<String.Index>? {
    var commaEnd = pasteRange.lowerBound
    while commaEnd > source.startIndex {
        let previous = source.index(before: commaEnd)
        guard source[previous].isWhitespace else {
            break
        }
        commaEnd = previous
    }

    guard commaEnd > source.startIndex else {
        return nil
    }

    let commaIndex = source.index(before: commaEnd)
    guard source[commaIndex] == "," else {
        return nil
    }

    var end = pasteRange.upperBound
    while end < source.endIndex, source[end].isWhitespace {
        end = source.index(after: end)
    }

    if end == source.endIndex || source[end].isShaderEmptyVariadicPasteDelimiter {
        return commaIndex..<end
    }

    return nil
}

private func shaderPasteOperandBefore(_ index: String.Index, in source: String) -> Range<String.Index>? {
    var end = index
    while end > source.startIndex {
        let previous = source.index(before: end)
        if source[previous].isWhitespace {
            end = previous
        } else {
            break
        }
    }

    guard end > source.startIndex else {
        return nil
    }

    var start = source.index(before: end)
    guard source[start].isShaderTokenPasteOperandContinue else {
        return nil
    }

    while start > source.startIndex {
        let previous = source.index(before: start)
        guard source[previous].isShaderTokenPasteOperandContinue else {
            break
        }
        start = previous
    }

    return start..<end
}

private func shaderPasteOperandAfter(_ index: String.Index, in source: String) -> Range<String.Index>? {
    var start = index
    while start < source.endIndex, source[start].isWhitespace {
        start = source.index(after: start)
    }

    guard start < source.endIndex,
          source[start].isShaderTokenPasteOperandContinue else {
        return nil
    }

    var end = source.index(after: start)
    while end < source.endIndex, source[end].isShaderTokenPasteOperandContinue {
        end = source.index(after: end)
    }

    return start..<end
}

private struct ShaderConditionalTokenizer {
    let source: String

    var tokens: [ShaderConditionalToken] {
        var tokens: [ShaderConditionalToken] = []
        var current = source.startIndex

        while current < source.endIndex {
            let character = source[current]
            if character.isWhitespace {
                current = source.index(after: current)
                continue
            }

            if character == "'" {
                let parsed = parseCharacterLiteral(startingAt: current)
                tokens.append(.number(parsed.value))
                current = parsed.end
                continue
            }

            if character.isNumber {
                let parsed = parseIntegerLiteral(startingAt: current)
                tokens.append(.number(parsed.value))
                current = parsed.end
                continue
            }

            if character.isLetter || character == "_" {
                let start = current
                repeat {
                    current = source.index(after: current)
                } while current < source.endIndex
                    && (source[current].isLetter || source[current].isNumber || source[current] == "_")
                tokens.append(.identifier(String(source[start..<current])))
                continue
            }

            let next = source.index(after: current)
            if next < source.endIndex {
                let twoCharacterOperator = String(source[current...next])
                if ["&&", "||", "==", "!=", ">=", "<=", "<<", ">>"].contains(twoCharacterOperator) {
                    tokens.append(.operator(twoCharacterOperator))
                    current = source.index(after: next)
                    continue
                }
            }

            tokens.append(.operator(String(character)))
            current = next
        }

        return tokens
    }

    private func parseIntegerLiteral(startingAt start: String.Index) -> (value: Int, end: String.Index) {
        var current = start
        var radix = 10
        var digitsStart = start
        var allowDigits: (Character) -> Bool = { $0.isNumber }

        if source[start] == "0" {
            let next = source.index(after: start)
            if next < source.endIndex {
                switch source[next].lowercased() {
                case "x":
                    radix = 16
                    current = source.index(after: next)
                    digitsStart = current
                    allowDigits = { $0.isHexDigit }
                case "b":
                    radix = 2
                    current = source.index(after: next)
                    digitsStart = current
                    allowDigits = { $0 == "0" || $0 == "1" }
                default:
                    radix = 8
                }
            }
        }

        if current == start {
            repeat {
                current = source.index(after: current)
            } while current < source.endIndex && source[current].isNumber
        } else {
            while current < source.endIndex && allowDigits(source[current]) {
                current = source.index(after: current)
            }
        }

        let rawDigits = digitsStart < current ? String(source[digitsStart..<current]) : "0"
        let value = Int(rawDigits, radix: radix) ?? Int(rawDigits) ?? 0
        return (value, endOfIntegerSuffix(startingAt: current))
    }

    private func endOfIntegerSuffix(startingAt start: String.Index) -> String.Index {
        var current = start
        while current < source.endIndex && ["u", "U", "l", "L"].contains(source[current]) {
            current = source.index(after: current)
        }
        return current
    }

    private func parseCharacterLiteral(startingAt start: String.Index) -> (value: Int, end: String.Index) {
        var current = source.index(after: start)
        guard current < source.endIndex else {
            return (0, current)
        }

        let value: Int
        if source[current] == "\\" {
            current = source.index(after: current)
            let escaped = parseEscapedCharacterValue(startingAt: current)
            value = escaped.value
            current = escaped.end
        } else {
            value = source[current].unicodeScalars.first.map { Int($0.value) } ?? 0
            current = source.index(after: current)
        }

        while current < source.endIndex {
            let character = source[current]
            current = source.index(after: current)
            if character == "'" {
                break
            }
        }

        return (value, current)
    }

    private func parseEscapedCharacterValue(startingAt start: String.Index) -> (value: Int, end: String.Index) {
        guard start < source.endIndex else {
            return (0, start)
        }

        let current = start
        switch source[current] {
        case "n":
            return (10, source.index(after: current))
        case "r":
            return (13, source.index(after: current))
        case "t":
            return (9, source.index(after: current))
        case "0":
            return parseOctalEscape(startingAt: current)
        case "x":
            return parseHexEscape(startingAt: source.index(after: current))
        case "\\":
            return (92, source.index(after: current))
        case "'":
            return (39, source.index(after: current))
        case "\"":
            return (34, source.index(after: current))
        default:
            return (source[current].unicodeScalars.first.map { Int($0.value) } ?? 0, source.index(after: current))
        }
    }

    private func parseOctalEscape(startingAt start: String.Index) -> (value: Int, end: String.Index) {
        var current = start
        var count = 0
        while current < source.endIndex,
              count < 3,
              ("0"..."7").contains(source[current]) {
            current = source.index(after: current)
            count += 1
        }
        return (Int(source[start..<current], radix: 8) ?? 0, current)
    }

    private func parseHexEscape(startingAt start: String.Index) -> (value: Int, end: String.Index) {
        var current = start
        while current < source.endIndex && source[current].isHexDigit {
            current = source.index(after: current)
        }
        let rawValue = start < current ? String(source[start..<current]) : "0"
        return (Int(rawValue, radix: 16) ?? 0, current)
    }
}

private extension Character {
    var isShaderIdentifierStart: Bool {
        isLetter || self == "_"
    }

    var isShaderIdentifierContinue: Bool {
        isLetter || isNumber || self == "_"
    }

    var isShaderTokenPasteOperandContinue: Bool {
        isShaderIdentifierContinue
    }

    var isShaderEmptyVariadicPasteDelimiter: Bool {
        self == "," || self == ")"
    }
}

private extension String {
    func removingShaderBlockComments(isInBlockComment: inout Bool) -> String {
        var output = ""
        var index = startIndex

        while index < endIndex {
            let next = self.index(after: index)

            if isInBlockComment {
                if self[index] == "*", next < endIndex, self[next] == "/" {
                    isInBlockComment = false
                    index = self.index(after: next)
                } else {
                    index = next
                }
                continue
            }

            if self[index] == "/", next < endIndex, self[next] == "*" {
                isInBlockComment = true
                index = self.index(after: next)
                continue
            }

            output.append(self[index])
            index = next
        }

        return output
    }

    func matchingShaderClosingParen(openParen: String.Index) -> String.Index? {
        var depth = 0
        var current = openParen
        while current < endIndex {
            switch self[current] {
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
            current = index(after: current)
        }
        return nil
    }

    var trimmedShaderDirectiveArgument: String {
        split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? ""
    }

    func strippingShaderDirectiveComments() -> String {
        var output = ""
        var index = startIndex
        var isInBlockComment = false

        while index < endIndex {
            let next = self.index(after: index)

            if isInBlockComment {
                if self[index] == "*", next < endIndex, self[next] == "/" {
                    isInBlockComment = false
                    index = self.index(after: next)
                } else {
                    index = next
                }
                continue
            }

            if self[index] == "/", next < endIndex {
                if self[next] == "/" {
                    break
                }
                if self[next] == "*" {
                    isInBlockComment = true
                    index = self.index(after: next)
                    continue
                }
            }

            output.append(self[index])
            index = next
        }

        return output
    }
}
