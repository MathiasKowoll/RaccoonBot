//
//  OptionFocusTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

/// A controller walking a title's options.
struct OptionFocusTests {

    private var windows: OptionPanelState {
        OptionPanelState(isNative: false, backend: "dxmt", hudEnabled: true, metalFXOn: true, osVersion: 27)
    }

    /// The list follows the panel's own conditions, in the panel's own order.
    @Test func theVisibleListMatchesThePanel() {
        let all = OptionFocus.visibleControls(for: windows)
        #expect(all.first == .backend)
        #expect(all.contains(.dxmtUpscale), "metalFX on shows the upscale slider")
        #expect(all.contains(.hudOpacity), "HUD on shows its section")
        #expect(!all.contains(.d3dMaxFPS), "DXMT selected hides D3DMetal")
        #expect(all.suffix(4) == [.save, .undo, .reset, .autoconfigure])
    }

    @Test func aNativeTitleHasNoWineControls() {
        let list = OptionFocus.visibleControls(for: OptionPanelState(isNative: true))
        #expect(!list.contains(.backend))
        #expect(!list.contains(.msync))
        #expect(list.contains(.mtlHud))
        #expect(list.contains(.save))
    }

    @Test func d3dMetalShowsItsSectionAndMetal4OnlyOn27() {
        var s = OptionPanelState(backend: "d3dmetal4", osVersion: 26)
        #expect(!OptionFocus.visibleControls(for: s).contains(.d3dMtl4))
        #expect(OptionFocus.visibleControls(for: s).contains(.d3dMaxFPS))
        s.osVersion = 27
        #expect(OptionFocus.visibleControls(for: s).contains(.d3dMtl4))
    }

    @Test func upAndDownWalkTheList() {
        var f = OptionFocus()
        f.update(for: windows)
        f.selectFirstIfNeeded()
        #expect(f.current == .backend)
        let d = f.move(.down); #expect(d)
        #expect(f.current == .x87)
        let u = f.move(.up); #expect(u)
        #expect(f.current == .backend)
        let top = f.move(.up); #expect(top == false)
    }

    /// Turning the HUD off removes the section below; the control you were on
    /// stays selected. A toggle should not also move you.
    @Test func hidingASectionKeepsTheSelectedControl() {
        var f = OptionFocus()
        var s = windows
        f.update(for: s)
        f.selectFirstIfNeeded()
        while f.current != .mtlHud { f.move(.down) }
        s.hudEnabled = false
        f.update(for: s)
        #expect(f.current == .mtlHud)
    }

    /// If the control you were on is the one that vanished, land nearby.
    @Test func losingTheSelectedControlLandsNearby() {
        var f = OptionFocus()
        var s = windows
        f.update(for: s)
        f.selectFirstIfNeeded()
        while f.current != .hudOpacity { f.move(.down) }
        s.hudEnabled = false
        f.update(for: s)
        #expect(f.current != nil)
        #expect(f.current != .hudOpacity)
    }

    @Test func pickersCycleAndWrap() {
        let b = OptionAdjust.backends
        #expect(OptionAdjust.cycle("dxmt", in: b, forward: true) == "d3dmetal3")
        #expect(OptionAdjust.cycle("auto", in: b, forward: true) == "dxmt", "wraps at the end")
        #expect(OptionAdjust.cycle("dxmt", in: b, forward: false) == "auto", "and at the start")
        #expect(OptionAdjust.cycle("garbage", in: b, forward: true) == "dxmt", "an unknown value lands on the first")
    }

    @Test func slidersNudgeSnapAndClamp() {
        #expect(OptionAdjust.nudge(60, by: 5, in: 0...240, forward: true) == 65)
        #expect(OptionAdjust.nudge(62, by: 5, in: 0...240, forward: true) == 65, "snaps to the step")
        #expect(OptionAdjust.nudge(240, by: 5, in: 0...240, forward: true) == 240, "clamps at the top")
        #expect(OptionAdjust.nudge(0.12, by: 0.05, in: 0.1...1.0, forward: false) == 0.1, "clamps at the bottom")
    }

    @Test func theButtonsAreButtons() {
        for c in [OptionControl.save, .undo, .reset, .autoconfigure] { #expect(c.isButton) }
        #expect(!OptionControl.mtlHud.isButton)
    }
}
