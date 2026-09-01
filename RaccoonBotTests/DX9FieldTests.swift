//
//  DX9FieldTests.swift
//  RaccoonBotTests
//

import Foundation
import Testing
@testable import RaccoonBot

struct DX9FieldTests {

    /// A stored `dx9PatchEnabled` must not decide the renderer.
    ///
    /// The control that used to set it forced cxGraphicsBackend to "wine" --
    /// wined3d -- which is the opposite of what a Direct3D 9 title wants, and
    /// the DLL copy it was named for has been commented out for longer than
    /// that. The field survives so saved records decode; four titles here
    /// carry it set. What must never come back is the coupling.
    @Test func aStoredDX9FlagLeavesTheBackendAlone() throws {
        for flag in [true, false] {
            let json = "{\"cxGraphicsBackend\":\"dxvk\",\"dx9PatchEnabled\":\(flag)}"
            let data = try JSONDecoder().decode(GameOptionsData.self, from: Data(json.utf8))
            let options = GameOptions()
            options.set(data: data)
            #expect(options.cxGraphicsBackend == "dxvk",
                    "dx9PatchEnabled=\(flag) changed the renderer to \(options.cxGraphicsBackend)")
            #expect(options.dx9PatchEnabled == flag)
        }
    }

    /// And the auto-configuration path must not couple them either.
    @Test func autoConfigurationDoesNotCoupleThemEither() throws {
        let options = GameOptions()
        options.cxGraphicsBackend = "d3dmetal4"
        let json = #"{"dx9PatchEnabled":true}"#
        let data = try JSONDecoder().decode(GameOptionsData.self, from: Data(json.utf8))
        options.importAutoConfig(data: data)
        #expect(options.cxGraphicsBackend == "d3dmetal4")
        #expect(options.dx9PatchEnabled)
    }
}
