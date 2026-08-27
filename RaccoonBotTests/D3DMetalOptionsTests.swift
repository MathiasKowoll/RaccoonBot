//
//  D3DMetalOptionsTests.swift
//  RaccoonBotTests
//
//  D3DM_MTL4 and D3DM_MAX_FPS exist only in D3DMetal 4.
//
//  Measured on the two toolkits this application carries: the 3.0 binary
//  contains neither string, the 4 one contains both. Which gets installed is
//  decided by the backend name at launch, so writing them for a 3 engine sets
//  variables nothing reads.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@MainActor
struct D3DMetalOptionTests {

    @MainActor
    private func options(backend: String, mtl4: Bool? = nil, maxFPS: Double = 0) -> GameOptions {
        let o = GameOptions(cxGraphicsBackend: backend, d3dMaxFPS: maxFPS)
        if let mtl4 { o.d3dMtl4Enabled = mtl4 }
        else { o.d3dMtl4Enabled = backend == "d3dmetal4" && OSVersion >= 27 }
        return o
    }

    @Test func metal4IsOnByDefaultWhenThatIsTheBackend() {
        #expect(options(backend: "d3dmetal4").d3dMtl4Enabled,
                "a backend called Metal 4 running with Metal 4 off")
    }

    @Test func anotherBackendLeavesItOff() {
        #expect(!options(backend: "d3dmetal3").d3dMtl4Enabled)
        #expect(!options(backend: "dxmt").d3dMtl4Enabled)
    }

    /// A choice already made is not overridden by the default.
    @Test func anExplicitChoiceIsKept() {
        #expect(!options(backend: "d3dmetal4", mtl4: false).d3dMtl4Enabled)
        #expect(options(backend: "d3dmetal3", mtl4: true).d3dMtl4Enabled)
    }

    @Test func theVariablesAreWrittenOnlyForTheToolkitThatReadsThem() {
        let four = getInlineEnvs(from: options(backend: "d3dmetal4", mtl4: true, maxFPS: 60))
        #expect(four.contains("D3DM_MTL4=1"))
        #expect(four.contains("D3DM_MAX_FPS="))

        for backend in ["d3dmetal3", "d3dmetal", "dxmt", "dxvk"] {
            let other = getInlineEnvs(from: options(backend: backend, mtl4: true, maxFPS: 60))
            #expect(!other.contains("D3DM_MTL4"), "\(backend) got a variable only D3DMetal 4 reads")
            #expect(!other.contains("D3DM_MAX_FPS"), "\(backend) got a frame cap it will not honour")
        }
    }

    @Test func turningItOffStillSaysSo() {
        // Explicit 0 is not the same as absent: D3DMetal 4 defaults it on its
        // own, and the user asking for it off has to reach the toolkit.
        #expect(getInlineEnvs(from: options(backend: "d3dmetal4", mtl4: false)).contains("D3DM_MTL4=0"))
    }

    /// CX_GRAPHICS_BACKEND never carries our own name for the toolkit
    /// generation: CrossOver knows "d3dmetal", not "d3dmetal4".
    @Test func crossoverIsToldABackendItUnderstands() {
        let env = getInlineEnvs(from: options(backend: "d3dmetal4"))
        #expect(env.contains("CX_GRAPHICS_BACKEND=\"d3dmetal\""))
        #expect(!env.contains("CX_GRAPHICS_BACKEND=\"d3dmetal4\""))
    }
}
