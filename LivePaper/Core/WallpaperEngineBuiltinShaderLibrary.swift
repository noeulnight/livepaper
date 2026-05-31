import Foundation

struct WallpaperEngineBuiltinShaderLibrary: Sendable {
    func shaderStageSource(
        name requestedName: String,
        pathExtension: String
    ) -> WallpaperEngineBuiltinShaderStage? {
        let shaderName = requestedName.normalizedWallpaperEnginePath.lowercased()
        let stageExtension = pathExtension.lowercased()

        guard let source = Self.shaderStages[shaderName]?[stageExtension] else {
            return nil
        }

        return WallpaperEngineBuiltinShaderStage(
            requestedName: shaderName,
            resolvedPath: "builtin/shaders/\(shaderName).\(stageExtension)",
            source: source
        )
    }

    func includeSource(for requestedPath: String) -> WallpaperEngineBuiltinShaderInclude? {
        let includePath = normalizedIncludePath(for: requestedPath)
        let fallbackName = (includePath as NSString).lastPathComponent
        let key = Self.sources[includePath] == nil ? fallbackName : includePath

        guard let source = Self.sources[key] else {
            return nil
        }

        return WallpaperEngineBuiltinShaderInclude(
            requestedPath: includePath,
            resolvedPath: "builtin/\(fallbackName)",
            source: source
        )
    }

    private static let shaderStages: [String: [String: String]] = [
        "genericparticle": [
            "vert": """
            // Built-in Wallpaper Engine compatibility shader: genericparticle.vert
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() { v_TexCoord = a_TexCoord; gl_Position = vec4(a_Position, 1.0); }
            """,
            "frag": """
            // Built-in Wallpaper Engine compatibility shader: genericparticle.frag
            varying vec2 v_TexCoord;
            void main() { gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0); }
            """
        ],
        "genericimage4": [
            "vert": """
            // Built-in Wallpaper Engine compatibility shader: genericimage4.vert
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() { v_TexCoord = a_TexCoord; gl_Position = vec4(a_Position, 1.0); }
            """,
            "frag": """
            // Built-in Wallpaper Engine compatibility shader: genericimage4.frag
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0; // {"hidden":true}
            void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
            """
        ]
    ]

    private func normalizedIncludePath(for requestedPath: String) -> String {
        let normalized = requestedPath.normalizedWallpaperEnginePath.lowercased()
        if normalized.wallpaperEnginePathExtension.isEmpty {
            return "\(normalized).h"
        }
        return normalized
    }

    private static let sources: [String: String] = [
        "common.h": """
        // Built-in Wallpaper Engine compatibility include: common.h
        #define M_PI 3.14159265358979323846
        vec2 rotateVec2(vec2 value, float angle) { float s = sin(angle); float c = cos(angle); return vec2(value.x * c - value.y * s, value.x * s + value.y * c); }
        """,
        "common_blending.h": """
        // Built-in Wallpaper Engine compatibility include: common_blending.h
        vec3 ApplyBlending(int mode, vec3 base, vec3 blend, float opacity) { return mix(base, blend, clamp(opacity, 0.0, 1.0)); }
        """,
        "common_blur.h": """
        // Built-in Wallpaper Engine compatibility include: common_blur.h
        vec4 blur13a(vec2 uv, vec2 direction) { return vec4(0.0); }
        vec4 blur7a(vec2 uv, vec2 direction) { return vec4(0.0); }
        vec4 blur3a(vec2 uv, vec2 direction) { return vec4(0.0); }
        """,
        "common_composite.h": """
        // Built-in Wallpaper Engine compatibility include: common_composite.h
        vec2 ApplyCompositeOffset(vec2 uv, vec2 resolution) { return uv; }
        vec4 ApplyComposite(vec4 base, vec4 overlay) { return overlay; }
        """
    ]
}

struct WallpaperEngineBuiltinShaderInclude: Equatable, Sendable {
    let requestedPath: String
    let resolvedPath: String
    let source: String
}

struct WallpaperEngineBuiltinShaderStage: Equatable, Sendable {
    let requestedName: String
    let resolvedPath: String
    let source: String
}
