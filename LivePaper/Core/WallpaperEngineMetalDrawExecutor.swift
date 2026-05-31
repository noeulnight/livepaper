import Foundation

#if canImport(Metal)
import Metal

enum WallpaperEngineMetalDrawExecutorError: LocalizedError {
    case commandQueueUnavailable
    case commandBufferUnavailable
    case commandBufferFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandQueueUnavailable:
            return "Metal command queue is unavailable."
        case .commandBufferUnavailable:
            return "Metal command buffer is unavailable."
        case .commandBufferFailed(let message):
            return "Metal command buffer failed: \(message)"
        }
    }
}

struct WallpaperEngineMetalDrawExecutionResult: Equatable {
    let encodedDrawIDs: [String]
    let skippedDrawIDs: [String]
    let diagnostics: [String]
}

struct WallpaperEngineMetalDrawExecutor {
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    func render(
        plan: WallpaperEngineMetalRenderPlan,
        compiledScene: WallpaperEngineMetalCompiledScene,
        commandQueue: MTLCommandQueue
    ) throws -> WallpaperEngineMetalDrawExecutionResult {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw WallpaperEngineMetalDrawExecutorError.commandBufferUnavailable
        }

        let vertexBuffer = makeQuadVertexBuffer()
        var encodedDrawIDs: [String] = []
        var skippedDrawIDs: [String] = []
        var diagnostics: [String] = []
        var clearedTargets = Set<String>()

        for draw in plan.draws {
            guard let pipelineID = draw.pipelineID,
                  let pipelineState = compiledScene.pipelineStates[pipelineID] else {
                skippedDrawIDs.append(draw.id)
                diagnostics.append("Skipped draw \(draw.id) because its pipeline is unavailable.")
                continue
            }
            guard let targetTexture = compiledScene.renderTargetTextures[draw.targetTextureKey] else {
                skippedDrawIDs.append(draw.id)
                diagnostics.append("Skipped draw \(draw.id) because target \(draw.targetTextureKey) is unavailable.")
                continue
            }
            guard let renderPassDescriptor = renderPassDescriptor(
                targetTexture: targetTexture,
                targetKey: draw.targetTextureKey,
                clearColor: plan.clearColor,
                clearedTargets: &clearedTargets
            ),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                skippedDrawIDs.append(draw.id)
                diagnostics.append("Skipped draw \(draw.id) because Metal could not create a render encoder.")
                continue
            }

