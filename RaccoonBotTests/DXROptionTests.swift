//
//  DXROptionTests.swift
//  RaccoonBotTests
//
//  The per-title ray-tracing switch. `d3dSupportDXR` was stored for every
//  title and read by nothing, so D3DMetal always offered DXR. Off now writes
//  D3DM_SUPPORT_DXR=0; On writes nothing, because it is the toolkit's default.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

@MainActor
struct DXROptionTests {

    private func env(_ backend: String, dxr: String?) -> String {
        let o = GameOptions(cxGraphicsBackend: backend)
        o.d3dSupportDXR = dxr
        return getInlineEnvs(from: o)
    }

    @Test func offIsWrittenForBothToolkits() {
        for backend in ["d3dmetal3", "d3dmetal4"] {
            #expect(env(backend, dxr: DXROption.off).contains("D3DM_SUPPORT_DXR=0"), "\(backend)")
        }
    }

    @Test func onAndUnsetWriteNothing() {
        for dxr in [DXROption.toolkitDefault, nil] {
            #expect(!env("d3dmetal4", dxr: dxr).contains("D3DM_SUPPORT_DXR"))
        }
    }

    @Test func otherBackendsNeverGetIt() {
        for backend in ["dxmt", "dxvk"] {
            #expect(!env(backend, dxr: DXROption.off).contains("D3DM_SUPPORT_DXR"), "\(backend)")
        }
    }

    @Test func aStaleBottleKeyIsCleared() {
        #expect(PROCYON_MANAGED_ENV_KEYS.contains("D3DM_SUPPORT_DXR"))
    }

    @Test func theRowIsWalkedOnBothToolkitsAndNowhereElse() {
        for backend in ["d3dmetal3", "d3dmetal4"] {
            let list = OptionFocus.visibleControls(for: OptionPanelState(backend: backend, osVersion: 27))
            #expect(list.contains(.d3dDXR), "\(backend)")
        }
        let dxmt = OptionFocus.visibleControls(for: OptionPanelState(backend: "dxmt"))
        #expect(!dxmt.contains(.d3dDXR))
    }
}
