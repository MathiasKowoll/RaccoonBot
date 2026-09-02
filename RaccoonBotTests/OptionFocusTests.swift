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
        // The section is there by its switch; the slider only once it is on.
        #expect(OptionFocus.visibleControls(for: s).contains(.d3dCap))
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

/// A popup opened from the pad or the keyboard.
struct MenuFocusTests {
    private let backends: [(id: String, label: String)] = [
        ("dxmt", "DXMT"), ("d3dmetal3", "D3Dmetal3"), ("d3dmetal4", "D3Dmetal4"),
        ("wined3d", "Wine"), ("dxvk", "DXVK"), ("auto", "Auto"),
    ]

    /// Opens on what is selected, as the popup does, so opening and choosing
    /// straight away changes nothing.
    @Test func opensOnTheCurrentValue() {
        let m = MenuFocus(control: .backend, options: backends, selected: "wined3d")
        #expect(m.currentID == "wined3d")
        #expect(m.index == 3)
    }

    @Test func anUnknownValueOpensOnTheFirst() {
        let m = MenuFocus(control: .backend, options: backends, selected: "nonsense")
        #expect(m.currentID == "dxmt")
    }

    @Test func upAndDownStopAtTheEnds() {
        var m = MenuFocus(control: .backend, options: backends, selected: "dxmt")
        let up = m.move(.up); #expect(up == false)
        let down = m.move(.down); #expect(down)
        #expect(m.currentID == "d3dmetal3")
        while m.move(.down) {}
        #expect(m.currentID == "auto")
        let past = m.move(.down); #expect(past == false)
    }

    @Test func sidewaysIsNothingInAColumn() {
        var m = MenuFocus(control: .backend, options: backends, selected: "dxmt")
        let l = m.move(.left); #expect(l == false)
        let r = m.move(.right); #expect(r == false)
        #expect(m.currentID == "dxmt")
    }

    /// A hover with the mouse moves the highlight, so the two devices agree
    /// on what a press would pick.
    @Test func highlightingByIDMovesTheIndex() {
        var m = MenuFocus(control: .backend, options: backends, selected: "dxmt")
        m.highlight("dxvk")
        #expect(m.currentID == "dxvk")
        m.highlight("nope")
        #expect(m.currentID == "dxvk", "an unknown id leaves it where it was")
    }

    @Test func onlyThePopupsOpenAMenu() {
        #expect(OptionControl.backend.opensMenu)
        #expect(OptionControl.hudAlignment.opensMenu)
        #expect(!OptionControl.hudDetail.opensMenu, "segmented: every choice is already on screen")
        #expect(!OptionControl.mtlHud.opensMenu)
    }
}

/// The frame-rate cap, as a switch and not as a slider dragged to its floor.
struct FrameCapTests {
    @Test func offIsZeroAndOnStartsAtSixty() {
        #expect(OptionAdjust.cap(false) == 0)
        #expect(OptionAdjust.cap(true) == 60)
        #expect(OptionAdjust.cap(true) > 20, "on has to clear the launch line's threshold")
    }

    @Test func theSliderAppearsOnlyWhenTheCapIsOn() {
        var s = OptionPanelState(backend: "dxmt")
        #expect(OptionFocus.visibleControls(for: s).contains(.dxmtCap))
        #expect(!OptionFocus.visibleControls(for: s).contains(.dxmtMaxFPS))
        s.dxmtCapOn = true
        let on = OptionFocus.visibleControls(for: s)
        #expect(on.contains(.dxmtMaxFPS))
        #expect(on.firstIndex(of: .dxmtCap)! < on.firstIndex(of: .dxmtMaxFPS)!, "switch first, then how much")
    }

    @Test func d3dMetalHasTheSameShape() {
        var s = OptionPanelState(backend: "d3dmetal4", osVersion: 27)
        #expect(OptionFocus.visibleControls(for: s).contains(.d3dCap))
        #expect(!OptionFocus.visibleControls(for: s).contains(.d3dMaxFPS))
        s.d3dCapOn = true
        #expect(OptionFocus.visibleControls(for: s).contains(.d3dMaxFPS))
    }
}
