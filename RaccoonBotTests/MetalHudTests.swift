//
//  MetalHudTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

private func envs(hud: Bool, detail: MetalHudDetail, backend: String = "d3dmetal4") -> String {
    let o = GameOptions(cxGraphicsBackend: backend, mtlHudEnabled: hud)
    o.mtlHudDetail = detail.rawValue
    return getInlineEnvs(from: o, cxAppPath: "/nowhere")
}

@Suite("How much of the Metal HUD to show")
struct MetalHudDetailTests {

    /// What somebody who turns a HUD on mid-game usually wants.
    @Test func theDefaultIsTheLeastItWillShow() {
        #expect(GameOptions().mtlHudDetail == MetalHudDetail.fpsOnly.rawValue)
    }

    @Test func noHudMeansNoneOfTheseVariables() {
        let e = envs(hud: false, detail: .extended)
        #expect(!e.contains("MTL_HUD_ENABLED"))
        #expect(!e.contains("D3DM_SHOW_HUD_STATS"))
        #expect(!e.contains("MVK_CONFIG_PERFORMANCE_TRACKING"))
    }

    /// Apple's HUD alone. There is no system variable that draws less -- the
    /// whole of macOS knows only MTL_HUD_ENABLED and MTL_HUD_PATH -- so this is
    /// the floor, and it must not carry anybody else's counters.
    @Test func frameRateOnlyAddsNothingToApplesHud() {
        let e = envs(hud: true, detail: .fpsOnly)
        #expect(e.contains("MTL_HUD_ENABLED=1"))
        #expect(!e.contains("D3DM_SHOW_HUD_STATS"))
        #expect(!e.contains("MVK_CONFIG_PERFORMANCE_TRACKING"))
    }

    @Test func normalAddsTheToolkitsOwnCounters() {
        let e = envs(hud: true, detail: .normal)
        #expect(e.contains("MTL_HUD_ENABLED=1"))
        #expect(e.contains("D3DM_SHOW_HUD_STATS=1"))
        #expect(!e.contains("MVK_CONFIG_PERFORMANCE_TRACKING"))
    }

    @Test func extendedAddsPerFrameTimingsAsWell() {
        let e = envs(hud: true, detail: .extended)
        #expect(e.contains("MTL_HUD_ENABLED=1"))
        #expect(e.contains("D3DM_SHOW_HUD_STATS=1"))
        #expect(e.contains("MVK_CONFIG_PERFORMANCE_TRACKING=1"))
        #expect(e.contains("MVK_CONFIG_PERFORMANCE_LOGGING_INLINE=1"))
    }

    /// D3DMetal's counters belong to D3DMetal. Writing them for a game drawing
    /// through DXMT sets a variable nothing reads -- the same fault this file's
    /// neighbours were written to stop.
    @Test func aBackendThatDoesNotDrawWithD3DMetalGetsNoD3DMetalCounters() {
        let e = envs(hud: true, detail: .normal, backend: "dxmt")
        #expect(e.contains("MTL_HUD_ENABLED=1"))
        #expect(!e.contains("D3DM_SHOW_HUD_STATS"))
    }

    @Test func anUnreadableSavedValueFallsBackToTheLeast() {
        let o = GameOptions(cxGraphicsBackend: "d3dmetal4", mtlHudEnabled: true)
        o.mtlHudDetail = "something nobody wrote"
        let e = getInlineEnvs(from: o, cxAppPath: "/nowhere")
        #expect(e.contains("MTL_HUD_ENABLED=1"))
        #expect(!e.contains("D3DM_SHOW_HUD_STATS"))
    }

    /// Through the form it is actually stored in.
    @Test func theChoiceSurvivesBeingSavedAndRead() throws {
        let saved = try JSONDecoder().decode(
            GameOptionsData.self,
            from: Data(#"{"mtlHudEnabled":true,"mtlHudDetail":"extended"}"#.utf8))
        let o = GameOptions()
        o.set(data: saved)
        #expect(o.mtlHudDetail == MetalHudDetail.extended.rawValue)
    }

    /// Every title saved before this setting existed. None of them carries the
    /// key, and all of them must come back showing the least.
    @Test func aTitleSavedBeforeThisSettingExistedShowsTheLeast() throws {
        let old = try JSONDecoder().decode(
            GameOptionsData.self, from: Data(#"{"mtlHudEnabled":true}"#.utf8))
        let o = GameOptions()
        o.set(data: old)
        #expect(o.mtlHudEnabled)
        #expect(o.mtlHudDetail == MetalHudDetail.fpsOnly.rawValue)
    }
}