            encoder.label = draw.id
            encoder.setRenderPipelineState(pipelineState)
            if let depthStencilState = compiledScene.depthStencilStates[pipelineID] {
                encoder.setDepthStencilState(depthStencilState)
            }
            encoder.setCullMode(cullMode(for: pipelineID, in: plan))
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            bindTextures(
                draw.textureArguments,
                compiledScene: compiledScene,
                encoder: encoder,
                diagnostics: &diagnostics
            )
            if let uniformBuffer = makeUniformBuffer(draw.uniformArguments) {
                encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
            }

            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            encodedDrawIDs.append(draw.id)
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw WallpaperEngineMetalDrawExecutorError.commandBufferFailed(error.localizedDescription)
        }

        return WallpaperEngineMetalDrawExecutionResult(
            encodedDrawIDs: encodedDrawIDs,
            skippedDrawIDs: skippedDrawIDs,
            diagnostics: diagnostics
        )
    }

    func render(
        plan: WallpaperEngineMetalRenderPlan,
        compiledScene: WallpaperEngineMetalCompiledScene
    ) throws -> WallpaperEngineMetalDrawExecutionResult {
        guard let commandQueue = device.makeCommandQueue() else {
            throw WallpaperEngineMetalDrawExecutorError.commandQueueUnavailable
        }
        return try render(
            plan: plan,
            compiledScene: compiledScene,
            commandQueue: commandQueue
        )
    }

    private func renderPassDescriptor(
        targetTexture: MTLTexture,
        targetKey: String,
        clearColor: WallpaperEngineSceneValue?,
        clearedTargets: inout Set<String>
    ) -> MTLRenderPassDescriptor? {
        let descriptor = MTLRenderPassDescriptor()
        let attachment = descriptor.colorAttachments[0]
        attachment?.texture = targetTexture
        attachment?.storeAction = .store

        if clearedTargets.insert(targetKey).inserted {
            attachment?.loadAction = .clear
            attachment?.clearColor = metalClearColor(clearColor)
        } else {
            attachment?.loadAction = .load
        }

        return descriptor
    }

    private func bindTextures(
        _ arguments: [WallpaperEngineMetalTextureArgument],
        compiledScene: WallpaperEngineMetalCompiledScene,
        encoder: MTLRenderCommandEncoder,
        diagnostics: inout [String]
    ) {
        for argument in arguments {
            guard let index = argument.index else {
                diagnostics.append("Skipped texture \(argument.uniformName) because it has no Metal index.")
                continue
            }
            guard let textureKey = argument.textureKey else {
                diagnostics.append("Skipped texture \(argument.uniformName) because it has no resolved texture key.")
                continue
            }
            guard let texture = texture(for: textureKey, compiledScene: compiledScene) else {
                diagnostics.append("Skipped texture \(argument.uniformName) because resource \(textureKey) is unavailable.")
                continue
            }

            encoder.setVertexTexture(texture, index: index)
            encoder.setFragmentTexture(texture, index: index)
            encoder.setVertexSamplerState(
                samplerState(for: textureKey, compiledScene: compiledScene),
                index: index
            )
            encoder.setFragmentSamplerState(
                samplerState(for: textureKey, compiledScene: compiledScene),
                index: index
            )
        }
    }

    private func texture(
        for key: String,
        compiledScene: WallpaperEngineMetalCompiledScene
    ) -> MTLTexture? {
        compiledScene.sourceTextures[key] ?? compiledScene.renderTargetTextures[key]
    }

    private func samplerState(
        for key: String,
        compiledScene: WallpaperEngineMetalCompiledScene
    ) -> MTLSamplerState {
        compiledScene.sourceSamplerStates[key] ?? compiledScene.samplerState
    }

    private func cullMode(
        for pipelineID: String,
        in plan: WallpaperEngineMetalRenderPlan
    ) -> MTLCullMode {
        guard let pipeline = plan.pipelines.first(where: { $0.id == pipelineID }) else {
            return .none
        }

        switch pipeline.cullMode {
        case .none:
            return .none
        case .back:
            return .back
        }
    }

    private func makeQuadVertexBuffer() -> MTLBuffer {
        let vertices: [Float] = [
            -1, -1, 0, 0, 1,
             1, -1, 0, 1, 1,
            -1,  1, 0, 0, 0,
             1,  1, 0, 1, 0
        ]
        return device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Float>.stride * vertices.count,
            options: .storageModeShared
        )!
    }

    private func makeUniformBuffer(
        _ arguments: [WallpaperEngineMetalUniformArgument]
    ) -> MTLBuffer? {
        var data = Data()
        for argument in arguments {
            appendUniform(argument, to: &data)
        }
        if data.isEmpty {
            data = Data(count: 16)
        }
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }
            return device.makeBuffer(
                bytes: baseAddress,
                length: data.count,
                options: .storageModeShared
            )
        }
    }

    private func appendUniform(
        _ argument: WallpaperEngineMetalUniformArgument,
        to data: inout Data
    ) {
        switch argument.valueType.lowercased() {
        case "int":
            align(&data, to: 4)
            append(Int32(argument.value.intValue ?? 0), to: &data)
        case "bool":
            align(&data, to: 4)
            append(UInt32((argument.value.boolValue ?? false) ? 1 : 0), to: &data)
        case "vec2", "float2":
            align(&data, to: 8)
            appendFloats(argument.value.floatVector(count: 2), to: &data)
        case "vec3", "float3":
            align(&data, to: 16)
            appendFloats(argument.value.floatVector(count: 3), to: &data)
            align(&data, to: 16)
        case "vec4", "float4":
            align(&data, to: 16)
            appendFloats(argument.value.floatVector(count: 4), to: &data)
        case "mat3", "float3x3":
            align(&data, to: 16)
            let values = argument.value.floatVector(count: 9)
            for column in 0..<3 {
                let columnStart = column * 3
                appendFloats(Array(values[columnStart..<(columnStart + 3)]), to: &data)
                align(&data, to: 16)
            }
        case "mat4", "float4x4":
            align(&data, to: 16)
            appendFloats(argument.value.floatVector(count: 16), to: &data)
        default:
            align(&data, to: 4)
            append(Float(argument.value.doubleValue ?? 0), to: &data)
        }
    }

    private func appendFloats(_ values: [Float], to data: inout Data) {
        for value in values {
            append(value, to: &data)
        }
    }

    private func append<T>(_ value: T, to data: inout Data) {
        var mutable = value
        withUnsafeBytes(of: &mutable) {
            data.append(contentsOf: $0)
        }
    }

    private func align(_ data: inout Data, to alignment: Int) {
        let remainder = data.count % alignment
        guard remainder != 0 else {
            return
        }
        data.append(Data(count: alignment - remainder))
    }

    private func metalClearColor(_ value: WallpaperEngineSceneValue?) -> MTLClearColor {
        let components = value?.doubleVector(count: 4) ?? [0, 0, 0, 1]
        return MTLClearColorMake(
            components[0],
            components[1],
            components[2],
            components[3]
        )
    }
}

private extension WallpaperEngineSceneValue {
    var doubleValue: Double? {
        switch self {
        case .bool(let value):
            return value ? 1 : 0
        case .int(let value):
            return Double(value)
        case .double(let value):
            return value
        case .string(let value):
            return Double(value)
        case .user(_, let value), .animation(let value, _):
            return value?.doubleValue
        case .vector2, .vector3, .vector4, .array, .object, .null:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .bool(let value):
            return value ? 1 : 0
        case .int(let value):
            return value
        case .double(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        case .user(_, let value), .animation(let value, _):
            return value?.intValue
        case .vector2, .vector3, .vector4, .array, .object, .null:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .int(let value):
            return value != 0
        case .double(let value):
            return value != 0
        case .string(let value):
            return Bool(value)
        case .user(_, let value), .animation(let value, _):
            return value?.boolValue
        case .vector2, .vector3, .vector4, .array, .object, .null:
            return nil
        }
    }

    func doubleVector(count: Int) -> [Double] {
        let values: [Double]
        switch self {
        case .vector2(let value):
            values = [value.x, value.y]
        case .vector3(let value):
            values = [value.x, value.y, value.z]
        case .vector4(let value):
            values = [value.x, value.y, value.z, value.w]
        case .array(let array):
            values = array.compactMap(\.doubleValue)
        case .string(let value):
            values = value
                .split(whereSeparator: \.isWhitespace)
                .compactMap { Double($0) }
        case .user(_, let value), .animation(let value, _):
            values = value?.doubleVector(count: count) ?? []
        default:
            values = doubleValue.map { [$0] } ?? []
        }

        let fallback = count == 4 ? [0.0, 0.0, 0.0, 1.0] : Array(repeating: 0.0, count: count)
        return Array((values + fallback).prefix(count))
    }

    func floatVector(count: Int) -> [Float] {
        doubleVector(count: count).map(Float.init)
    }
}
#endif
