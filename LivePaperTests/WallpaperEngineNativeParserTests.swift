import Foundation
#if canImport(Compression)
import Compression
#endif
#if canImport(Metal)
import Metal
#endif
import XCTest
@testable import LivePaper

final class WallpaperEngineNativeParserTests: XCTestCase {
    func testPackageParserReadsIndexAndPayloadEntries() throws {
        let folderURL = try makeTemporaryDirectory()
        let packageURL = folderURL.appendingPathComponent("scene.pkg")
        try makePackageData(files: [
            ("scene.json", Data(#"{"objects":[]}"#.utf8)),
            ("materials/demo.tex", Data([1, 2, 3]))
        ]).write(to: packageURL)

        let package = try WallpaperEnginePackageParser().parsePackage(at: packageURL)

        XCTAssertEqual(package.header, "PKGV0023")
        XCTAssertEqual(package.entries.map(\.path), ["scene.json", "materials/demo.tex"])
        XCTAssertEqual(package.data(for: "scene.json"), Data(#"{"objects":[]}"#.utf8))
        XCTAssertTrue(package.contains("materials\\demo.tex"))
    }

    func testTextureParserReadsHeaderMipmapAndAnimationFrames() throws {
        let texture = try WallpaperEngineTextureParser().parseTexture(
            data: makeTextureData(flags: 2 | 4),
            path: "materials/demo.tex"
        )

        XCTAssertEqual(texture.path, "materials/demo.tex")
        XCTAssertEqual(texture.format, .r8)
        XCTAssertEqual(texture.flags, 6)
        XCTAssertEqual(texture.containerVersion, .texb0003)
        XCTAssertEqual(texture.imageCount, 1)
        XCTAssertEqual(texture.mipmaps.count, 1)
        XCTAssertEqual(texture.mipmaps[0].width, 16)
        XCTAssertEqual(texture.mipmaps[0].height, 8)
        XCTAssertEqual(texture.mipmaps[0].data.count, 16 * 8)
        XCTAssertEqual(texture.animationVersion, .texs0003)
        XCTAssertEqual(texture.gifWidth, 16)
        XCTAssertEqual(texture.gifHeight, 8)
        XCTAssertEqual(texture.frames.count, 1)
    }

    func testTextureParserInflatesLZ4CompressedMipmaps() throws {
#if canImport(Compression)
        let pixels = Data((0..<(16 * 8)).map { UInt8(($0 * 7) % 251) })
        let compressedPixels = try lz4Compressed(pixels)

        let texture = try WallpaperEngineTextureParser().parseTexture(
            data: makeTextureData(
                flags: 2,
                pixels: pixels,
                storedPixels: compressedPixels,
                compression: 1,
                uncompressedSize: Int32(pixels.count)
            ),
            path: "materials/compressed.tex"
        )

        let mipmap = try XCTUnwrap(texture.mipmaps.first)
        XCTAssertEqual(mipmap.compression, 1)
        XCTAssertEqual(mipmap.uncompressedSize, Int32(pixels.count))
        XCTAssertEqual(mipmap.byteCount, Int32(compressedPixels.count))
        XCTAssertEqual(mipmap.data, pixels)
#else
        throw XCTSkip("Compression framework is unavailable.")
#endif
    }

    func testTextureParserInflatesRawLZ4BlockMipmaps() throws {
        let pixels = Data("abcabcabcabc".utf8)
        let rawLZ4Block = Data([
            0x35,
            0x61, 0x62, 0x63,
            0x03, 0x00
        ])

        let texture = try WallpaperEngineTextureParser().parseTexture(
            data: makeTextureData(
                flags: 2,
                pixels: pixels,
                storedPixels: rawLZ4Block,
                compression: 1,
                uncompressedSize: Int32(pixels.count)
            ),
            path: "materials/raw-lz4.tex"
        )

        let mipmap = try XCTUnwrap(texture.mipmaps.first)
        XCTAssertEqual(mipmap.compression, 1)
        XCTAssertEqual(mipmap.data, pixels)
    }

    func testMetalRenderPlanUsesPerImageMipmapCountForArrayTextures() throws {
        let texture = WallpaperEngineTextureInfo(
            path: "materials/array.tex",
            format: .r8,
            rawFormat: 9,
            flags: 0,
            textureWidth: 16,
            textureHeight: 16,
            imageWidth: 16,
            imageHeight: 16,
            containerVersion: .texb0003,
            rawContainerVersion: "TEXB0003",
            freeImageFormat: -1,
            isVideoMP4: false,
            imageCount: 2,
            mipmaps: [
                makeMipmap(imageIndex: 0, level: 0, width: 16, height: 16),
                makeMipmap(imageIndex: 0, level: 1, width: 8, height: 8),
                makeMipmap(imageIndex: 1, level: 0, width: 16, height: 16),
                makeMipmap(imageIndex: 1, level: 1, width: 8, height: 8)
            ],
            animationVersion: nil,
            gifWidth: nil,
            gifHeight: nil,
            frames: []
        )
        let commandPlan = WallpaperEngineSceneRenderCommandPlan(
            canvasSize: nil,
            clearColor: nil,
            sceneFramebuffer: "_rt_FullFrameBuffer",
            framebuffers: [],
            objectFramebuffers: [],
            commands: []
        )

        let plan = WallpaperEngineMetalRenderPlanBuilder().buildPlan(
            commandPlan: commandPlan,
            textures: ["materials/array.tex": texture],
            metalShaders: []
        )

        let descriptor = try XCTUnwrap(plan.textures.first)
        XCTAssertEqual(descriptor.path, "materials/array.tex")
        XCTAssertEqual(descriptor.imageCount, 2)
        XCTAssertEqual(descriptor.mipmapLevelCount, 2)
    }

    func testMetalRenderPlanMapsTextureSamplerFlags() throws {
        let texture = WallpaperEngineTextureInfo(
            path: "materials/nearest-border.tex",
            format: .r8,
            rawFormat: 9,
            flags: WallpaperEngineTextureParser.Flags.noInterpolation
                | WallpaperEngineTextureParser.Flags.clampUVsBorder,
            textureWidth: 16,
            textureHeight: 16,
            imageWidth: 16,
            imageHeight: 16,
            containerVersion: .texb0003,
            rawContainerVersion: "TEXB0003",
            freeImageFormat: -1,
            isVideoMP4: false,
            imageCount: 1,
            mipmaps: [
                makeMipmap(imageIndex: 0, level: 0, width: 16, height: 16),
                makeMipmap(imageIndex: 0, level: 1, width: 8, height: 8)
            ],
            animationVersion: nil,
            gifWidth: nil,
            gifHeight: nil,
            frames: []
        )
        let commandPlan = WallpaperEngineSceneRenderCommandPlan(
            canvasSize: nil,
            clearColor: nil,
            sceneFramebuffer: "_rt_FullFrameBuffer",
            framebuffers: [],
            objectFramebuffers: [],
            commands: []
        )

        let descriptor = try XCTUnwrap(WallpaperEngineMetalRenderPlanBuilder().buildPlan(
            commandPlan: commandPlan,
            textures: ["materials/nearest-border.tex": texture],
            metalShaders: []
        ).textures.first)

        XCTAssertEqual(descriptor.sampler.minFilter, .nearest)
        XCTAssertEqual(descriptor.sampler.magFilter, .nearest)
        XCTAssertEqual(descriptor.sampler.mipFilter, .nearest)
        XCTAssertEqual(descriptor.sampler.addressModeU, .clampToBorderColor)
        XCTAssertEqual(descriptor.sampler.addressModeV, .clampToBorderColor)
    }

    func testShaderPreprocessorHonorsTextureComboRequireConditions() throws {
        let source = """
        // [COMBO] {"combo":"ENABLEMASK","default":0}
        // [COMBO] {"combo":"A","default":0}
        // [COMBO] {"combo":"B","default":0}
        // [COMBO] {"combo":"lowercaseMode","default":0}
        uniform sampler2D g_Texture0; // {"combo":"MASK","default":"util/noise","require":{"ENABLEMASK":1}}
        uniform sampler2D g_Texture1; // {"combo":"ANYMASK","default":"util/noise","require":{"A":1,"B":1},"requireany":true}
        #if MASK
        #include "mask_branch.h"
        #endif
        #if ANYMASK
        #include "any_branch.h"
        #endif
        #if LOWERCASEMODE
        #include "lower_branch.h"
        #endif
        void main() { gl_FragColor = vec4(1.0); }
        """
        let parser = WallpaperEngineShaderParser()
        let metadata = parser.parseShader(source: source, path: "shaders/require.frag", stage: .fragment)
        let shader = WallpaperEngineResolvedShader(
            name: "require",
            vertexPath: nil,
            fragmentPath: "shaders/require.frag",
            vertexSource: nil,
            fragmentSource: source,
            vertexMetadata: nil,
            fragmentMetadata: metadata
        )
        let includes = [
            "mask_branch.h": makeShaderInclude("mask_branch.h"),
            "any_branch.h": makeShaderInclude("any_branch.h"),
            "lower_branch.h": makeShaderInclude("lower_branch.h")
        ]
        let preprocessor = WallpaperEngineShaderPreprocessor()

        let inactive = preprocessor.prepare(
            shader: shader,
            usage: "test",
            materialCombos: ["ENABLEMASK": 0, "A": 0, "B": 0, "lowercaseMode": 0],
            textureBindings: [],
            includes: includes
        )
        XCTAssertEqual(inactive.combos["MASK"], 0)
        XCTAssertEqual(inactive.combos["ANYMASK"], 0)
        XCTAssertEqual(inactive.combos["LOWERCASEMODE"], 0)
        XCTAssertTrue(inactive.includedPaths.isEmpty)

        let required = preprocessor.prepare(
            shader: shader,
            usage: "test",
            materialCombos: ["ENABLEMASK": 1, "A": 0, "B": 1, "lowercaseMode": 1],
            textureBindings: [],
            includes: includes
        )
        XCTAssertEqual(required.combos["MASK"], 1)
        XCTAssertEqual(required.combos["ANYMASK"], 1)
        XCTAssertEqual(required.combos["LOWERCASEMODE"], 1)
        XCTAssertEqual(required.includedPaths, ["any_branch.h", "lower_branch.h", "mask_branch.h"])

        let bound = preprocessor.prepare(
            shader: shader,
            usage: "test",
            materialCombos: ["ENABLEMASK": 0, "A": 0, "B": 0, "lowercaseMode": 0],
            textureBindings: [
                WallpaperEngineRenderTextureBinding(index: 0, reference: .asset("materials/mask.tex"))
            ],
            includes: includes
        )
        XCTAssertEqual(bound.combos["MASK"], 1)
        XCTAssertEqual(bound.combos["ANYMASK"], 0)
        XCTAssertEqual(bound.includedPaths, ["mask_branch.h"])
    }

    func testShaderPreprocessorBranchParserKeepsInactiveDefinesOutOfActivePass() throws {
        let source = """
        #define MODE 1
        #if MODE == 0
        #define LEAKED_BRANCH 1
        #include "inactive_first.h"
        #elif MODE == 1
        #define SELECTED_BRANCH 1
        #include "selected.h"
        #else
        #include "inactive_else.h"
        #endif
        #if defined(LEAKED_BRANCH)
        #include "leaked.h"
        #elif defined(SELECTED_BRANCH)
        #include "selected_followup.h"
        #endif
        void main() { gl_FragColor = vec4(1.0); }
        """
        let parser = WallpaperEngineShaderParser()
        let shader = WallpaperEngineResolvedShader(
            name: "branch",
            vertexPath: nil,
            fragmentPath: "shaders/branch.frag",
            vertexSource: nil,
            fragmentSource: source,
            vertexMetadata: nil,
            fragmentMetadata: parser.parseShader(source: source, path: "shaders/branch.frag", stage: .fragment)
        )
        let includes = [
            "inactive_first.h": makeShaderInclude("inactive_first.h"),
            "inactive_else.h": makeShaderInclude("inactive_else.h"),
            "leaked.h": makeShaderInclude("leaked.h"),
            "selected.h": makeShaderInclude("selected.h"),
            "selected_followup.h": makeShaderInclude("selected_followup.h")
        ]

        let prepared = WallpaperEngineShaderPreprocessor().prepare(
            shader: shader,
            usage: "test",
            materialCombos: [:],
            textureBindings: [],
            includes: includes
        )

        XCTAssertEqual(prepared.includedPaths, ["selected.h", "selected_followup.h"])
        XCTAssertTrue(prepared.fragmentSource?.contains("selectedHelper") == true)
        XCTAssertTrue(prepared.fragmentSource?.contains("selected_followupHelper") == true)
        XCTAssertTrue(prepared.fragmentSource?.contains("inactive_firstHelper") == false)
        XCTAssertTrue(prepared.fragmentSource?.contains("inactive_elseHelper") == false)
        XCTAssertTrue(prepared.fragmentSource?.contains("leakedHelper") == false)
    }

    func testShaderPreprocessorAcceptsWhitespaceAfterDirectiveMarker() throws {
        let source = """
        # define SPACED_BRANCH 1
        # if SPACED_BRANCH
        # include "spaced.h"
        # else
        # include "inactive_spaced_else.h"
        # endif
        # undef SPACED_BRANCH
        # ifdef SPACED_BRANCH
        # include "still_defined.h"
        # elifndef SPACED_BRANCH
        # include "undefined_followup.h"
        # endif
        void main() { gl_FragColor = vec4(1.0); }
        """
        let parser = WallpaperEngineShaderParser()
        let shader = WallpaperEngineResolvedShader(
            name: "spaced-directive",
            vertexPath: nil,
            fragmentPath: "shaders/spaced.frag",
            vertexSource: nil,
            fragmentSource: source,
            vertexMetadata: nil,
            fragmentMetadata: parser.parseShader(source: source, path: "shaders/spaced.frag", stage: .fragment)
        )
        let includes = [
            "inactive_spaced_else.h": makeShaderInclude("inactive_spaced_else.h"),
            "spaced.h": makeShaderInclude("spaced.h"),
            "still_defined.h": makeShaderInclude("still_defined.h"),
            "undefined_followup.h": makeShaderInclude("undefined_followup.h")
        ]

        let prepared = WallpaperEngineShaderPreprocessor().prepare(
            shader: shader,
            usage: "test",
            materialCombos: [:],
            textureBindings: [],
            includes: includes
        )
        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertEqual(prepared.includedPaths, ["spaced.h", "undefined_followup.h"])
        XCTAssertTrue(prepared.fragmentSource?.contains("spacedHelper") == true)
        XCTAssertTrue(prepared.fragmentSource?.contains("undefined_followupHelper") == true)
        XCTAssertTrue(prepared.fragmentSource?.contains("inactive_spaced_elseHelper") == false)
        XCTAssertTrue(prepared.fragmentSource?.contains("still_definedHelper") == false)
        XCTAssertTrue(metadataSource.contains(#"#include "spaced.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "undefined_followup.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("inactive_spaced_else.h"), metadataSource)
        XCTAssertFalse(metadataSource.contains("still_defined.h"), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserKeepsKnownBranchesPreciseForMetadata() throws {
        let source = """
        #define KNOWN_BRANCH 1
        #if KNOWN_BRANCH
        #include "known.h"
        #elif UNKNOWN_AFTER_KNOWN
        #include "unknown_after_known.h"
        #else
        #include "else_after_known.h"
        #endif
        #if UNKNOWN_BRANCH
        #include "possible_unknown.h"
        #elif KNOWN_BRANCH
        #include "possible_known_fallback.h"
        #endif
        #if UNKNOWN_GUARD
        #include "possible_unknown_guard.h"
        #elif KNOWN_BRANCH
        #include "known_exhausts_unknown_guard.h"
        #else
        #include "impossible_after_known_elif.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertTrue(metadataSource.contains(#"#include "known.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("unknown_after_known.h"), metadataSource)
        XCTAssertFalse(metadataSource.contains("else_after_known.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_unknown.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_known_fallback.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_unknown_guard.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "known_exhausts_unknown_guard.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_after_known_elif.h"), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserTracksConditionalDefines() throws {
        let source = """
        #define ALWAYS_DEFINED 1
        #if UNKNOWN_FEATURE
        #define CONDITIONAL_FLAG 1
        #define CONDITIONAL_ZERO 0
        #define CONDITIONAL_INCLUDE "conditional_macro.h"
        #undef ALWAYS_DEFINED
        #endif
        #ifdef CONDITIONAL_FLAG
        #include "conditional_flag.h"
        #else
        #include "conditional_flag_else.h"
        #endif
        #if CONDITIONAL_FLAG
        #include "conditional_value_true.h"
        #else
        #include "conditional_value_false.h"
        #endif
        #if CONDITIONAL_ZERO
        #include "conditional_zero_true.h"
        #else
        #include "conditional_zero_false.h"
        #endif
        #ifdef ALWAYS_DEFINED
        #include "always_defined_maybe.h"
        #else
        #include "always_undefined_maybe.h"
        #endif
        #include CONDITIONAL_INCLUDE
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertTrue(metadataSource.contains(#"#include "conditional_flag.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "conditional_flag_else.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "conditional_value_true.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "conditional_value_false.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("conditional_zero_true.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "conditional_zero_false.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "always_defined_maybe.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "always_undefined_maybe.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "conditional_macro.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserRetainsConditionalFunctionMacros() throws {
        let source = """
        #define REAL_FLAG 1
        #if UNKNOWN_FEATURE
        #define OPTIONAL_ENABLED(name) defined(name)
        #endif
        #if OPTIONAL_ENABLED(REAL_FLAG)
        #include "possible_optional_function.h"
        #else
        #include "optional_function_else.h"
        #endif
        #if OPTIONAL_ENABLED(REAL_FLAG) && 0
        #include "impossible_optional_function_and.h"
        #else
        #include "possible_optional_function_and_else.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertTrue(metadataSource.contains(#"#include "possible_optional_function.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "optional_function_else.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_optional_function_and.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_optional_function_and_else.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserExpandsConditionalFunctionMacroIncludes() throws {
        let source = """
        #define OPTIONAL_INCLUDE_FILE conditional_function_include.h
        #define OPTIONAL_STRINGIFY(path) #path
        #if UNKNOWN_FEATURE
        #define OPTIONAL_INCLUDE(path) OPTIONAL_STRINGIFY(path)
        #endif
        #if UNKNOWN_GUARD
        #include OPTIONAL_INCLUDE(OPTIONAL_INCLUDE_FILE)
        #else
        #include "conditional_function_include_else.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertTrue(metadataSource.contains(#"#include "conditional_function_include.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "conditional_function_include_else.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains(#"#include "OPTIONAL_INCLUDE("#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserExpandsConditionalObjectMacroIncludeAliases() throws {
        let source = """
        #if UNKNOWN_FILE
        #define OPTIONAL_INCLUDE_FILE conditional_object_alias_include.h
        #endif
        #if UNKNOWN_ALIAS
        #define OPTIONAL_INCLUDE_ALIAS OPTIONAL_INCLUDE_FILE
        #endif
        #if UNKNOWN_GUARD
        #include OPTIONAL_INCLUDE_ALIAS
        #else
        #include "conditional_object_alias_else.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertTrue(metadataSource.contains(#"#include "conditional_object_alias_include.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "conditional_object_alias_else.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains(#"#include "OPTIONAL_INCLUDE_FILE""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserRetainsConditionalFunctionAliases() throws {
        let source = """
        #define FLAGS 0x4
        #define HAS_MASK(value, bit) (((value) & (bit)) == (bit))
        #if UNKNOWN_FEATURE
        #define MAYBE_MASK HAS_MASK
        #endif
        #if MAYBE_MASK(FLAGS, 0x4)
        #include "possible_conditional_alias.h"
        #else
        #include "conditional_alias_else.h"
        #endif
        #if MAYBE_MASK(FLAGS, 0x4) && 0
        #include "impossible_conditional_alias_and.h"
        #else
        #include "possible_conditional_alias_and_else.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertTrue(metadataSource.contains(#"#include "possible_conditional_alias.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "conditional_alias_else.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_conditional_alias_and.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_conditional_alias_and_else.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserNarrowsConditionalMacroValues() throws {
        let source = """
        #if UNKNOWN_A
        #define ALT_MODE 1
        #endif
        #if UNKNOWN_B
        #define ALT_MODE 2
        #endif
        #if ALT_MODE == 3
        #include "impossible_alt_mode_three.h"
        #else
        #include "possible_alt_mode_else.h"
        #endif
        #if ALT_MODE == 2
        #include "possible_alt_mode_two.h"
        #else
        #include "possible_alt_mode_not_two.h"
        #endif
        #if UNKNOWN_ZERO
        #define MAYBE_ZERO 0
        #endif
        #if MAYBE_ZERO
        #include "impossible_maybe_zero_true.h"
        #else
        #include "possible_maybe_zero_false.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertFalse(metadataSource.contains("impossible_alt_mode_three.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_alt_mode_else.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_alt_mode_two.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_alt_mode_not_two.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_maybe_zero_true.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_maybe_zero_false.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserNarrowsTernaryValues() throws {
        let source = """
        #if UNKNOWN_A
        #define ALT_MODE 1
        #endif
        #if UNKNOWN_B
        #define ALT_MODE 2
        #endif
        #if ((ALT_MODE == 1) ? 8 : 4) == 16
        #include "impossible_ternary_value.h"
        #else
        #include "possible_ternary_value_else.h"
        #endif
        #if ((ALT_MODE == 1) ? 8 : 4) == 8
        #include "possible_ternary_value_eight.h"
        #else
        #include "possible_ternary_value_not_eight.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertFalse(metadataSource.contains("impossible_ternary_value.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_ternary_value_else.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_ternary_value_eight.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_ternary_value_not_eight.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserNarrowsDefinedValues() throws {
        let source = """
        #if UNKNOWN_FEATURE
        #define OPTIONAL_SWITCH 1
        #endif
        #if defined(OPTIONAL_SWITCH) == 2
        #include "impossible_defined_two.h"
        #else
        #include "possible_defined_not_two.h"
        #endif
        #if defined(OPTIONAL_SWITCH) == 1
        #include "possible_defined_one.h"
        #else
        #include "possible_defined_zero.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertFalse(metadataSource.contains("impossible_defined_two.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_defined_not_two.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_defined_one.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_defined_zero.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserTracksExhaustiveConditionalDefines() throws {
        let source = """
        #if UNKNOWN_FEATURE
        #define EXHAUSTIVE_MODE 1
        #else
        #define EXHAUSTIVE_MODE 2
        #endif
        #if defined(EXHAUSTIVE_MODE) == 0
        #include "impossible_exhaustive_undefined.h"
        #else
        #include "possible_exhaustive_defined.h"
        #endif
        #if EXHAUSTIVE_MODE == 0
        #include "impossible_exhaustive_zero.h"
        #else
        #include "possible_exhaustive_nonzero.h"
        #endif
        #if EXHAUSTIVE_MODE == 1
        #include "possible_exhaustive_one.h"
        #else
        #include "possible_exhaustive_not_one.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertFalse(metadataSource.contains("impossible_exhaustive_undefined.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_exhaustive_defined.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_exhaustive_zero.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_exhaustive_nonzero.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_exhaustive_one.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_exhaustive_not_one.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserExhaustsFiniteValueElifChains() throws {
        let source = """
        #if UNKNOWN_FEATURE
        #define ENUM_MODE 1
        #else
        #define ENUM_MODE 2
        #endif
        #if ENUM_MODE == 1
        #include "possible_enum_one.h"
        #elif ENUM_MODE == 2
        #include "possible_enum_two.h"
        #else
        #include "impossible_enum_else.h"
        #endif
        #if ENUM_MODE == 1 || ENUM_MODE == 2
        #include "possible_enum_tautology.h"
        #else
        #include "impossible_enum_tautology_else.h"
        #endif
        #if (ENUM_MODE & 0x1) == 0
        #include "possible_enum_even.h"
        #elif (ENUM_MODE & 0x1) == 1
        #include "possible_enum_odd.h"
        #else
        #include "impossible_enum_bitmask_else.h"
        #endif
        #if ENUM_MODE == 1
        #include "possible_enum_duplicate_first.h"
        #elif ENUM_MODE == 1
        #include "impossible_enum_duplicate_elif.h"
        #else
        #include "possible_enum_duplicate_else.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertTrue(metadataSource.contains(#"#include "possible_enum_one.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_enum_two.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_enum_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_enum_tautology.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_enum_tautology_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_enum_even.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_enum_odd.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_enum_bitmask_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_enum_duplicate_first.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_enum_duplicate_elif.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_enum_duplicate_else.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserExhaustsDefinednessElifChains() throws {
        let source = """
        #if UNKNOWN_FEATURE
        #define MAYBE_DEFINED 1
        #endif
        #if defined(MAYBE_DEFINED)
        #include "possible_defined_arm.h"
        #elif !defined(MAYBE_DEFINED)
        #include "possible_undefined_arm.h"
        #else
        #include "impossible_definedness_else.h"
        #endif
        #ifdef MAYBE_DEFINED
        #include "possible_ifdef_arm.h"
        #elifndef MAYBE_DEFINED
        #include "possible_elifndef_arm.h"
        #else
        #include "impossible_ifdef_else.h"
        #endif
        #ifndef MAYBE_DEFINED
        #include "possible_ifndef_arm.h"
        #elifdef MAYBE_DEFINED
        #include "possible_elifdef_arm.h"
        #else
        #include "impossible_ifndef_else.h"
        #endif
        #if defined(MAYBE_DEFINED)
        #include "possible_duplicate_defined_first.h"
        #elif defined(MAYBE_DEFINED)
        #include "impossible_duplicate_defined_elif.h"
        #else
        #include "possible_duplicate_defined_else.h"
        #endif
        #if !defined(MAYBE_DEFINED)
        #include "possible_duplicate_undefined_first.h"
        #elif !defined(MAYBE_DEFINED)
        #include "impossible_duplicate_undefined_elif.h"
        #else
        #include "possible_duplicate_undefined_else.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertTrue(metadataSource.contains(#"#include "possible_defined_arm.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_undefined_arm.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_definedness_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_ifdef_arm.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_elifndef_arm.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_ifdef_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_ifndef_arm.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_elifdef_arm.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_ifndef_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_duplicate_defined_first.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_duplicate_defined_elif.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_duplicate_defined_else.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_duplicate_undefined_first.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_duplicate_undefined_elif.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_duplicate_undefined_else.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserNarrowsConditionsInsideCurrentArm() throws {
        let source = """
        #if UNKNOWN_FEATURE
        #define CURRENT_MODE 1
        #else
        #define CURRENT_MODE 2
        #endif
        #if CURRENT_MODE == 1
        #if CURRENT_MODE == 2
        #include "impossible_current_mode_two_inside_one.h"
        #else
        #include "possible_current_mode_not_two_inside_one.h"
        #endif
        #elif CURRENT_MODE == 2
        #if CURRENT_MODE == 1
        #include "impossible_current_mode_one_inside_two.h"
        #else
        #include "possible_current_mode_not_one_inside_two.h"
        #endif
        #else
        #include "impossible_current_mode_outer_else.h"
        #endif
        #if CURRENT_MODE == 1
        #include "possible_current_mode_outer_one.h"
        #else
        #if CURRENT_MODE == 1
        #include "impossible_current_mode_one_inside_else.h"
        #else
        #include "possible_current_mode_not_one_inside_else.h"
        #endif
        #endif
        #if UNKNOWN_DEFINED
        #define CURRENT_DEFINED 0
        #endif
        #if defined(CURRENT_DEFINED)
        #if defined(CURRENT_DEFINED)
        #include "possible_current_defined_inside_defined.h"
        #else
        #include "impossible_current_undefined_inside_defined.h"
        #endif
        #else
        #if defined(CURRENT_DEFINED)
        #include "impossible_current_defined_inside_undefined.h"
        #else
        #include "possible_current_undefined_inside_undefined.h"
        #endif
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertFalse(metadataSource.contains("impossible_current_mode_two_inside_one.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_current_mode_not_two_inside_one.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_current_mode_one_inside_two.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_current_mode_not_one_inside_two.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_current_mode_outer_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_current_mode_outer_one.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_current_mode_one_inside_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_current_mode_not_one_inside_else.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_current_defined_inside_defined.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_current_undefined_inside_defined.h"), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_current_defined_inside_undefined.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_current_undefined_inside_undefined.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserNarrowsPartialUnknownConditions() throws {
        let source = """
        #if UNKNOWN_FEATURE
        #define PARTIAL_MODE 1
        #else
        #define PARTIAL_MODE 2
        #endif
        #if PARTIAL_MODE == 1 && UNKNOWN_GUARD
        #if PARTIAL_MODE == 2
        #include "impossible_partial_mode_two_inside_one.h"
        #else
        #include "possible_partial_mode_not_two_inside_one.h"
        #endif
        #elif PARTIAL_MODE == 1
        #include "possible_partial_mode_one_fallback.h"
        #endif
        #if PARTIAL_MODE == 1 || UNKNOWN_GUARD
        #include "possible_partial_mode_or_unknown.h"
        #else
        #if PARTIAL_MODE == 1
        #include "impossible_partial_mode_one_inside_or_else.h"
        #else
        #include "possible_partial_mode_not_one_inside_or_else.h"
        #endif
        #endif
        #if UNKNOWN_DEFINED
        #define PARTIAL_DEFINED 0
        #endif
        #if defined(PARTIAL_DEFINED) && UNKNOWN_GUARD
        #if !defined(PARTIAL_DEFINED)
        #include "impossible_partial_undefined_inside_defined.h"
        #else
        #include "possible_partial_defined_inside_defined.h"
        #endif
        #elif defined(PARTIAL_DEFINED)
        #include "possible_partial_defined_fallback.h"
        #else
        #include "possible_partial_undefined_path.h"
        #endif
        #if defined(PARTIAL_DEFINED) || UNKNOWN_GUARD
        #include "possible_partial_defined_or_unknown.h"
        #else
        #ifdef PARTIAL_DEFINED
        #include "impossible_partial_defined_inside_or_else.h"
        #else
        #include "possible_partial_undefined_inside_or_else.h"
        #endif
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertFalse(metadataSource.contains("impossible_partial_mode_two_inside_one.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_partial_mode_not_two_inside_one.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_partial_mode_one_fallback.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_partial_mode_or_unknown.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_partial_mode_one_inside_or_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_partial_mode_not_one_inside_or_else.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_partial_undefined_inside_defined.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_partial_defined_inside_defined.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_partial_defined_fallback.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_partial_undefined_path.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_partial_defined_or_unknown.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_partial_defined_inside_or_else.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_partial_undefined_inside_or_else.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserKeepsNestedExhaustiveDefinesScoped() throws {
        let source = """
        #if OUTER_UNKNOWN
        #if INNER_UNKNOWN
        #define NESTED_MODE 1
        #else
        #define NESTED_MODE 2
        #endif
        #endif
        #if defined(NESTED_MODE) == 0
        #include "possible_nested_undefined.h"
        #else
        #include "possible_nested_defined.h"
        #endif
        #if NESTED_MODE == 0
        #include "possible_nested_zero.h"
        #else
        #include "possible_nested_nonzero.h"
        #endif
        #if NESTED_MODE == 1
        #include "possible_nested_one.h"
        #else
        #include "possible_nested_not_one.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertTrue(metadataSource.contains(#"#include "possible_nested_undefined.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_nested_defined.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_nested_zero.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_nested_nonzero.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_nested_one.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_nested_not_one.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserDropsDefinitionsUndefedWithinExhaustiveArm() throws {
        let source = """
        #if UNKNOWN_FEATURE
        #define CLEANED_MODE 1
        #undef CLEANED_MODE
        #else
        #define CLEANED_MODE 2
        #endif
        #if CLEANED_MODE == 1
        #include "impossible_cleaned_one.h"
        #else
        #include "possible_cleaned_not_one.h"
        #endif
        #if CLEANED_MODE == 0
        #include "possible_cleaned_zero.h"
        #else
        #include "possible_cleaned_nonzero.h"
        #endif
        #if CLEANED_MODE == 2
        #include "possible_cleaned_two.h"
        #else
        #include "possible_cleaned_not_two.h"
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertFalse(metadataSource.contains("impossible_cleaned_one.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_cleaned_not_one.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_cleaned_zero.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_cleaned_nonzero.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_cleaned_two.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_cleaned_not_two.h""#), metadataSource)
    }

    func testShaderPreprocessorPotentialBranchParserKeepsSiblingArmDefinesOutOfElifConditions() throws {
        let source = """
        #if UNKNOWN_FEATURE
        #define SIBLING_ONLY 1
        #elif SIBLING_ONLY
        #include "impossible_sibling_elif.h"
        #else
        #include "possible_sibling_else.h"
        #endif
        #if SIBLING_ONLY
        #include "possible_after_sibling_defined.h"
        #else
        #include "possible_after_sibling_undefined.h"
        #endif
        #if OUTER_UNKNOWN
        #define OUTER_ONLY 1
        #else
        #if OUTER_ONLY
        #include "impossible_nested_sibling_define.h"
        #else
        #include "possible_nested_sibling_else.h"
        #endif
        #endif
        """

        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertFalse(metadataSource.contains("impossible_sibling_elif.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_sibling_else.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_after_sibling_defined.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_after_sibling_undefined.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("impossible_nested_sibling_define.h"), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "possible_nested_sibling_else.h""#), metadataSource)
    }

    func testShaderPreprocessorIgnoresDirectivesInsideBlockComments() throws {
        let source = """
        #define COMMENTED_FLAG 0
        /*
        #define COMMENTED_FLAG 1
        #include "commented_block.h"
        */
        #if 1 /* keep this active */
        #include "active_after_comment.h"
        #endif
        #if COMMENTED_FLAG
        #include "leaked_commented_define.h"
        #else
        #include "commented_define_ignored.h"
        #endif
        """
        let parser = WallpaperEngineShaderParser()
        let shader = WallpaperEngineResolvedShader(
            name: "commented-directives",
            vertexPath: nil,
            fragmentPath: "shaders/commented.frag",
            vertexSource: nil,
            fragmentSource: source,
            vertexMetadata: nil,
            fragmentMetadata: parser.parseShader(source: source, path: "shaders/commented.frag", stage: .fragment)
        )
        let includes = [
            "active_after_comment.h": makeShaderInclude("active_after_comment.h"),
            "commented_block.h": makeShaderInclude("commented_block.h"),
            "commented_define_ignored.h": makeShaderInclude("commented_define_ignored.h"),
            "leaked_commented_define.h": makeShaderInclude("leaked_commented_define.h")
        ]

        let prepared = WallpaperEngineShaderPreprocessor().prepare(
            shader: shader,
            usage: "test",
            materialCombos: [:],
            textureBindings: [],
            includes: includes
        )
        let metadataSource = WallpaperEngineShaderPreprocessor().sourceForMetadataParsing(
            source: source,
            stage: .fragment
        )

        XCTAssertEqual(prepared.includedPaths, ["active_after_comment.h", "commented_define_ignored.h"])
        XCTAssertTrue(prepared.fragmentSource?.contains("active_after_commentHelper") == true)
        XCTAssertTrue(prepared.fragmentSource?.contains("commented_define_ignoredHelper") == true)
        XCTAssertTrue(prepared.fragmentSource?.contains("commented_blockHelper") == false)
        XCTAssertTrue(prepared.fragmentSource?.contains("leaked_commented_defineHelper") == false)
        XCTAssertTrue(metadataSource.contains(#"#include "active_after_comment.h""#), metadataSource)
        XCTAssertTrue(metadataSource.contains(#"#include "commented_define_ignored.h""#), metadataSource)
        XCTAssertFalse(metadataSource.contains("commented_block.h"), metadataSource)
        XCTAssertFalse(metadataSource.contains("leaked_commented_define.h"), metadataSource)
    }

    func testShaderPreprocessorSharesCombosAcrossShaderStages() throws {
        let vertexSource = """
        // [COMBO] {"combo":"KERNEL","default":1}
        #if MASK
        #include "mask_vertex_branch.h"
        #endif
        void main() { gl_Position = vec4(1.0); }
        """
        let fragmentSource = """
        uniform sampler2D g_Texture0; // {"combo":"MASK","default":"util/noise"}
        #if KERNEL == 1
        #include "kernel_fragment_branch.h"
        #endif
        void main() { gl_FragColor = vec4(1.0); }
        """
        let parser = WallpaperEngineShaderParser()
        let shader = WallpaperEngineResolvedShader(
            name: "linked",
            vertexPath: "shaders/linked.vert",
            fragmentPath: "shaders/linked.frag",
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            vertexMetadata: parser.parseShader(source: vertexSource, path: "shaders/linked.vert", stage: .vertex),
            fragmentMetadata: parser.parseShader(source: fragmentSource, path: "shaders/linked.frag", stage: .fragment)
        )
        let includes = [
            "kernel_fragment_branch.h": makeShaderInclude("kernel_fragment_branch.h"),
            "mask_vertex_branch.h": makeShaderInclude("mask_vertex_branch.h")
        ]

        let prepared = WallpaperEngineShaderPreprocessor().prepare(
            shader: shader,
            usage: "test",
            materialCombos: [:],
            textureBindings: [],
            includes: includes
        )

        XCTAssertEqual(prepared.combos["KERNEL"], 1)
        XCTAssertEqual(prepared.combos["MASK"], 1)
        XCTAssertEqual(prepared.includedPaths, ["kernel_fragment_branch.h", "mask_vertex_branch.h"])
        XCTAssertTrue(prepared.vertexSource?.contains("mask_vertex_branchHelper") == true)
        XCTAssertTrue(prepared.fragmentSource?.contains("kernel_fragment_branchHelper") == true)
    }

    func testSceneParserBuildsManifestFromScenePackage() throws {
        let folderURL = try makeSceneFixture(projectInPackage: false)

        let manifest = try WallpaperEngineSceneParser().analyzeProject(in: folderURL)

        XCTAssertEqual(manifest.project.type, "scene")
        XCTAssertEqual(manifest.sceneFile, "scene.json")
        XCTAssertEqual(manifest.packageFiles.first?.filename, "scene.pkg")
        XCTAssertEqual(manifest.packageEntryExtensionCounts[".json"], 8)
        XCTAssertEqual(manifest.packageEntryExtensionCounts[".tex"], 2)
        XCTAssertEqual(manifest.objectKindCounts[.image], 1)
        XCTAssertEqual(manifest.objectKindCounts[.text], 1)
        XCTAssertEqual(manifest.objectKindCounts[.particle], 1)
        XCTAssertEqual(manifest.objectKindCounts[.sound], 1)
        XCTAssertEqual(manifest.assets.models, ["models/bg.json"])
        XCTAssertTrue(manifest.assets.materials.contains("materials/bgmat.json"))
        XCTAssertTrue(manifest.assets.materials.contains("materials/particlemat.json"))
        XCTAssertTrue(manifest.assets.effects.contains("effects/tint.json"))
        XCTAssertEqual(manifest.assets.particles, ["particles/rain.json", "particles/splash.json"])
        XCTAssertEqual(manifest.assets.textures, ["materials/bgtex.tex", "materials/util/noise.tex"])
        XCTAssertEqual(manifest.assets.inlineScriptCount, 1)
        XCTAssertEqual(manifest.textures.map(\.path), ["materials/bgtex.tex", "materials/util/noise.tex"])
        XCTAssertTrue(manifest.textureParseFailures.isEmpty)
    }

    func testSceneParserBuildsTypedDocumentForRendererInput() throws {
        let folderURL = try makeSceneFixture(projectInPackage: false)

        let document = try WallpaperEngineSceneParser().parseProject(in: folderURL)

        XCTAssertEqual(document.project.properties["rain"]?.type, "bool")
        XCTAssertEqual(document.project.properties["rain"]?.value, .bool(true))
        XCTAssertEqual(document.project.properties["music"]?.minimum, .int(0))
        XCTAssertEqual(document.project.properties["music"]?.maximum, .int(1))
        XCTAssertEqual(document.project.properties["music"]?.step, .double(0.1))
        XCTAssertEqual(document.project.properties["stickh"]?.options.compactMap(\.label), ["Stick H", "Stick V", "None"])
        XCTAssertEqual(document.general.projection.width, 1920)
        XCTAssertEqual(document.general.projection.height, 1080)
        XCTAssertEqual(document.camera.eye, .vector3(WallpaperEngineSceneVector3(x: 0, y: 0, z: 1)))

        let background = try XCTUnwrap(document.objects.first { $0.id == 1 })
        XCTAssertEqual(background.kind, .image)
        XCTAssertEqual(background.origin, nil)
        XCTAssertEqual(background.image?.modelPath, "models/bg.json")
        XCTAssertEqual(background.image?.model?.materialPath, "materials/bgmat.json")
        XCTAssertEqual(background.image?.model?.width, 1920)
        XCTAssertEqual(background.image?.model?.material?.passes.first?.shader, "genericimage")
        XCTAssertEqual(background.image?.model?.material?.passes.first?.blending, "translucent")
        XCTAssertEqual(background.image?.model?.material?.passes.first?.textures[0], "bgtex")
        XCTAssertEqual(background.image?.model?.material?.passes.first?.constants["alpha"], .double(0.5))
        XCTAssertEqual(background.image?.effects.first?.effect?.fbos.first?.name, "_rt_Test")
        XCTAssertEqual(background.image?.effects.first?.effect?.passes.first?.binds[0], "previous")
        XCTAssertEqual(background.image?.effects.first?.passOverrides.first?.constants["strength"], .int(2))

        let clock = try XCTUnwrap(document.objects.first { $0.id == 2 })
        XCTAssertEqual(clock.kind, .text)
        XCTAssertEqual(clock.text?.text, "00:00")
        XCTAssertEqual(clock.text?.script, "return '00:00';")
        XCTAssertEqual(clock.text?.fontPath, "fonts/demo.otf")

        let particle = try XCTUnwrap(document.objects.first { $0.id == 3 })
        XCTAssertEqual(particle.particle?.particlePath, "particles/rain.json")
        XCTAssertEqual(particle.particle?.definition?.materialPath, "materials/particlemat.json")
        XCTAssertEqual(particle.particle?.definition?.rendererNames, ["sprite"])
        XCTAssertEqual(particle.particle?.definition?.maxCount, 10)
        XCTAssertEqual(particle.particle?.definition?.emitters.first?.name, "point")
        XCTAssertEqual(particle.particle?.definition?.initializers.first?.rawFields["min"], .vector3(WallpaperEngineSceneVector3(x: 0, y: 1, z: 0)))
        XCTAssertEqual(particle.particle?.definition?.operators.first?.rawFields["gravity"], .vector3(WallpaperEngineSceneVector3(x: 0, y: -9.8, z: 0)))
        XCTAssertEqual(particle.particle?.definition?.controlPoints.first?.index, 0)
        XCTAssertEqual(particle.particle?.definition?.children.first?.particlePath, "particles/splash.json")

        let sound = try XCTUnwrap(document.objects.first { $0.id == 4 })
        XCTAssertEqual(sound.sound?.soundPaths, ["sounds/rain.mp3"])
    }

    func testSceneRenderPlannerBuildsRendererFacingPassPlan() throws {
        let folderURL = try makeSceneFixture(projectInPackage: false)
        let document = try WallpaperEngineSceneParser().parseProject(in: folderURL)

        let plan = WallpaperEngineSceneRenderPlanner().buildPlan(for: document)

        XCTAssertEqual(plan.canvasSize, WallpaperEngineSceneVector2(x: 1920, y: 1080))
        XCTAssertEqual(plan.clearColor, .vector3(WallpaperEngineSceneVector3(x: 0, y: 0, z: 0)))
        XCTAssertEqual(plan.objects.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(plan.resources.models, ["models/bg.json"])
        XCTAssertEqual(plan.resources.materials, [
            "materials/bgmat.json",
            "materials/particlemat.json",
            "materials/tintmat.json"
        ])
        XCTAssertEqual(plan.resources.textures, ["materials/bgtex.tex", "materials/util/noise.tex"])
        XCTAssertEqual(plan.resources.shaders, ["genericimage", "genericparticle", "tint"])
        XCTAssertEqual(plan.resources.effects, ["effects/tint.json"])
        XCTAssertEqual(plan.resources.particles, ["particles/rain.json", "particles/splash.json"])
        XCTAssertEqual(plan.resources.fonts, ["fonts/demo.otf"])
        XCTAssertEqual(plan.resources.sounds, ["sounds/rain.mp3"])
        XCTAssertEqual(plan.resources.framebuffers, ["_rt_FullFrameBuffer", "_rt_Test"])

        let background = try XCTUnwrap(plan.objects.first { $0.id == 1 })
        guard case .image(let imagePlan) = background.payload else {
            return XCTFail("Expected an image render plan.")
        }
        XCTAssertEqual(imagePlan.size, WallpaperEngineSceneVector2(x: 1920, y: 1080))
        XCTAssertEqual(imagePlan.basePasses.first?.shader, "genericimage")
        XCTAssertEqual(imagePlan.basePasses.first?.blending, "translucent")
        XCTAssertEqual(imagePlan.basePasses.first?.textures, [
            WallpaperEngineRenderTextureBinding(index: 0, reference: .asset("materials/bgtex.tex"))
        ])

        let effectPlan = try XCTUnwrap(imagePlan.effects.first)
        XCTAssertEqual(effectPlan.framebuffers.first?.name, "_rt_Test")
        XCTAssertEqual(effectPlan.passes.first?.target, .framebuffer("_rt_FullFrameBuffer"))
        XCTAssertEqual(effectPlan.passes.first?.binds, [
            WallpaperEngineRenderTextureBinding(index: 0, reference: .previous)
        ])
        XCTAssertEqual(effectPlan.passes.first?.materialPass?.shader, "tint")
        XCTAssertEqual(effectPlan.passes.first?.materialPass?.constants["strength"], .int(2))
        XCTAssertEqual(effectPlan.passes.first?.materialPass?.overrideID, 12)

        let particleObject = try XCTUnwrap(plan.objects.first { $0.id == 3 })
        guard case .particle(let particlePlan) = particleObject.payload else {
            return XCTFail("Expected a particle render plan.")
        }
        XCTAssertEqual(particlePlan.materialPasses.first?.shader, "genericparticle")
        XCTAssertEqual(particlePlan.emitters.first?.name, "point")
        XCTAssertEqual(particlePlan.children.first?.particlePath, "particles/splash.json")

        let resources = WallpaperEngineSceneResourceResolver(
            assetStore: try WallpaperEngineSceneAssetStore(folderURL: folderURL)
        ).resolve(plan: plan)
        XCTAssertEqual(resources.textures["materials/bgtex.tex"]?.imageWidth, 16)
        XCTAssertNotNil(resources.assets["materials/bgmat.json"])
        XCTAssertNotNil(resources.assets["effects/tint.json"])
        XCTAssertEqual(resources.shaders["tint"]?.vertexPath, "shaders/tint.vert")
        XCTAssertEqual(resources.shaders["tint"]?.fragmentPath, "shaders/tint.frag")
        XCTAssertTrue(resources.shaders["tint"]?.isComplete == true)
        XCTAssertEqual(resources.shaders["tint"]?.fragmentMetadata?.includes, [
            "common_blending.h",
            "optional_metadata_branch.h",
            "macro_branch.h",
            "pasted_branch.h",
            "variadic_branch.h",
            "function_alias_branch.h",
            "pasted_callee_branch.h",
            "defined_function_branch.h",
            "texture_combo_branch.h",
            "elifdef_branch.h",
            "elifndef_branch.h",
            "operator_fragment_branch.h",
            "empty_variadic_branch.h",
            "stringified_branch.h",
            "expanded_arg_branch.h",
            "combo_branch.h"
        ])
        XCTAssertEqual(resources.shaders["tint"]?.fragmentMetadata?.requires, ["LightingV1"])
        XCTAssertEqual(resources.shaders["tint"]?.fragmentMetadata?.combos.first?.name, "BLENDMODE")
        XCTAssertEqual(resources.shaders["tint"]?.fragmentMetadata?.combos.first?.defaultValue, .int(30))
        XCTAssertEqual(resources.shaders["tint"]?.fragmentMetadata?.textures.map(\.uniformName), [
            "g_Texture0",
            "g_Texture1",
            "g_Texture2"
        ])
        XCTAssertEqual(resources.shaders["tint"]?.fragmentMetadata?.textures[0].hidden, true)
        XCTAssertEqual(resources.shaders["tint"]?.fragmentMetadata?.textures[1].defaultTexture, "util/noise")
        XCTAssertEqual(resources.shaders["tint"]?.fragmentMetadata?.textures[2].metadata["combo"], .string("TEXTURE_COMBO"))
        XCTAssertEqual(resources.shaders["tint"]?.fragmentMetadata?.parameters.first?.materialName, "strength")
        XCTAssertEqual(
            resources.shaders["tint"]?.vertexMetadata?.parameters.first?.defaultValue,
            .vector2(WallpaperEngineSceneVector2(x: 1, y: 1))
        )
        XCTAssertEqual(resources.shaders["tint"]?.defaultTextures, [1: "util/noise"])
        XCTAssertEqual(resources.shaderIncludes["common_blending.h"]?.resolvedPath, "shaders/common_blending.h")
        XCTAssertEqual(resources.shaderIncludes["common_blending.h"]?.metadata.includes, ["math.h"])
        XCTAssertEqual(resources.shaderIncludes["optional_metadata_branch.h"]?.resolvedPath, "shaders/optional_metadata_branch.h")
        XCTAssertEqual(resources.shaderIncludes["pasted_branch.h"]?.resolvedPath, "shaders/pasted_branch.h")
        XCTAssertEqual(resources.shaderIncludes["variadic_branch.h"]?.resolvedPath, "shaders/variadic_branch.h")
        XCTAssertEqual(resources.shaderIncludes["function_alias_branch.h"]?.resolvedPath, "shaders/function_alias_branch.h")
        XCTAssertEqual(resources.shaderIncludes["pasted_callee_branch.h"]?.resolvedPath, "shaders/pasted_callee_branch.h")
        XCTAssertEqual(resources.shaderIncludes["defined_function_branch.h"]?.resolvedPath, "shaders/defined_function_branch.h")
        XCTAssertEqual(resources.shaderIncludes["texture_combo_branch.h"]?.resolvedPath, "shaders/texture_combo_branch.h")
        XCTAssertEqual(resources.shaderIncludes["elifdef_branch.h"]?.resolvedPath, "shaders/elifdef_branch.h")
        XCTAssertEqual(resources.shaderIncludes["elifndef_branch.h"]?.resolvedPath, "shaders/elifndef_branch.h")
        XCTAssertEqual(resources.shaderIncludes["operator_fragment_branch.h"]?.resolvedPath, "shaders/operator_fragment_branch.h")
        XCTAssertEqual(resources.shaderIncludes["empty_variadic_branch.h"]?.resolvedPath, "shaders/empty_variadic_branch.h")
        XCTAssertEqual(resources.shaderIncludes["stringified_branch.h"]?.resolvedPath, "shaders/stringified_branch.h")
        XCTAssertEqual(resources.shaderIncludes["expanded_arg_branch.h"]?.resolvedPath, "shaders/expanded_arg_branch.h")
        XCTAssertEqual(resources.shaderIncludes["combo_branch.h"]?.resolvedPath, "shaders/combo_branch.h")
        XCTAssertEqual(resources.shaderIncludes["math.h"]?.resolvedPath, "shaders/math.h")
        XCTAssertEqual(
            resources.shaderIncludes["common_blending.h"]?.metadata.parameters.first?.defaultValue,
            .double(0.5)
        )
        XCTAssertEqual(resources.textures["materials/util/noise.tex"]?.imageWidth, 16)
        let preparedTint = try XCTUnwrap(resources.preparedShaders.first { $0.shaderName == "tint" })
        XCTAssertEqual(preparedTint.usage, "object:1:image:effect:11:pass:0:material:0")
        XCTAssertEqual(preparedTint.combos["BLENDMODE"], 32)
        XCTAssertEqual(preparedTint.includedPaths, [
            "combo_branch.h",
            "common_blending.h",
            "defined_function_branch.h",
            "elifdef_branch.h",
            "elifndef_branch.h",
            "empty_variadic_branch.h",
            "expanded_arg_branch.h",
            "function_alias_branch.h",
            "macro_branch.h",
            "math.h",
            "operator_fragment_branch.h",
            "pasted_branch.h",
            "pasted_callee_branch.h",
            "stringified_branch.h",
            "texture_combo_branch.h",
            "variadic_branch.h"
        ])
        XCTAssertTrue(preparedTint.unresolvedIncludes.isEmpty)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("#define BLENDMODE 32") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("#define GLSL 1") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float helper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float comboBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float macroBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float pastedBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float pastedCalleeBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float definedFunctionBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float textureComboBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float variadicBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float functionAliasBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float elifdefBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float elifndefBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float operatorFragmentBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float emptyVariadicBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float stringifiedBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float expandedArgumentBranchHelper(float value)") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("float optionalMetadataHelper(float value)") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("vec3 PerformLighting_V1") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("#require") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("out vec4 out_FragColor;") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("out_FragColor = mix") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("vec4(0.25, 0.0, 0.0, 0.0) * 0.0") == true)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("vec4(0.0, 1.0, 1.0, 1.0)") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("vec4(1.0, 0.0, 1.0, 1.0)") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("vec4(0.5, 0.5, 0.0, 1.0)") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("vec4(0.1, 0.5, 0.0, 1.0)") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("#if") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("#elif") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("#else") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("#endif") == false)
        XCTAssertTrue(preparedTint.fragmentSource?.contains("in vec2 v_TexCoord;") == true)
        XCTAssertTrue(preparedTint.vertexSource?.contains("in vec3 a_Position;") == true)
        XCTAssertTrue(preparedTint.vertexSource?.contains("out vec2 v_TexCoord;") == true)
        XCTAssertEqual(resources.shaderBindings.count, 3)
        let baseBinding = try XCTUnwrap(resources.shaderBindings.first { $0.usage == "object:1:image:base:0" })
        XCTAssertEqual(baseBinding.shaderName, "genericimage")
        XCTAssertEqual(baseBinding.textures.first?.reference, .asset("materials/bgtex.tex"))
        XCTAssertEqual(baseBinding.textures.first?.source, .materialTexture)
        let particleBinding = try XCTUnwrap(resources.shaderBindings.first { $0.usage == "object:3:particle:material:0" })
        XCTAssertEqual(particleBinding.shaderName, "genericparticle")
        XCTAssertTrue(particleBinding.textures.isEmpty)
        let tintBinding = try XCTUnwrap(resources.shaderBindings.first { $0.usage == "object:1:image:effect:11:pass:0:material:0" })
        XCTAssertEqual(tintBinding.shaderName, "tint")
        XCTAssertEqual(tintBinding.materialPath, "materials/tintmat.json")
        XCTAssertEqual(tintBinding.overrideID, 12)
        XCTAssertEqual(tintBinding.renderState.blending, "normal")
        XCTAssertEqual(tintBinding.renderState.cullMode, "nocull")
        XCTAssertEqual(tintBinding.renderState.depthTest, "disabled")
        XCTAssertEqual(tintBinding.renderState.depthWrite, "disabled")
        XCTAssertEqual(tintBinding.combos["BLENDMODE"], 32)
        let texture0 = try XCTUnwrap(tintBinding.textures.first { $0.uniformName == "g_Texture0" })
        XCTAssertEqual(texture0.index, 0)
        XCTAssertEqual(texture0.reference, .previous)
        XCTAssertEqual(texture0.source, .effectBind)
        let texture1 = try XCTUnwrap(tintBinding.textures.first { $0.uniformName == "g_Texture1" })
        XCTAssertEqual(texture1.index, 1)
        XCTAssertEqual(texture1.reference, .asset("materials/util/noise.tex"))
        XCTAssertEqual(texture1.source, .shaderDefault)
        XCTAssertEqual(texture1.defaultTexture, "util/noise")
        let texture2 = try XCTUnwrap(tintBinding.textures.first { $0.uniformName == "g_Texture2" })
        XCTAssertEqual(texture2.index, 2)
        XCTAssertEqual(texture2.reference, .asset("materials/util/noise.tex"))
        XCTAssertEqual(texture2.source, .materialTexture)
        let strength = try XCTUnwrap(tintBinding.parameters.first { $0.uniformName == "g_Strength" })
        XCTAssertEqual(strength.value, .int(2))
        XCTAssertEqual(strength.source, .materialConstant)
        let scale = try XCTUnwrap(tintBinding.parameters.first { $0.uniformName == "g_Scale" })
        XCTAssertEqual(scale.value, .vector2(WallpaperEngineSceneVector2(x: 1, y: 1)))
        XCTAssertEqual(scale.source, .shaderDefault)
        let blendAmount = try XCTUnwrap(tintBinding.parameters.first { $0.uniformName == "g_BlendAmount" })
        XCTAssertEqual(blendAmount.value, .double(0.5))
        XCTAssertEqual(blendAmount.source, .shaderDefault)
        XCTAssertEqual(resources.metalShaders.count, 3)
        let metalTint = try XCTUnwrap(resources.metalShaders.first { $0.usage == "object:1:image:effect:11:pass:0:material:0" })
        XCTAssertEqual(metalTint.shaderName, "tint")
        XCTAssertEqual(metalTint.vertexFunctionName, "we_vertex_object_1_image_effect_11_pass_0_material_0")
        XCTAssertEqual(metalTint.fragmentFunctionName, "we_fragment_object_1_image_effect_11_pass_0_material_0")
        XCTAssertTrue(metalTint.source.contains("#include <metal_stdlib>"))
        XCTAssertTrue(metalTint.source.contains("#define BLENDMODE 32"))
        XCTAssertTrue(metalTint.source.contains("texture2d<float> g_Texture0 [[texture(0)]]"))
        XCTAssertTrue(metalTint.source.contains("sampler g_Texture0Sampler [[sampler(0)]]"))
        XCTAssertTrue(metalTint.source.contains("texture2d<float> g_Texture1 [[texture(1)]]"))
        XCTAssertTrue(metalTint.source.contains("sampler g_Texture1Sampler [[sampler(1)]]"))
        XCTAssertTrue(metalTint.source.contains("texture2d<float> g_Texture2 [[texture(2)]]"))
        XCTAssertTrue(metalTint.source.contains("sampler g_Texture2Sampler [[sampler(2)]]"))
        XCTAssertTrue(metalTint.source.contains("float2 g_Scale;"))
        XCTAssertTrue(metalTint.source.contains("float g_Strength;"))
        XCTAssertTrue(metalTint.source.contains("float g_TextureReductionScale;"))
        XCTAssertTrue(metalTint.source.contains("float4 g_Texture0Resolution;"))
        XCTAssertTrue(metalTint.source.contains("float4 g_Texture1Resolution;"))
        XCTAssertTrue(metalTint.source.contains("float4 g_Texture0Rotation;"))
        XCTAssertTrue(metalTint.source.contains("float2 g_Texture0Translation;"))
        XCTAssertTrue(metalTint.source.contains("float2 g_TexelSize;"))
        XCTAssertTrue(metalTint.source.contains("float2 g_TexelSizeHalf;"))
        let helperContextSignature = "constant WEUniforms& uniforms, texture2d<float> g_Texture0, sampler g_Texture0Sampler"
        for helperName in [
            "helper",
            "macroBranchHelper",
            "pastedBranchHelper",
            "pastedCalleeBranchHelper",
            "definedFunctionBranchHelper",
            "textureComboBranchHelper",
            "variadicBranchHelper",
            "functionAliasBranchHelper",
            "elifdefBranchHelper",
            "elifndefBranchHelper",
            "operatorFragmentBranchHelper",
            "emptyVariadicBranchHelper",
            "stringifiedBranchHelper",
            "expandedArgumentBranchHelper"
        ] {
            XCTAssertTrue(
                metalTint.source.contains("float \(helperName)(float value, \(helperContextSignature)"),
                metalTint.source
            )
        }
        XCTAssertTrue(metalTint.source.contains("float3 PerformLighting_V1"))
        XCTAssertTrue(metalTint.source.contains("out.position = float4(vertexIn.a_Position, 1.0);"), metalTint.source)
        XCTAssertTrue(metalTint.source.contains("out.v_TexCoord = vertexIn.a_TexCoord * uniforms.g_Scale;"))
        XCTAssertTrue(
            metalTint.source.contains("g_Texture0.sample(g_Texture0Sampler, stageIn.v_TexCoord + uniforms.g_TexelSize)"),
            metalTint.source
        )
        XCTAssertTrue(
            metalTint.source.contains("g_Texture1.sample(g_Texture1Sampler, stageIn.v_TexCoord * uniforms.g_Texture0Rotation.xy + uniforms.g_Texture0Translation)"),
            metalTint.source
        )
        XCTAssertTrue(
            metalTint.source.contains("g_Texture1.sample(g_Texture1Sampler, stageIn.v_TexCoord + uniforms.g_TexelSizeHalf, level(0.0))"),
            metalTint.source
        )
        XCTAssertTrue(
            metalTint.source.contains("uniforms.g_Texture0Resolution.x / max(uniforms.g_Texture1Resolution.x, 1.0)"),
            metalTint.source
        )
        XCTAssertTrue(metalTint.source.contains("uniforms.g_TextureReductionScale * 0.0"), metalTint.source)
        XCTAssertTrue(metalTint.source.contains("uniforms.g_Texture0Rotation.x * 0.0"), metalTint.source)
        XCTAssertTrue(metalTint.source.contains("uniforms.g_Texture0Translation.y * 0.0"), metalTint.source)
        XCTAssertTrue(metalTint.source.contains("uniforms.g_TexelSize.x * 0.0"), metalTint.source)
        XCTAssertTrue(metalTint.source.contains("uniforms.g_TexelSizeHalf.y * 0.0"), metalTint.source)
        XCTAssertTrue(metalTint.source.contains("float4(0.25, 0.0, 0.0, 0.0) * 0.0"), metalTint.source)
        XCTAssertFalse(metalTint.source.contains("float4(0.0, 1.0, 1.0, 1.0)"), metalTint.source)
        XCTAssertFalse(metalTint.source.contains("float4(1.0, 0.0, 1.0, 1.0)"), metalTint.source)
        XCTAssertTrue(
            metalTint.source.contains("uniforms.g_Strength * helper(uniforms.g_BlendAmount, uniforms, g_Texture0, g_Texture0Sampler"),
            metalTint.source
        )
        XCTAssertTrue(metalTint.source.contains("mix("))
        XCTAssertTrue(metalTint.source.contains("stageIn.v_TexCoord"), metalTint.source)
        XCTAssertEqual(metalTint.builtinUniforms, [
            WallpaperEngineMetalBuiltinUniform(
                uniformName: "g_TextureReductionScale",
                valueType: "float",
                textureIndex: nil,
                kind: .textureReductionScale
            ),
                WallpaperEngineMetalBuiltinUniform(
                    uniformName: "g_Texture0Resolution",
                    valueType: "vec4",
                    textureIndex: 0,
                    kind: .textureResolution
                ),
                WallpaperEngineMetalBuiltinUniform(
                    uniformName: "g_Texture1Resolution",
                    valueType: "vec4",
                    textureIndex: 1,
                    kind: .textureResolution
                ),
            WallpaperEngineMetalBuiltinUniform(
                uniformName: "g_Texture0Rotation",
                valueType: "vec4",
                textureIndex: 0,
                kind: .textureRotation
            ),
            WallpaperEngineMetalBuiltinUniform(
                uniformName: "g_Texture0Translation",
                valueType: "vec2",
                textureIndex: 0,
                kind: .textureTranslation
            ),
            WallpaperEngineMetalBuiltinUniform(
                uniformName: "g_TexelSize",
                valueType: "vec2",
                textureIndex: nil,
                kind: .texelSize
            ),
            WallpaperEngineMetalBuiltinUniform(
                uniformName: "g_TexelSizeHalf",
                valueType: "vec2",
                textureIndex: nil,
                kind: .texelSizeHalf
            )
        ])
        XCTAssertTrue(metalTint.diagnostics.isEmpty, metalTint.diagnostics.joined(separator: "\n"))
#if canImport(Metal)
        if let device = MTLCreateSystemDefaultDevice() {
            let library = try device.makeLibrary(source: metalTint.source, options: nil)
            XCTAssertNotNil(library.makeFunction(name: metalTint.vertexFunctionName))
            XCTAssertNotNil(library.makeFunction(name: metalTint.fragmentFunctionName))
            let compiledResources = try WallpaperEngineMetalResourceCompiler(device: device)
                .compile(resources: resources)
            XCTAssertEqual(compiledResources.sourceTextures.keys.sorted(), [
                "asset:materials/bgtex.tex",
                "asset:materials/util/noise.tex"
            ])
            XCTAssertEqual(compiledResources.sourceSamplerStates.keys.sorted(), [
                "asset:materials/bgtex.tex",
                "asset:materials/util/noise.tex"
            ])
            XCTAssertEqual(compiledResources.sourceTextures["asset:materials/bgtex.tex"]?.width, 16)
            XCTAssertEqual(compiledResources.sourceTextures["asset:materials/bgtex.tex"]?.height, 8)
            XCTAssertEqual(compiledResources.renderTargetTextures.keys.sorted(), [
                "framebuffer:_rt_FullFrameBuffer",
                "framebuffer:_rt_Test",
                "object:1:main",
                "object:1:sub"
            ])
            XCTAssertNotNil(compiledResources.shaderLibraries["object:1:image:effect:11:pass:0:material:0"])
            XCTAssertEqual(compiledResources.pipelineStates.keys.sorted(), [
                "pipeline:object:1:image:base:0",
                "pipeline:object:1:image:effect:11:pass:0:material:0",
                "pipeline:object:3:particle:material:0"
            ])
            XCTAssertNotNil(compiledResources.depthStencilStates["pipeline:object:1:image:effect:11:pass:0:material:0"])
            XCTAssertTrue(compiledResources.diagnostics.isEmpty, compiledResources.diagnostics.joined(separator: "\n"))
            let execution = try WallpaperEngineMetalDrawExecutor(device: device).render(
                plan: resources.metalRenderPlan,
                compiledScene: compiledResources
            )
            XCTAssertEqual(execution.encodedDrawIDs, [
                "object:1:image:base:0",
                "object:1:image:effect:11:pass:0:material:0",
                "object:3:particle:material:0"
            ])
            XCTAssertTrue(execution.skippedDrawIDs.isEmpty)
            XCTAssertTrue(execution.diagnostics.isEmpty, execution.diagnostics.joined(separator: "\n"))
        }
#endif
        XCTAssertEqual(resources.metalRenderPlan.textures.map(\.key), [
            "asset:materials/bgtex.tex",
            "asset:materials/util/noise.tex"
        ])
        XCTAssertEqual(resources.metalRenderPlan.textures.first?.pixelFormat, .r8Unorm)
        XCTAssertEqual(resources.metalRenderPlan.textures.first?.sampler.minFilter, .linear)
        XCTAssertEqual(resources.metalRenderPlan.textures.first?.sampler.magFilter, .linear)
        XCTAssertEqual(resources.metalRenderPlan.textures.first?.sampler.mipFilter, .notMipmapped)
        XCTAssertEqual(resources.metalRenderPlan.textures.first?.sampler.addressModeU, .clampToEdge)
        XCTAssertEqual(resources.metalRenderPlan.textures.first?.sampler.addressModeV, .clampToEdge)
        XCTAssertEqual(resources.metalRenderPlan.framebuffers.map(\.key), [
            "framebuffer:_rt_FullFrameBuffer",
            "framebuffer:_rt_Test",
            "object:1:main",
            "object:1:sub"
        ])
        let sceneFramebuffer = try XCTUnwrap(
            resources.metalRenderPlan.framebuffers.first { $0.key == "framebuffer:_rt_FullFrameBuffer" }
        )
        XCTAssertEqual(sceneFramebuffer.role, .scene)
        XCTAssertEqual(sceneFramebuffer.width, 1920)
        XCTAssertEqual(sceneFramebuffer.height, 1080)
        XCTAssertEqual(sceneFramebuffer.pixelFormat, .rgba8Unorm)
        let effectFramebuffer = try XCTUnwrap(
            resources.metalRenderPlan.framebuffers.first { $0.key == "framebuffer:_rt_Test" }
        )
        XCTAssertEqual(effectFramebuffer.role, .effect)
        XCTAssertEqual(effectFramebuffer.width, 960)
        XCTAssertEqual(effectFramebuffer.height, 540)
        XCTAssertEqual(resources.metalRenderPlan.pipelines.count, 3)
        let tintPipeline = try XCTUnwrap(
            resources.metalRenderPlan.pipelines.first { $0.usage == "object:1:image:effect:11:pass:0:material:0" }
        )
        XCTAssertEqual(tintPipeline.id, "pipeline:object:1:image:effect:11:pass:0:material:0")
        XCTAssertEqual(tintPipeline.colorPixelFormat, .rgba8Unorm)
        XCTAssertEqual(tintPipeline.blend.sourceRGBFactor, .one)
        XCTAssertEqual(tintPipeline.blend.destinationRGBFactor, .zero)
        XCTAssertEqual(tintPipeline.depthStencil.depthCompareFunction, .always)
        XCTAssertEqual(tintPipeline.depthStencil.isDepthWriteEnabled, false)
        XCTAssertEqual(tintPipeline.cullMode, .none)
        XCTAssertTrue(tintPipeline.diagnostics.isEmpty, tintPipeline.diagnostics.joined(separator: "\n"))
        let tintDraw = try XCTUnwrap(
            resources.metalRenderPlan.draws.first { $0.id == "object:1:image:effect:11:pass:0:material:0" }
        )
        XCTAssertEqual(tintDraw.targetTextureKey, "framebuffer:_rt_FullFrameBuffer")
        XCTAssertEqual(tintDraw.pipelineID, "pipeline:object:1:image:effect:11:pass:0:material:0")
        XCTAssertEqual(tintDraw.textureArguments.map(\.textureKey), [
            "object:1:main",
            "asset:materials/util/noise.tex",
            "asset:materials/util/noise.tex"
        ])
        XCTAssertEqual(tintDraw.uniformArguments.map(\.uniformName).sorted(), [
            "g_BlendAmount",
            "g_Scale",
            "g_Strength",
            "g_TexelSize",
            "g_TexelSizeHalf",
            "g_Texture0Resolution",
            "g_Texture0Rotation",
            "g_Texture0Translation",
            "g_Texture1Resolution",
            "g_TextureReductionScale"
        ])
        let textureReductionScale = try XCTUnwrap(
            tintDraw.uniformArguments.first { $0.uniformName == "g_TextureReductionScale" }
        )
        XCTAssertEqual(textureReductionScale.source, .textureReductionScale)
        XCTAssertEqual(textureReductionScale.value, .double(1))
        let texture0Resolution = try XCTUnwrap(
            tintDraw.uniformArguments.first { $0.uniformName == "g_Texture0Resolution" }
        )
        XCTAssertEqual(texture0Resolution.source, .textureResolution)
        XCTAssertEqual(
            texture0Resolution.value,
            .vector4(WallpaperEngineSceneVector4(x: 1920, y: 1080, z: 1920, w: 1080))
        )
        let texture1Resolution = try XCTUnwrap(
            tintDraw.uniformArguments.first { $0.uniformName == "g_Texture1Resolution" }
        )
        XCTAssertEqual(texture1Resolution.source, .textureResolution)
        XCTAssertEqual(
            texture1Resolution.value,
            .vector4(WallpaperEngineSceneVector4(x: 16, y: 8, z: 16, w: 8))
        )
        let texture0Rotation = try XCTUnwrap(
            tintDraw.uniformArguments.first { $0.uniformName == "g_Texture0Rotation" }
        )
        XCTAssertEqual(texture0Rotation.source, .textureTransform)
        XCTAssertEqual(
            texture0Rotation.value,
            .vector4(WallpaperEngineSceneVector4(x: 0, y: 0, z: 0, w: 0))
        )
        let texture0Translation = try XCTUnwrap(
            tintDraw.uniformArguments.first { $0.uniformName == "g_Texture0Translation" }
        )
        XCTAssertEqual(texture0Translation.source, .textureTransform)
        XCTAssertEqual(
            texture0Translation.value,
            .vector2(WallpaperEngineSceneVector2(x: 0, y: 0))
        )
        let texelSize = try XCTUnwrap(
            tintDraw.uniformArguments.first { $0.uniformName == "g_TexelSize" }
        )
        XCTAssertEqual(texelSize.source, .texelSize)
        XCTAssertEqual(
            texelSize.value,
            .vector2(WallpaperEngineSceneVector2(x: 1.0 / 1920.0, y: 1.0 / 1080.0))
        )
        let texelSizeHalf = try XCTUnwrap(
            tintDraw.uniformArguments.first { $0.uniformName == "g_TexelSizeHalf" }
        )
        XCTAssertEqual(texelSizeHalf.source, .texelSizeHalf)
        XCTAssertEqual(
            texelSizeHalf.value,
            .vector2(WallpaperEngineSceneVector2(x: 0.5 / 1920.0, y: 0.5 / 1080.0))
        )
        XCTAssertTrue(tintDraw.diagnostics.isEmpty, tintDraw.diagnostics.joined(separator: "\n"))
        let baseDraw = try XCTUnwrap(
            resources.metalRenderPlan.draws.first { $0.id == "object:1:image:base:0" }
        )
        XCTAssertEqual(baseDraw.pipelineID, "pipeline:object:1:image:base:0")
        XCTAssertEqual(baseDraw.targetTextureKey, "object:1:main")
        XCTAssertEqual(baseDraw.textureArguments.map(\.textureKey), ["asset:materials/bgtex.tex"])
        XCTAssertTrue(baseDraw.diagnostics.isEmpty, baseDraw.diagnostics.joined(separator: "\n"))
        let particleDraw = try XCTUnwrap(
            resources.metalRenderPlan.draws.first { $0.id == "object:3:particle:material:0" }
        )
        XCTAssertEqual(particleDraw.pipelineID, "pipeline:object:3:particle:material:0")
        XCTAssertTrue(particleDraw.diagnostics.isEmpty, particleDraw.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(resources.renderCommandPlan.sceneFramebuffer, "_rt_FullFrameBuffer")
        XCTAssertEqual(resources.renderCommandPlan.objectFramebuffers, [
            WallpaperEngineObjectFramebuffer(
                objectID: 1,
                slot: .main,
                size: WallpaperEngineSceneVector2(x: 1920, y: 1080)
            ),
            WallpaperEngineObjectFramebuffer(
                objectID: 1,
                slot: .sub,
                size: WallpaperEngineSceneVector2(x: 1920, y: 1080)
            )
        ])
        XCTAssertEqual(resources.renderCommandPlan.commands.map(\.usage), [
            "object:1:image:base:0",
            "object:1:image:effect:11:pass:0:material:0",
            "object:3:particle:material:0"
        ])
        let baseCommand = try XCTUnwrap(resources.renderCommandPlan.commands.first)
        XCTAssertEqual(baseCommand.kind, .drawImageBase)
        XCTAssertEqual(baseCommand.target, .objectFramebuffer(objectID: 1, slot: .main))
        XCTAssertEqual(baseCommand.input, .asset("materials/bgtex.tex"))
        XCTAssertEqual(baseCommand.previousInput, nil)
        XCTAssertEqual(baseCommand.shaderBinding?.usage, "object:1:image:base:0")
        let effectCommand = try XCTUnwrap(resources.renderCommandPlan.commands.dropFirst().first)
        XCTAssertEqual(effectCommand.kind, .drawImageEffect)
        XCTAssertEqual(effectCommand.effectID, 11)
        XCTAssertEqual(effectCommand.effectPassIndex, 0)
        XCTAssertEqual(effectCommand.materialPassIndex, 0)
        XCTAssertEqual(effectCommand.target, .framebuffer("_rt_FullFrameBuffer"))
        XCTAssertEqual(effectCommand.input, .objectFramebuffer(objectID: 1, slot: .main))
        XCTAssertEqual(effectCommand.previousInput, .objectFramebuffer(objectID: 1, slot: .main))
        XCTAssertEqual(effectCommand.shaderBinding?.usage, "object:1:image:effect:11:pass:0:material:0")
        let particleCommand = try XCTUnwrap(resources.renderCommandPlan.commands.last)
        XCTAssertEqual(particleCommand.kind, .drawParticle)
        XCTAssertEqual(particleCommand.target, .framebuffer("_rt_FullFrameBuffer"))
        XCTAssertTrue(resources.unresolvedShaders.isEmpty)
        XCTAssertTrue(resources.unresolvedShaderIncludes.isEmpty)
        XCTAssertTrue(resources.missingAssets.isEmpty)
        XCTAssertTrue(resources.textureParseFailures.isEmpty)
    }

    func testSceneParserCanReadProjectJsonFromPackageOnlyFolder() throws {
        let folderURL = try makeSceneFixture(projectInPackage: true)

        let manifest = try WallpaperEngineSceneParser().analyzeProject(in: folderURL)

        XCTAssertEqual(manifest.project.title, "Native Scene")
        XCTAssertEqual(manifest.sceneFile, "scene.json")
        XCTAssertEqual(manifest.objects.count, 4)
    }

    func testSceneResourceResolverFallsBackToBuiltinShaderIncludes() throws {
        let folderURL = try makeTemporaryDirectory()
        let project = Data("""
        {"title":"Builtins","type":"scene","file":"scene.json"}
        """.utf8)
        try project.write(to: folderURL.appendingPathComponent("project.json"))
        try makePackageData(files: [
            (
                "scene.json",
                Data(#"{"general":{"orthogonalprojection":{"width":16,"height":16}},"camera":{"center":"0 0 0","eye":"0 0 1","up":"0 1 0"},"objects":[{"id":1,"image":"models/builtin.json"}]}"#.utf8)
            ),
            ("models/builtin.json", Data(#"{"material":"materials/builtinmat.json","width":16,"height":16}"#.utf8)),
            ("materials/builtinmat.json", Data(#"{"passes":[{"shader":"builtin","textures":["bgtex"]}]}"#.utf8)),
            ("shaders/builtin.vert", Data("""
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() { v_TexCoord = a_TexCoord; gl_Position = vec4(a_Position, 1.0); }
            """.utf8)),
            ("shaders/builtin.frag", Data("""
            #include "common.h"
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0; // {"hidden":true}
            void main() { gl_FragColor = vec4(rotateVec2(v_TexCoord, 0.0), M_PI * 0.0, 1.0); }
            """.utf8)),
            ("materials/bgtex.tex", makeTextureData(flags: 2))
        ]).write(to: folderURL.appendingPathComponent("scene.pkg"))

        let document = try WallpaperEngineSceneParser().parseProject(in: folderURL)
        let plan = WallpaperEngineSceneRenderPlanner().buildPlan(for: document)
        let resources = WallpaperEngineSceneResourceResolver(
            assetStore: try WallpaperEngineSceneAssetStore(folderURL: folderURL)
        ).resolve(plan: plan)

        XCTAssertTrue(resources.unresolvedShaderIncludes.isEmpty)
        XCTAssertEqual(resources.shaderIncludes["common.h"]?.resolvedPath, "builtin/common.h")
        XCTAssertTrue(resources.shaderIncludes["common.h"]?.source.contains("rotateVec2") == true)

        let prepared = try XCTUnwrap(resources.preparedShaders.first)
        XCTAssertTrue(prepared.unresolvedIncludes.isEmpty)
        XCTAssertEqual(prepared.includedPaths, ["common.h"])
        XCTAssertTrue(prepared.fragmentSource?.contains("#define M_PI") == true)
        XCTAssertTrue(prepared.fragmentSource?.contains("rotateVec2") == true)

        let metal = try XCTUnwrap(resources.metalShaders.first)
        XCTAssertTrue(metal.source.contains("constant float M_PI"))
        XCTAssertTrue(metal.source.contains("float2 rotateVec2"))
#if canImport(Metal)
        if let device = MTLCreateSystemDefaultDevice() {
            let library = try device.makeLibrary(source: metal.source, options: nil)
            XCTAssertNotNil(library.makeFunction(name: metal.vertexFunctionName))
            XCTAssertNotNil(library.makeFunction(name: metal.fragmentFunctionName))
        }
#endif
    }

    func testBuiltinShaderLibraryCoversObservedSharedIncludes() {
        let library = WallpaperEngineBuiltinShaderLibrary()

        XCTAssertEqual(library.includeSource(for: "common")?.resolvedPath, "builtin/common.h")
        XCTAssertEqual(library.includeSource(for: "common_blending.h")?.resolvedPath, "builtin/common_blending.h")
        XCTAssertEqual(library.includeSource(for: "shaders/common_blur.h")?.resolvedPath, "builtin/common_blur.h")
        XCTAssertEqual(library.includeSource(for: "common_composite.h")?.resolvedPath, "builtin/common_composite.h")
        XCTAssertNil(library.includeSource(for: "unknown_common.h"))
    }

    func testSceneResourceResolverFallsBackToBuiltinGenericImageShader() throws {
        let folderURL = try makeTemporaryDirectory()
        let project = Data("""
        {"title":"Generic Image","type":"scene","file":"scene.json"}
        """.utf8)
        try project.write(to: folderURL.appendingPathComponent("project.json"))
        try makePackageData(files: [
            (
                "scene.json",
                Data(#"{"general":{"orthogonalprojection":{"width":16,"height":16}},"camera":{"center":"0 0 0","eye":"0 0 1","up":"0 1 0"},"objects":[{"id":1,"image":"models/image.json"}]}"#.utf8)
            ),
            ("models/image.json", Data(#"{"material":"materials/image.json","width":16,"height":16}"#.utf8)),
            ("materials/image.json", Data(#"{"passes":[{"shader":"genericimage4","textures":["image"]}]}"#.utf8)),
            ("materials/image.tex", makeTextureData(flags: 2))
        ]).write(to: folderURL.appendingPathComponent("scene.pkg"))

        let document = try WallpaperEngineSceneParser().parseProject(in: folderURL)
        let plan = WallpaperEngineSceneRenderPlanner().buildPlan(for: document)
        let resources = WallpaperEngineSceneResourceResolver(
            assetStore: try WallpaperEngineSceneAssetStore(folderURL: folderURL)
        ).resolve(plan: plan)

        XCTAssertTrue(resources.unresolvedShaders.isEmpty)
        XCTAssertEqual(resources.shaders["genericimage4"]?.vertexPath, "builtin/shaders/genericimage4.vert")
        XCTAssertEqual(resources.shaders["genericimage4"]?.fragmentPath, "builtin/shaders/genericimage4.frag")
        XCTAssertEqual(resources.metalShaders.first?.shaderName, "genericimage4")
        XCTAssertTrue(resources.metalShaders.first?.diagnostics.isEmpty == true)
    }

    func testSceneResourceResolverFallsBackToBuiltinGenericParticleShader() throws {
        let folderURL = try makeTemporaryDirectory()
        let project = Data("""
        {"title":"Generic Particle","type":"scene","file":"scene.json"}
        """.utf8)
        try project.write(to: folderURL.appendingPathComponent("project.json"))
        try makePackageData(files: [
            (
                "scene.json",
                Data(#"{"general":{"orthogonalprojection":{"width":16,"height":16}},"camera":{"center":"0 0 0","eye":"0 0 1","up":"0 1 0"},"objects":[{"id":1,"particle":"particles/spark.json"}]}"#.utf8)
            ),
            ("particles/spark.json", Data(#"{"material":"materials/particle.json","maxcount":4,"renderer":[{"name":"sprite"}]}"#.utf8)),
            ("materials/particle.json", Data(#"{"passes":[{"shader":"genericparticle"}]}"#.utf8))
        ]).write(to: folderURL.appendingPathComponent("scene.pkg"))

        let document = try WallpaperEngineSceneParser().parseProject(in: folderURL)
        let plan = WallpaperEngineSceneRenderPlanner().buildPlan(for: document)
        let resources = WallpaperEngineSceneResourceResolver(
            assetStore: try WallpaperEngineSceneAssetStore(folderURL: folderURL)
        ).resolve(plan: plan)

        XCTAssertTrue(resources.unresolvedShaders.isEmpty)
        XCTAssertEqual(resources.shaders["genericparticle"]?.vertexPath, "builtin/shaders/genericparticle.vert")
        XCTAssertEqual(resources.shaders["genericparticle"]?.fragmentPath, "builtin/shaders/genericparticle.frag")
        XCTAssertEqual(resources.preparedShaders.first?.shaderName, "genericparticle")
        XCTAssertEqual(resources.metalShaders.first?.shaderName, "genericparticle")
        XCTAssertTrue(resources.metalShaders.first?.diagnostics.isEmpty == true)
        XCTAssertEqual(resources.metalRenderPlan.pipelines.first?.id, "pipeline:object:1:particle:material:0")
        XCTAssertEqual(resources.metalRenderPlan.draws.first?.pipelineID, "pipeline:object:1:particle:material:0")
    }

    func testMetalShaderTranslatorProvidesModelViewProjectionBuiltin() throws {
        let folderURL = try makeTemporaryDirectory()
        let project = Data("""
        {"title":"MVP","type":"scene","file":"scene.json"}
        """.utf8)
        try project.write(to: folderURL.appendingPathComponent("project.json"))
        try makePackageData(files: [
            (
                "scene.json",
                Data(#"{"general":{"orthogonalprojection":{"width":16,"height":16}},"camera":{"center":"0 0 0","eye":"0 0 1","up":"0 1 0"},"objects":[{"id":1,"image":"models/mvp.json"}]}"#.utf8)
            ),
            ("models/mvp.json", Data(#"{"material":"materials/mvp.json","width":16,"height":16}"#.utf8)),
            ("materials/mvp.json", Data(#"{"passes":[{"shader":"mvp","textures":["mvp"]}]}"#.utf8)),
            ("shaders/mvp.vert", Data("""
            uniform mat4 g_ModelViewProjectionMatrix;
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() { v_TexCoord = a_TexCoord; gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix); }
            """.utf8)),
            ("shaders/mvp.frag", Data("""
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0; // {"hidden":true}
            void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
            """.utf8)),
            ("materials/mvp.tex", makeTextureData(flags: 2))
        ]).write(to: folderURL.appendingPathComponent("scene.pkg"))

        let document = try WallpaperEngineSceneParser().parseProject(in: folderURL)
        let plan = WallpaperEngineSceneRenderPlanner().buildPlan(for: document)
        let resources = WallpaperEngineSceneResourceResolver(
            assetStore: try WallpaperEngineSceneAssetStore(folderURL: folderURL)
        ).resolve(plan: plan)

        let metal = try XCTUnwrap(resources.metalShaders.first)
        XCTAssertTrue(metal.source.contains("float4x4 g_ModelViewProjectionMatrix;"), metal.source)
        XCTAssertTrue(
            metal.source.contains("uniforms.g_ModelViewProjectionMatrix * float4(vertexIn.a_Position, 1.0)"),
            metal.source
        )
        let draw = try XCTUnwrap(resources.metalRenderPlan.draws.first)
        XCTAssertEqual(draw.uniformArguments.first?.uniformName, "g_ModelViewProjectionMatrix")
        XCTAssertEqual(draw.uniformArguments.first?.source, .modelViewProjectionMatrix)
#if canImport(Metal)
        if let device = MTLCreateSystemDefaultDevice() {
            let library = try device.makeLibrary(source: metal.source, options: nil)
            XCTAssertNotNil(library.makeFunction(name: metal.vertexFunctionName))
            XCTAssertNotNil(library.makeFunction(name: metal.fragmentFunctionName))
        }
#endif
    }

    func testMetalShaderTranslatorKeepsMainBodyLocalsAndFlattensVaryingArrays() throws {
        let folderURL = try makeTemporaryDirectory()
        let project = Data("""
        {"title":"Array Varying","type":"scene","file":"scene.json"}
        """.utf8)
        try project.write(to: folderURL.appendingPathComponent("project.json"))
        try makePackageData(files: [
            (
                "scene.json",
                Data(#"{"general":{"orthogonalprojection":{"width":16,"height":16}},"camera":{"center":"0 0 0","eye":"0 0 1","up":"0 1 0"},"objects":[{"id":1,"image":"models/array.json"}]}"#.utf8)
            ),
            ("models/array.json", Data(#"{"material":"materials/array.json","width":16,"height":16}"#.utf8)),
            ("materials/array.json", Data(#"{"passes":[{"shader":"array","textures":["array"]}]}"#.utf8)),
            ("shaders/array.vert", Data("""
            uniform float g_Time;
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord[2];
            void main() {
                gl_Position = vec4(a_Position, 1.0);
                vec2 offsets = vec2(g_Time);
                v_TexCoord[0] = a_TexCoord;
                v_TexCoord[1] = a_TexCoord + offsets * 0.0;
            }
            """.utf8)),
            ("shaders/array.frag", Data("""
            varying vec2 v_TexCoord[2];
            uniform sampler2D g_Texture0; // {"hidden":true}
            void main() {
                vec4 albedo = texSample2D(g_Texture0, v_TexCoord[0]);
                for (int i = 0; i < 2; ++i) {
                    albedo += texSample2D(g_Texture0, v_TexCoord[i]) * 0.0;
                }
                gl_FragColor.rgb = albedo.rgb;
                gl_FragColor.a = albedo.a;
            }
            """.utf8)),
            ("materials/array.tex", makeTextureData(flags: 2))
        ]).write(to: folderURL.appendingPathComponent("scene.pkg"))

        let document = try WallpaperEngineSceneParser().parseProject(in: folderURL)
        let plan = WallpaperEngineSceneRenderPlanner().buildPlan(for: document)
        let resources = WallpaperEngineSceneResourceResolver(
            assetStore: try WallpaperEngineSceneAssetStore(folderURL: folderURL)
        ).resolve(plan: plan)

        let metal = try XCTUnwrap(resources.metalShaders.first)
        XCTAssertTrue(metal.source.contains("float g_Time;"), metal.source)
        XCTAssertTrue(metal.source.contains("float2 v_TexCoord_0;"), metal.source)
        XCTAssertTrue(metal.source.contains("float2 v_TexCoord_1;"), metal.source)
        XCTAssertTrue(metal.source.contains("out.v_TexCoord_1 = vertexIn.a_TexCoord + offsets * 0.0;"), metal.source)
        XCTAssertTrue(metal.source.contains("float2 v_TexCoord[2] = { stageIn.v_TexCoord_0, stageIn.v_TexCoord_1 };"), metal.source)
        XCTAssertTrue(metal.source.contains("float4 albedo = g_Texture0.sample(g_Texture0Sampler, stageIn.v_TexCoord_0);"), metal.source)
        XCTAssertTrue(metal.source.contains("g_Texture0.sample(g_Texture0Sampler, v_TexCoord[i])"), metal.source)
        XCTAssertTrue(metal.source.contains("return out_FragColor;"), metal.source)
        let draw = try XCTUnwrap(resources.metalRenderPlan.draws.first)
        let timeUniform = try XCTUnwrap(draw.uniformArguments.first { $0.uniformName == "g_Time" })
        XCTAssertEqual(timeUniform.source, .time)
        XCTAssertEqual(timeUniform.value, .double(0))
#if canImport(Metal)
        if let device = MTLCreateSystemDefaultDevice() {
            let library = try device.makeLibrary(source: metal.source, options: nil)
            XCTAssertNotNil(library.makeFunction(name: metal.vertexFunctionName))
            XCTAssertNotNil(library.makeFunction(name: metal.fragmentFunctionName))
        }
#endif
    }

    func testImporterClassifiesScenePackageBeforeCheckingSceneFileOnDisk() throws {
        let parentURL = try makeTemporaryDirectory()
        let folderURL = parentURL.appendingPathComponent("12345", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let project = Data("""
        {"title":"Scene","type":"scene","file":"scene.json"}
        """.utf8)
        try project.write(to: folderURL.appendingPathComponent("project.json"))
        try makePackageData(files: [
            ("scene.json", Data(#"{"general":{"orthogonalprojection":{"width":16,"height":16}},"camera":{"center":"0 0 0","eye":"0 0 1","up":"0 1 0"},"objects":[]}"#.utf8))
        ]).write(to: folderURL.appendingPathComponent("scene.pkg"))

        do {
            _ = try WallpaperEngineImporter().importWorkshopItem(id: "12345", folderURL: folderURL)
            XCTFail("Scene projects should remain unsupported until a renderer is available.")
        } catch WallpaperEngineImportError.unsupportedWallpaperType(let type) {
            XCTAssertEqual(type, "scene")
        } catch {
            XCTFail("Expected unsupported scene classification, got \(error)")
        }
    }

    private func makeSceneFixture(projectInPackage: Bool) throws -> URL {
        let folderURL = try makeTemporaryDirectory()
        let project = Data("""
        {
          "title": "Native Scene",
          "type": "scene",
          "file": "scene.json",
          "preview": "preview.gif",
          "workshopid": "12345",
          "general": {
            "properties": {
              "rain": { "type": "bool", "text": "Rain", "value": true, "index": 1, "order": 101 },
              "music": { "type": "slider", "text": "Music", "value": 0.4, "min": 0, "max": 1, "step": 0.1, "precision": 2, "fraction": true },
              "stickh": {
                "type": "combo",
                "text": "Stick H",
                "value": "1",
                "options": [
                  { "label": "Stick H", "value": "0" },
                  { "label": "Stick V", "value": "1" },
                  { "label": "None", "value": "2" }
                ]
              }
            }
          }
        }
        """.utf8)

        if !projectInPackage {
            try project.write(to: folderURL.appendingPathComponent("project.json"))
        }

        var packageFiles: [(String, Data)] = [
            ("scene.json", Data(sceneJSON.utf8)),
            ("models/bg.json", Data(#"{"material":"materials/bgmat.json","width":1920,"height":1080}"#.utf8)),
            ("materials/bgmat.json", Data(#"{"passes":[{"shader":"genericimage","textures":["bgtex"],"constantshadervalues":{"alpha":0.5},"blending":"translucent"}]}"#.utf8)),
            ("effects/tint.json", Data(#"{"fbos":[{"name":"_rt_Test","scale":0.5,"unique":true}],"passes":[{"material":"materials/tintmat.json","target":"_rt_FullFrameBuffer","bind":[{"index":0,"name":"previous"}]}]}"#.utf8)),
            ("materials/tintmat.json", Data(#"{"passes":[{"shader":"tint","combos":{"BLENDMODE":32},"textures":[null,null,"util/noise"]}]}"#.utf8)),
            ("shaders/genericimage.vert", Data("""
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() { v_TexCoord = a_TexCoord; }
            """.utf8)),
            ("shaders/genericimage.frag", Data("""
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0; // {"hidden":true}
            void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
            """.utf8)),
            ("shaders/tint.vert", Data("""
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            uniform vec2 g_Scale; // {"material":"scale","default":"1 1"}
            void main() { v_TexCoord = a_TexCoord * g_Scale; gl_Position = vec4(a_Position, 1.0); }
            """.utf8)),
            ("shaders/tint.frag", Data("""
            // [COMBO] {"material":"ui_editor_properties_blend_mode","combo":"BLENDMODE","type":"imageblending","default":30}
            #include <common_blending.h>
            #require LightingV1
            varying vec2 v_TexCoord;
            uniform sampler2D g_Texture0; // {"hidden":true}
            uniform sampler2D g_Texture1; // {"label":"Mask","mode":"opacitymask","combo":"MASK","default":"util/noise"}
            uniform sampler2D g_Texture2; // {"label":"Explicit Mask","mode":"opacitymask","combo":"TEXTURE_COMBO"}
            uniform float g_Strength; // {"material":"strength","label":"Strength","default":1,"range":[0,2]}
            #define DEFERRED_TINT_BRANCH ENABLE_TINT_BRANCH
            #define DEFERRED_MASK_BITS LATE_MASK_BITS
            #define FUNCTION_STYLE(value) value
            #define HAS_MASK(value, bit) (((value) & (bit)) == (bit))
            #define HAS_DEFERRED_MASK(value) HAS_MASK(value, 0x4)
            #define HAS_MASK_ALIAS HAS_MASK
            #define IS_DEFINED(name) defined(name)
            #define MACRO_BRANCH_INCLUDE "macro_branch.h"
            #define BRANCH_ENABLED 1
            #define JOIN_TOKENS(left, right) left ## right
            #define HAS_VARIADIC_MASK(value, ...) (((value) & (__VA_ARGS__)) != 0)
            #define OPTIONAL_ARG_COUNT(...) OPTIONAL_ARG_COUNT_IMPL(0, ## __VA_ARGS__, 1, 0)
            #define OPTIONAL_ARG_COUNT_IMPL(_0, _1, count, ...) count
            #define STRINGIFY_INCLUDE(name) #name
            #define INCLUDE_WRAPPER(path) STRINGIFY_INCLUDE(path)
            #define EXPANDED_ARG_BRANCH_FILE expanded_arg_branch.h
            #define OPERATOR_FRAGMENT_BRANCH || ENABLE_TINT_BRANCH
            #define ENABLE_TINT_BRANCH 1
            #define LATE_MASK_BITS COMBO_MASK
            #define COMBO_MASK \\
              (0x4u | 0x0) /* keep bit 2 */
            #if defined(OPTIONAL_METADATA_BRANCH)
            #include "optional_metadata_branch.h"
            #endif
            #if defined(MACRO_BRANCH_INCLUDE) && BLENDMODE == 32
            #include MACRO_BRANCH_INCLUDE
            #endif
            #if JOIN_TOKENS(BRANCH_, ENABLED)
            #include "pasted_branch.h"
            #endif
            #if HAS_VARIADIC_MASK(COMBO_MASK, 0x4)
            #include "variadic_branch.h"
            #endif
            #if HAS_MASK_ALIAS(COMBO_MASK, 0x4)
            #include "function_alias_branch.h"
            #endif
            #if JOIN_TOKENS(HAS_, MASK)(COMBO_MASK, 0x4)
            #include "pasted_callee_branch.h"
            #endif
            #if IS_DEFINED(ENABLE_TINT_BRANCH) && !IS_DEFINED(MISSING_DEFINED_FUNCTION_BRANCH)
            #include "defined_function_branch.h"
            #endif
            #if TEXTURE_COMBO
            #include "texture_combo_branch.h"
            #endif
            #if 0
            #include "inactive_elifdef_branch.h"
            #elifdef ENABLE_TINT_BRANCH
            #include "elifdef_branch.h"
            #endif
            #if 0
            #include "inactive_elifndef_branch.h"
            #elifndef MISSING_ELIFNDEF_BRANCH
            #include "elifndef_branch.h"
            #endif
            #if 0 OPERATOR_FRAGMENT_BRANCH
            #include "operator_fragment_branch.h"
            #endif
            #if !OPTIONAL_ARG_COUNT()
            #include "empty_variadic_branch.h"
            #endif
            #if defined(STRINGIFY_INCLUDE)
            #include STRINGIFY_INCLUDE(stringified_branch.h)
            #endif
            #if defined(INCLUDE_WRAPPER)
            #include INCLUDE_WRAPPER(EXPANDED_ARG_BRANCH_FILE)
            #endif
            #if BLENDMODE == 32
            #include "combo_branch.h"
            #endif
            #if 0 && UNKNOWN_METADATA_BRANCH
            #include "never_missing_branch.h"
            #endif
            #if !GLSL
            #include "inactive_missing_branch.h"
            void main() { gl_FragColor = vec4(0.0, 1.0, 1.0, 1.0); }
            #elif BLENDMODE == 0
            void main() { gl_FragColor = vec4(1.0, 1.0, 0.0, 1.0); }
            #elif (true ? false : true)
            void main() { gl_FragColor = vec4(0.5, 0.5, 0.0, 1.0); }
            #elif (false ? 1 : 1) && false
            void main() { gl_FragColor = vec4(0.1, 0.5, 0.0, 1.0); }
            #elif GLSL && defined(ENABLE_TINT_BRANCH) && \\
              !defined(MISSING_BRANCH) && ENABLE_TINT_BRANCH && DEFERRED_TINT_BRANCH && defined(FUNCTION_STYLE) && !FUNCTION_STYLE && HAS_MASK(COMBO_MASK, 0x4) && HAS_DEFERRED_MASK(DEFERRED_MASK_BITS) && (INCLUDED_BRANCH_FLAG == 7) && (BLENDMODE == 32) && ((COMBO_MASK & 0x7) == (1 << 2)) && ((DEFERRED_MASK_BITS | 0x2) == 6) && ((COMBO_MASK ^ 0x5) == 1) && ((COMBO_MASK >> 1) == 2) && ((0b100 == 4) && (010 == 8) && ('A' == 65) && ('\\n' == 10)) && ((12 / 3 + 2 * 5 - 1) >= 13) && ((~0) < 0) && (true ? ((COMBO_MASK & 0x4) == 4) : false) && (false ? 0 : 1) // active
            void main() { gl_FragColor = mix(texSample2D(g_Texture0, v_TexCoord + g_TexelSize), texture(g_Texture1, v_TexCoord * g_Texture0Rotation.xy + g_Texture0Translation) + textureLod(g_Texture1, v_TexCoord + g_TexelSizeHalf, 0.0) * 0.0, clamp((g_Texture0Resolution.x / max(g_Texture1Resolution.x, 1.0)) * g_Strength * helper(g_BlendAmount) + comboBranchHelper(g_Strength) * 0.0 + macroBranchHelper(g_Strength) * 0.0 + pastedBranchHelper(g_Strength) * 0.0 + variadicBranchHelper(g_Strength) * 0.0 + functionAliasBranchHelper(g_Strength) * 0.0 + pastedCalleeBranchHelper(g_Strength) * 0.0 + definedFunctionBranchHelper(g_Strength) * 0.0 + elifdefBranchHelper(g_Strength) * 0.0 + elifndefBranchHelper(g_Strength) * 0.0 + operatorFragmentBranchHelper(g_Strength) * 0.0 + emptyVariadicBranchHelper(g_Strength) * 0.0 + stringifiedBranchHelper(g_Strength) * 0.0 + expandedArgumentBranchHelper(g_Strength) * 0.0 + PerformLighting_V1(vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), 0.0, 0.0).x * 0.0 + g_TextureReductionScale * 0.0 + g_Texture0Rotation.x * 0.0 + g_Texture0Translation.y * 0.0 + g_TexelSize.x * 0.0 + g_TexelSizeHalf.y * 0.0, 0.0, 1.0)) + vec4(0.25, 0.0, 0.0, 0.0) * 0.0; }
            #else
            void main() { gl_FragColor = vec4(1.0, 0.0, 1.0, 1.0); }
            #endif
            """.utf8)),
            ("shaders/common_blending.h", Data("""
            #include <math.h>
            #define INCLUDED_BRANCH_FLAG 7
            uniform float g_BlendAmount; // {"material":"blend","default":0.5}
            """.utf8)),
            ("shaders/math.h", Data("float helper(float value) { return value; }\n".utf8)),
            ("shaders/combo_branch.h", Data("float comboBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/macro_branch.h", Data("float macroBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/pasted_branch.h", Data("float pastedBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/pasted_callee_branch.h", Data("float pastedCalleeBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/defined_function_branch.h", Data("float definedFunctionBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/texture_combo_branch.h", Data("float textureComboBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/variadic_branch.h", Data("float variadicBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/function_alias_branch.h", Data("float functionAliasBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/elifdef_branch.h", Data("float elifdefBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/elifndef_branch.h", Data("float elifndefBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/operator_fragment_branch.h", Data("float operatorFragmentBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/empty_variadic_branch.h", Data("float emptyVariadicBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/stringified_branch.h", Data("float stringifiedBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/expanded_arg_branch.h", Data("float expandedArgumentBranchHelper(float value) { return value; }\n".utf8)),
            ("shaders/optional_metadata_branch.h", Data("float optionalMetadataHelper(float value) { return value; }\n".utf8)),
            ("particles/rain.json", Data(#"{"material":"materials/particlemat.json","maxcount":10,"emitter":[{"name":"point","rate":10}],"initializer":[{"name":"velocityrandom","min":"0 1 0","max":"0 5 0"}],"operator":[{"name":"movement","gravity":"0 -9.8 0"}],"renderer":[{"name":"sprite"}],"controlpoint":[{"index":0,"name":"origin"}],"children":[{"particle":"particles/splash.json","delay":0.1}]}"#.utf8)),
            ("particles/splash.json", Data(#"{"material":"materials/particlemat.json","maxcount":2,"renderer":[{"name":"sprite"}]}"#.utf8)),
            ("materials/particlemat.json", Data(#"{"passes":[{"shader":"genericparticle"}]}"#.utf8)),
            ("fonts/demo.otf", Data([0x4F, 0x54, 0x54, 0x4F])),
            ("sounds/rain.mp3", Data([0x49, 0x44, 0x33])),
            ("materials/bgtex.tex", makeTextureData(flags: 2)),
            ("materials/util/noise.tex", makeTextureData(flags: 2))
        ]

        if projectInPackage {
            packageFiles.insert(("project.json", project), at: 0)
        }

        try makePackageData(files: packageFiles)
            .write(to: folderURL.appendingPathComponent("scene.pkg"))

        return folderURL
    }

    private var sceneJSON: String {
        """
        {
          "general": {
            "orthogonalprojection": { "width": 1920, "height": 1080 },
            "clearcolor": "0 0 0"
          },
          "camera": {
            "center": "0 0 0",
            "eye": "0 0 1",
            "up": "0 1 0"
          },
          "objects": [
            {
              "id": 1,
              "name": "Background",
              "image": "models/bg.json",
              "effects": [{
                "id": 11,
                "name": "Tint",
                "file": "effects/tint.json",
                "passes": [{ "id": 12, "constantshadervalues": { "strength": 2 } }]
              }]
            },
            {
              "id": 2,
              "name": "Clock",
              "text": { "value": "00:00", "script": "return '00:00';" },
              "font": "fonts/demo.otf"
            },
            {
              "id": 3,
              "name": "Rain",
              "particle": "particles/rain.json"
            },
            {
              "id": 4,
              "name": "Audio",
              "sound": ["sounds/rain.mp3"]
            }
          ]
        }
        """
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LivePaperParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeShaderInclude(_ path: String) -> WallpaperEngineResolvedShaderInclude {
        WallpaperEngineResolvedShaderInclude(
            requestedPath: path,
            resolvedPath: "shaders/\(path)",
            source: "float \(path.replacingOccurrences(of: ".h", with: ""))Helper(float value) { return value; }\n",
            metadata: WallpaperEngineShaderParser().parseShader(
                source: "",
                path: "shaders/\(path)",
                stage: .include
            )
        )
    }

    private func makePackageData(files: [(String, Data)]) -> Data {
        var payload = Data()
        let entries = files.map { path, data -> (String, UInt32, UInt32) in
            let offset = UInt32(payload.count)
            payload.append(data)
            return (path, offset, UInt32(data.count))
        }

        var result = Data()
        result.appendLengthPrefixedString("PKGV0023")
        result.appendUInt32(UInt32(entries.count))

        for entry in entries {
            result.appendLengthPrefixedString(entry.0)
            result.appendUInt32(entry.1)
            result.appendUInt32(entry.2)
        }

        result.append(payload)
        return result
    }

    private func makeTextureData(
        flags: UInt32,
        pixels: Data = Data((0..<(16 * 8)).map { UInt8($0 % 256) }),
        storedPixels: Data? = nil,
        compression: UInt32 = 0,
        uncompressedSize: Int32? = nil
    ) -> Data {
        let payload = storedPixels ?? pixels
        var data = Data()
        data.appendCString("TEXV0005")
        data.appendCString("TEXI0001")
        data.appendUInt32(9)
        data.appendUInt32(flags)
        data.appendUInt32(16)
        data.appendUInt32(8)
        data.appendUInt32(16)
        data.appendUInt32(8)
        data.appendUInt32(0)
        data.appendCString("TEXB0003")
        data.appendUInt32(1)
        data.appendInt32(-1)
        data.appendUInt32(1)
        data.appendUInt32(16)
        data.appendUInt32(8)
        data.appendUInt32(compression)
        data.appendInt32(uncompressedSize ?? Int32(pixels.count))
        data.appendInt32(Int32(payload.count))
        data.append(payload)

        if (flags & WallpaperEngineTextureParser.Flags.isGIF) != 0 {
            data.appendCString("TEXS0003")
            data.appendUInt32(1)
            data.appendUInt32(16)
            data.appendUInt32(8)
            data.appendUInt32(0)
            data.appendFloat32(0.25)
            data.appendFloat32(0)
            data.appendFloat32(0)
            data.appendFloat32(16)
            data.appendFloat32(16)
            data.appendFloat32(8)
            data.appendFloat32(8)
        }

        return data
    }

    private func makeMipmap(
        imageIndex: Int,
        level: Int,
        width: UInt32,
        height: UInt32
    ) -> WallpaperEngineTextureInfo.Mipmap {
        WallpaperEngineTextureInfo.Mipmap(
            imageIndex: imageIndex,
            level: level,
            width: width,
            height: height,
            compression: 0,
            uncompressedSize: Int32(width * height),
            byteCount: Int32(width * height),
            data: Data(repeating: 0, count: Int(width * height)),
            metadataJSON: nil
        )
    }

#if canImport(Compression)
    private func lz4Compressed(_ data: Data) throws -> Data {
        var output = Data(count: data.count + 64)
        let outputCapacity = output.count
        let encodedByteCount = data.withUnsafeBytes { sourceBuffer in
            output.withUnsafeMutableBytes { destinationBuffer in
                guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let destination = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }

                return compression_encode_buffer(
                    destination,
                    outputCapacity,
                    source,
                    data.count,
                    nil,
                    COMPRESSION_LZ4
                )
            }
        }

        guard encodedByteCount > 0 else {
            throw WallpaperEngineTextureError.mipmapDecompressionFailed(
                expected: data.count,
                actual: encodedByteCount
            )
        }

        output.removeSubrange(encodedByteCount..<output.count)
        return output
    }
#endif
}

private extension Data {
    mutating func appendLengthPrefixedString(_ value: String) {
        let data = Data(value.utf8)
        appendUInt32(UInt32(data.count))
        append(data)
    }

    mutating func appendCString(_ value: String) {
        append(Data(value.utf8))
        append(0)
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendInt32(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    mutating func appendFloat32(_ value: Float) {
        appendUInt32(value.bitPattern)
    }
}
