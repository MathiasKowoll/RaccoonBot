//
//  MetalHudTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

private func envs(hud: Bool, detail: MetalHudDetail,
                  backend: String = "d3dmetal4", opacity: Double = 1.0) -> String {
    let o = GameOptions(cxGraphicsBackend: backend, mtlHudEnabled: hud)
    o.mtlHudDetail = detail.rawValue
    o.mtlHudOpacity = opacity
    return getInlineEnvs(from: o, cxAppPath: "/nowhere")
}

@Suite("How much of the Metal HUD to show")
struct MetalHudDetailTests {

    /// What somebody who turns a HUD on mid-game usually wants.
    @Test func theDefaultIsTheLeastItWillShow() {
        #expect(GameOptions().mtlHudDetail == MetalHudDetail.fpsOnly.rawValue)
    }

    @Test func noHudMeansNoneOfTheseVariables() {
        let e = envs(hud: false, detail: .extended, opacity: 0.5)
        #expect(!e.contains("MTL_HUD_ENABLED"))
        #expect(!e.contains("MTL_HUD_ELEMENTS"))
        #expect(!e.contains("MTL_HUD_OPACITY"))
        #expect(!e.contains("D3DM_SHOW_HUD_STATS"))
    }

    /// Apple's HUD alone. There is no system variable that draws less -- the
    /// whole of macOS knows only MTL_HUD_ENABLED and MTL_HUD_PATH -- so this is
    /// the floor, and it must not carry anybody else's counters.
    /// One line, which is the point of it.
    @Test func frameRateOnlyAsksForOneRow() {
        let e = envs(hud: true, detail: .fpsOnly)
        #expect(e.contains("MTL_HUD_ENABLED=1"))
        #expect(e.contains("MTL_HUD_ELEMENTS=fps "))
        #expect(!e.contains("D3DM_SHOW_HUD_STATS"))
    }

    @Test func normalAsksForTheUsualRows() {
        let e = envs(hud: true, detail: .normal)
        #expect(e.contains("MTL_HUD_ELEMENTS="))
        for row in ["fps", "memory", "gputime", "frameinterval"] {
            #expect(MetalHudDetail.normal.elements.contains(row))
        }
        // Not everything: that is what Extended is for.
        #expect(MetalHudDetail.normal.elements.count < MetalHudDetail.allElements.count)
        #expect(!e.contains("D3DM_SHOW_HUD_STATS"))
    }

    @Test func extendedAsksForEveryRowAndTheToolkitsCounters() {
        let e = envs(hud: true, detail: .extended)
        #expect(MetalHudDetail.extended.elements.count == MetalHudDetail.allElements.count)
        #expect(e.contains("D3DM_SHOW_HUD_STATS=1"))
    }

    /// Every level has to draw the frame rate: it is the one row somebody
    /// turning a HUD on is always there for.
    @Test(arguments: MetalHudDetail.allCases)
    func everyLevelShowsTheFrameRate(_ detail: MetalHudDetail) {
        #expect(detail.elements.contains("fps"))
    }

    @Test func fullOpacityIsNotWrittenAtAll() {
        #expect(!envs(hud: true, detail: .fpsOnly, opacity: 1.0).contains("MTL_HUD_OPACITY"))
    }

    @Test func aChosenOpacityIsWrittenAsTheHudExpects() {
        let e = envs(hud: true, detail: .fpsOnly, opacity: 0.45)
        #expect(e.contains("MTL_HUD_OPACITY=0.450"))
    }

    /// D3DMetal's counters belong to D3DMetal. Writing them for a game drawing
    /// through DXMT sets a variable nothing reads -- the same fault this file's
    /// neighbours were written to stop.
    @Test func aBackendThatDoesNotDrawWithD3DMetalGetsNoD3DMetalCounters() {
        let e = envs(hud: true, detail: .extended, backend: "dxmt")
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
