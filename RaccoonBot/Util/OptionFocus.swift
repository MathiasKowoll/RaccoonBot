//
//  OptionFocus.swift
//  RaccoonBot
//
//  Which control of a title's options a controller is on, and what a press
//  does to it.
//
//  The panel is a column of controls, some of which are only there under
//  conditions the panel decides -- a DXMT section when DXMT is the backend, a
//  HUD section when the HUD is on. The controller has to walk the same list
//  the eye does, so the conditions live here as a value the view fills in, and
//  the order here IS the order on screen. A control added to the panel and not
//  to this list is one a controller cannot reach, which is at least a visible
//  failure rather than a silent one.
//
//  Text fields are not in the list. A pad has no way to type into one, and
//  landing on it with nothing to do reads as broken. They stay the keyboard's.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum OptionControl: String, CaseIterable, Hashable {
    // Generic
    case backend, x87, mtlHud, advertiseAVX, msync, sdl, hidraw, ue4Hack, mvkArgBuff
    // DXMT
    case dxmtCap, dxmtMaxFPS, dxmtMetalFX, dxmtUpscale
    // Metal HUD
    case hudDetail, hudAlignment, hudOpacity
    // D3DMetal
    case d3dMtl4, d3dCap, d3dMaxFPS
    // Actions
    case save, undo, reset, autoconfigure

    var isButton: Bool {
        switch self {
        case .save, .undo, .reset, .autoconfigure: return true
        default: return false
        }
    }

    /// A press opens a list to choose from, the way a click opens the popup.
    /// The segmented HUD picker is not one: all its choices are already on
    /// screen, and cycling is what a click does there too.
    var opensMenu: Bool {
        switch self {
        case .backend, .hudAlignment: return true
        default: return false
        }
    }
}

/// An open menu: which control it belongs to, what it lists, and where the
/// highlight is. The list is the same one the mouse gets, so choosing with a
/// pad, the arrows or a click all land on the same value.
nonisolated struct MenuFocus: Equatable {
    let control: OptionControl
    let ids: [String]
    let labels: [String]
    private(set) var index: Int

    init(control: OptionControl, options: [(id: String, label: String)], selected: String) {
        self.control = control
        self.ids = options.map(\.id)
        self.labels = options.map(\.label)
        // Opens on the current value, as a popup does, so a press-then-select
        // with nothing in between changes nothing.
        self.index = max(0, options.firstIndex { $0.id == selected } ?? 0)
    }

    var currentID: String { ids.isEmpty ? "" : ids[index] }

    /// Up and down, stopping at the ends. Sideways is nothing: a menu is a
    /// column.
    @discardableResult
    mutating func move(_ direction: GridFocus.Direction) -> Bool {
        guard !ids.isEmpty else { return false }
        switch direction {
        case .up:   guard index > 0 else { return false }; index -= 1
        case .down: guard index < ids.count - 1 else { return false }; index += 1
        case .left, .right: return false
        }
        return true
    }

    mutating func highlight(_ id: String) {
        if let at = ids.firstIndex(of: id) { index = at }
    }
}

/// What the panel is showing, so the list can be the visible one.
nonisolated struct OptionPanelState: Equatable {
    var isNative = false
    var backend = "dxmt"
    var hudEnabled = false
    var metalFXOn = false
    var dxmtCapOn = false
    var d3dCapOn = false
    var osVersion = 26
    var armShown = false
}

nonisolated struct OptionFocus: Equatable {

    enum Adjust { case select, left, right }

    /// What a press did, so the view knows whether to act on a button.
    enum Outcome: Equatable {
        case nothing
        case changed
        case activate(OptionControl)
        /// A press on a popup: the view opens the list rather than the value
        /// changing here. Sideways on the same control still cycles.
        case openMenu(OptionControl)
    }

    private(set) var visible: [OptionControl] = []
    private(set) var index: Int?

    var current: OptionControl? {
        guard let index, index < visible.count else { return nil }
        return visible[index]
    }

    /// The controls on screen, in the order they are on screen.
    static func visibleControls(for state: OptionPanelState) -> [OptionControl] {
        var list: [OptionControl] = []
        if !state.isNative { list.append(.backend) }
        // Nothing for the two text fields.
        if !state.isNative { list.append(.x87) }
        list += [.mtlHud, .advertiseAVX]
        if !state.isNative { list += [.msync, .sdl, .hidraw, .ue4Hack, .mvkArgBuff] }
        if state.backend == "dxmt" {
            list.append(.dxmtCap)
            if state.dxmtCapOn { list.append(.dxmtMaxFPS) }
            list.append(.dxmtMetalFX)
            if state.metalFXOn { list.append(.dxmtUpscale) }
        }
        if state.hudEnabled { list += [.hudDetail, .hudAlignment, .hudOpacity] }
        if state.backend.hasPrefix("d3dmetal") {
            if state.osVersion >= 27 { list.append(.d3dMtl4) }
            list.append(.d3dCap)
            if state.d3dCapOn { list.append(.d3dMaxFPS) }
        }
        list += [.save, .undo, .reset, .autoconfigure]
        return list
    }

    /// The panel changed shape. The selection stays on the same CONTROL if it
    /// is still there, because a toggle that hides a section below it should
    /// not also move what you are on.
    mutating func update(for state: OptionPanelState) {
        let was = current
        visible = Self.visibleControls(for: state)
        if let was, let at = visible.firstIndex(of: was) {
            index = at
        } else if let index, !visible.isEmpty {
            self.index = min(index, visible.count - 1)
        } else {
            index = visible.isEmpty ? nil : index
        }
    }

    mutating func selectFirstIfNeeded() {
        if index == nil, !visible.isEmpty { index = 0 }
    }

    mutating func clear() { index = nil }

    @discardableResult
    mutating func move(_ direction: GridFocus.Direction) -> Bool {
        guard !visible.isEmpty else { return false }
        guard let current = index else { index = 0; return true }
        switch direction {
        case .up:   guard current > 0 else { return false }; index = current - 1
        case .down: guard current < visible.count - 1 else { return false }; index = current + 1
        case .left, .right: return false   // those adjust; the view asks `adjust`
        }
        return true
    }
}

/// What a press does to the form. Kept as functions on the form's data rather
/// than on the view, so every mapping can be stated in a test: which way a
/// slider goes, where a picker wraps, that A on a toggle is a flip.
nonisolated enum OptionAdjust {

    static let backends = ["dxmt", "d3dmetal3", "d3dmetal4", "wined3d", "dxvk", "auto"]

    /// Step sizes, chosen to be felt: one press is a change you can see.
    static let fpsStep: Double = 5
    static let opacityStep: Double = 0.05
    static let upscaleStep: Double = 0.125   // the slider's own step; anything else lands between its stops

    /// What the cap becomes when its switch is thrown. The launch line emits a
    /// cap only above 20, so 0 is off in the only sense that matters; 60 is
    /// where on starts, and the slider takes it from there.
    static func cap(_ on: Bool) -> Double { on ? 60 : 0 }

    static func cycle(_ value: String, in options: [String], forward: Bool) -> String {
        guard let at = options.firstIndex(of: value) else { return options.first ?? value }
        let next = forward ? (at + 1) % options.count : (at - 1 + options.count) % options.count
        return options[next]
    }

    static func nudge(_ value: Double, by step: Double, in range: ClosedRange<Double>, forward: Bool) -> Double {
        let raw = value + (forward ? step : -step)
        // Snap to the step so a slider that started off-grid does not stay
        // off-grid forever, then clamp.
        let snapped = (raw / step).rounded() * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}
