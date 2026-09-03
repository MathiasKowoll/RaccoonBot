//
//  GameOptionsView.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 12/02/2026.
//

import SwiftUI

struct GameOptionsView: View {
    @Binding var game: Game?
    @EnvironmentObject var gameOptions: GameOptions
    @EnvironmentObject var session: OptionsSession
    /// Needed to tell the user whether an ARM bottle has been chosen at all.
    /// Provided by the sheet that presents this view.
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @StateObject private var fix = MGVFCoordinator()
    @State private var confirmingInstall = false
    @State private var confirmingUninstall = false
    @State private var autoconfigError: String?

    /// The controller, shared with the grid underneath and taken over while
    /// this panel is up; the control it is on; and the way out.
    @EnvironmentObject private var gamepad: GamepadInput
    @State private var padToken: UUID?
    @State private var focus = OptionFocus()
    /// The popup that is open, if one is.
    @State private var menu: MenuFocus?
    @Environment(\.dismiss) private var dismiss
    @State var isLoading = false

    /// The folder the game is installed in, from its metadata.
    ///
    /// Never GameDetailView.gameFolder: that one is built without the "common"
    /// component and points at a path that does not exist.
    private var gameFolder: String? {
        guard let id = game?.id else { return nil }
        return getMeta(libraryPageGlobals.gamesMeta, byID: id)?.gameURL?.path(percentEncoded: false)
    }
    
    var preferredMaxFrameRate: String {
        $gameOptions.dxmtPreferredMaxFrameRate.wrappedValue < 20.0 ? "Disabled" : "\($gameOptions.dxmtPreferredMaxFrameRate.wrappedValue)"
    }
    
    var d3dMaxFPS: String {
        $gameOptions.d3dMaxFPS.wrappedValue < 20.0 ? "Disabled" : "\($gameOptions.d3dMaxFPS.wrappedValue)"
    }
    
    var body: some View {
        // Guarded rather than forced. A body getter that traps takes the whole
        // application down with no message -- which is what opening this from
        // the list did, because GameOptionsView force-unwraps its game and
        // requires a GameOptions in the environment that only the detail page
        // happened to provide. GameOptionsSheet supplies both now; this is the
        // second lock on the same door.
        if let current = game {
        let id = current.steamAppID != 0 ? String(describing: current.steamAppID) : String(describing: current.id)
        let gameOptKey = GameDefaults.key(forAppID: current.steamAppID,
                                          id: String(describing: current.id))
    ScrollViewReader { proxy in
        VStack (alignment: .leading, spacing: 5){
            Text("id:\(id)").font(Font.footnote).foregroundStyle(.procyonBrightGray)
            Form {
                VStack(alignment: .leading, spacing: 20) {
                    Section("Generic options") {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .trailing){
                                if !current.isNative {
                                    DropDown(options: cxGraphicsBackend, label: "Graphics Backend", value: $gameOptions.cxGraphicsBackend)
                                        .onChange(of: gameOptions.cxGraphicsBackend) { _, backend in
                                            // The variable follows the choice. Picking a
                                            // backend called Metal 4 and then running with
                                            // Metal 4 off is not what anybody meant, and
                                            // loading a saved value is not enough -- the
                                            // change has to reach it too, which is the bug
                                            // this fixes.
                                            //
                                            // Off below macOS 27, where the toggle is
                                            // disabled: turning it on there would write
                                            // D3DM_MTL4=1 for a system that cannot use it
                                            // and nobody could turn it back off.
                                            gameOptions.d3dMtl4Enabled =
                                                backend == "d3dmetal4" && OSVersion >= 27
                                        }
                                        .optionFocus(.backend, current: focus.current, shown: gamepad.showsFocus)
                                        .popover(isPresented: Binding(get: { menu?.control == .backend },
                                                                         set: { if !$0 { menu = nil } }),
                                                 arrowEdge: .bottom) { menuPopover(for: .backend) }
                                }
                                Divider()
                                TextField("Game arguments", text: $gameOptions.gameArguments)
                                TextField("Env variables", text: $gameOptions.envVariables)
                                if !current.isNative {
                                    Divider()
                                    if showArmSupport {
                                        Toggle("Run in the ARM bottle", isOn: $gameOptions.useArmBottle)
                                            .onChange(of: gameOptions.useArmBottle) { _, newValue in
                                                // An ARM bottle has no D3DMetal: Direct3D goes
                                                // through DXMT, which reaches D3D11. Forcing the
                                                // backend here is the same idiom the DX9 toggle
                                                // already uses below.
                                                if newValue { gameOptions.cxGraphicsBackend = "dxmt" }
                                            }
                                        if gameOptions.useArmBottle {
                                            if appGlobals.selectedArmBottle.isEmpty {
                                                Text("No ARM bottle chosen. Pick one in Options, or create one in CrossOver with the ARM architecture.")
                                                    .font(.footnote).foregroundStyle(.orange)
                                            }
                                            Text("Draws through DXMT, so Direct3D 11 at most: a Direct3D 12 title will not run here.")
                                                .font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    Divider()
                                    Text("32Bits options")
                                    Toggle("Reduced x87 precision", isOn: $gameOptions.x87PatchEnabled)
                                        .optionFocus(.x87, current: focus.current, shown: gamepad.showsFocus)
                                    // "Use DX9" is gone: it promised one thing and did the
                                    // opposite.
                                    //
                                    // Its only live effect was to set the backend to
                                    // "wine" -- wined3d -- which is the opposite of what a
                                    // Direct3D 9 title wants, since those are the ones that
                                    // need d9vk. The DLL copy it was named for has one call
                                    // site and it is commented out, and the override it
                                    // once wrote was removed long ago, as the comment that
                                    // used to sit here said. A switch whose only working
                                    // part chose a renderer nobody asked for.
                                    //
                                    // The stored field stays so saved records still decode.
                                    // Four titles here carry it set and their backends are
                                    // untouched by this; a test holds that the two stay
                                    // uncoupled.
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Toggle("Metal HUD", isOn: $gameOptions.mtlHudEnabled)
                                    .optionFocus(.mtlHud, current: focus.current, shown: gamepad.showsFocus)
                                Toggle("Advertise AVX", isOn: $gameOptions.advertiseAVX)
                                    .optionFocus(.advertiseAVX, current: focus.current, shown: gamepad.showsFocus)
                                if !current.isNative {
                                    Toggle("MSync", isOn: $gameOptions.wineMSync)
                                        .optionFocus(.msync, current: focus.current, shown: gamepad.showsFocus)
                                    Toggle("Enable SDL", isOn: $gameOptions.enableSDL)
                                        .optionFocus(.sdl, current: focus.current, shown: gamepad.showsFocus)
                                    Toggle("Disable Hidraw", isOn: $gameOptions.disableHidraw)
                                        .optionFocus(.hidraw, current: focus.current, shown: gamepad.showsFocus)
                                    Divider()
                                    Text("Vulkan options")
                                    Toggle("Enable UE4 Hack", isOn: $gameOptions.ue4Hack)
                                        .optionFocus(.ue4Hack, current: focus.current, shown: gamepad.showsFocus)
                                    Toggle("MTL arg. buffers", isOn: $gameOptions.mvkArgBuff)
                                        .optionFocus(.mvkArgBuff, current: focus.current, shown: gamepad.showsFocus)
                                    DropDown(options: cxVulkanBackend, label: "VK lib", value: $gameOptions.vulkanLib)
                                    .pickerStyle(.menu)
                                }
                            }
                        }
                    }
                    if(gameOptions.cxGraphicsBackend == "dxmt") {
                        Divider()
                        Section("DXMT Options") {
                            // On or off, said outright. The launch line emits a cap only when the
                            // value is above 20, so "off" used to be a slider dragged to its
                            // bottom -- which nobody would guess. The toggle writes 0 for off and
                            // 60 for on; the slider then says how much.
                            Toggle("Limit frame rate", isOn: Binding(
                                get: { gameOptions.dxmtPreferredMaxFrameRate > 20 },
                                set: { gameOptions.dxmtPreferredMaxFrameRate = OptionAdjust.cap($0) }))
                                .optionFocus(.dxmtCap, current: focus.current, shown: gamepad.showsFocus)
                            if gameOptions.dxmtPreferredMaxFrameRate > 20 {
                                                            VStack{
                                                                Text(localizedString(forKey: "preferredMaxFrameRate", value: preferredMaxFrameRate))
                                                                Slider(
                                                                    value: $gameOptions.dxmtPreferredMaxFrameRate,
                                                                    in: 19...240,
                                                                    step: 1.0
                                                                )
                                                                .help(localizedString(forKey: "preferredMaxFrameRateHelp"))
                                                                    .optionFocus(.dxmtMaxFPS, current: focus.current, shown: gamepad.showsFocus)
                            }
                            }
                            
                            Toggle("metalFXSpatial", isOn: $gameOptions.dxmtMetalFXSpatial)
                                .help(localizedString(forKey: "metalFXSpatialHelp"))
                                .onChange(of: gameOptions.dxmtMetalFXSpatial) { oldValue, newValue in
                                    if (!newValue) {
                                        $gameOptions.dxmtMetalSpatialUpscaleFactor.wrappedValue = 1.0
                                    }
                                }
                                .optionFocus(.dxmtMetalFX, current: focus.current, shown: gamepad.showsFocus)
                            
                            if (gameOptions.dxmtMetalFXSpatial) {
                                VStack {
                                    Text(localizedString(forKey:"metalSpatialUpscaleFactor", value: String($gameOptions.dxmtMetalSpatialUpscaleFactor.wrappedValue)))
                                    Slider(
                                        value: $gameOptions.dxmtMetalSpatialUpscaleFactor,
                                        in: 1.0...2.0,
                                        step: 0.125
                                    )
                                    .help(localizedString(forKey: "metalFXSpatialHelp"))
                                        .optionFocus(.dxmtUpscale, current: focus.current, shown: gamepad.showsFocus)
                                }
                            }
                        }
                    }
                    if(gameOptions.cxGraphicsBackend == "d3dmetal4") {
                        Divider()
                        // Its own section rather than three controls squeezed
                        // into the column of toggles: a picker, a slider and a
                        // second picker need the width, and they are only worth
                        // any room at all while the HUD is on.
                        if gameOptions.mtlHudEnabled {
                            Section("Metal HUD") {
                                Picker("Show", selection: $gameOptions.mtlHudDetail) {
                                    ForEach(MetalHudDetail.allCases, id: \.rawValue) { detail in
                                        Text(detail.label).tag(detail.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                    .optionFocus(.hudDetail, current: focus.current, shown: gamepad.showsFocus)
                                Text((MetalHudDetail(rawValue: gameOptions.mtlHudDetail) ?? .fpsOnly).explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Picker("Position", selection: $gameOptions.mtlHudAlignment) {
                                    ForEach(MetalHudAlignment.allCases, id: \.rawValue) { corner in
                                        Text(corner.label).tag(corner.rawValue)
                                    }
                                }
                                    .optionFocus(.hudAlignment, current: focus.current, shown: gamepad.showsFocus)
                                    .popover(isPresented: Binding(get: { menu?.control == .hudAlignment },
                                                                     set: { if !$0 { menu = nil } }),
                                             arrowEdge: .bottom) { menuPopover(for: .hudAlignment) }
                                VStack {
                                    Text("Opacity \(Int(gameOptions.mtlHudOpacity * 100))%")
                                    Slider(value: $gameOptions.mtlHudOpacity, in: 0.1...1.0)
                                        .optionFocus(.hudOpacity, current: focus.current, shown: gamepad.showsFocus)
                                }
                            }
                        }

                        Section("D3DMetal Options") {
                            Toggle("Metal 4 Backend", isOn: $gameOptions.d3dMtl4Enabled)
                                .help(localizedString(forKey: "metal4Backend"))
                                .disabled(OSVersion < 27)
                                .opacity(OSVersion < 27 ? 0.5 : 1.0)
                                .optionFocus(.d3dMtl4, current: focus.current, shown: gamepad.showsFocus)
                            // On or off, said outright. The launch line emits a cap only when the
                            // value is above 20, so "off" used to be a slider dragged to its
                            // bottom -- which nobody would guess. The toggle writes 0 for off and
                            // 60 for on; the slider then says how much.
                            Toggle("Limit frame rate", isOn: Binding(
                                get: { gameOptions.d3dMaxFPS > 20 },
                                set: { gameOptions.d3dMaxFPS = OptionAdjust.cap($0) }))
                                .optionFocus(.d3dCap, current: focus.current, shown: gamepad.showsFocus)
                            if gameOptions.d3dMaxFPS > 20 {
                                                            VStack{
                                                                Text(localizedString(forKey: "preferredMaxFrameRate", value: d3dMaxFPS))
                                                                Slider(
                                                                    value: $gameOptions.d3dMaxFPS,
                                                                    in: 19...240,
                                                                    step: 1.0
                                                                )
                                                                .help(localizedString(forKey: "preferredMaxFrameRateHelp"))
                                                                    .optionFocus(.d3dMaxFPS, current: focus.current, shown: gamepad.showsFocus)
                            }
                            }
                        }
                    }
                    HStack {
                        // Save commits now and keeps editing; closing the panel commits
                        // too, so this is for somebody who wants the file right before
                        // running Auto configure, not a step that can be forgotten. Both
                        // buttons say whether there is anything to do, which is the only
                        // "unsaved changes" indicator: the state, on the thing that acts.
                        Button(session.isDirty(gameOptions) ? "Save settings" : "Saved") {
                            console.log("saving")
                            session.save(gameOptions)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!session.isDirty(gameOptions))
                            .optionFocus(.save, current: focus.current, shown: gamepad.showsFocus)
                        // Undo puts the form back to the file: the escape hatch before
                        // closing, and a state that cannot be wrong. Reset, beside it,
                        // goes to factory defaults -- a different and much larger step,
                        // left as it was.
                        Button("Undo") {
                            console.log("undoing")
                            session.undo(into: gameOptions)
                        }
                        .disabled(!session.isDirty(gameOptions))
                            .optionFocus(.undo, current: focus.current, shown: gamepad.showsFocus)
                        Button("Reset") {
                            console.log("resetting")
                            gameOptions.set(data: GameOptionsData(data: GameOptions()))
                        }
                            .optionFocus(.reset, current: focus.current, shown: gamepad.showsFocus)
                        Spacer()
                        ProminentButton("Auto configure", systemImage: "wand.and.sparkles", isLoading: isLoading) {
                            Task { await runAutoconfigure() }
                        }
                            .optionFocus(.autoconfigure, current: focus.current, shown: gamepad.showsFocus)
                    }.padding(.top)

                    if fix.entry != nil || fix.state != .noFix {
                        Divider()
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fix.summary).font(.callout)
                                if let detail = fix.detail {
                                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                                }
                                if let blocked = fix.blocked {
                                    Text(blocked).font(.footnote).foregroundStyle(.orange)
                                }
                                if let error = fix.lastError ?? autoconfigError {
                                    Text(error).font(.footnote).foregroundStyle(.red)
                                }
                                // Never nil: the catalogue emits "" for the
                                // thirteen titles that run on either
                                // generation, so `!= nil` showed this on all
                                // of them.
                                if fix.entry?.gptk?.isEmpty == false, let warning = fix.scopeWarning {
                                    Text(warning).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if fix.canRemove {
                                Button("Remove") { Task { await fix.remove() } }
                            }
                        }.padding(.top, 4)
                    }

                    if let route = Uninstall.route(for: current) {
                        Divider()
                        uninstallRow(route, game: current)
                    }
                }
                
            }
            .controlSize(.small)
            .formStyle(.columns)
            .toggleStyle(.switch)
        }
        .padding()
        .confirmationDialog("Install the video fix?",
                            isPresented: $confirmingInstall,
                            titleVisibility: .visible) {
            Button("Install") { Task { await fix.install() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let entry = fix.entry, let folder = gameFolder {
                Text("""
                \(entry.name)
                \(entry.why)

                \(MGVFRunner.redacted(entry.carrierPath(inGameFolder: folder))) is renamed to \(entry.keptAs), and \(entry.files.joined(separator: ", ")) takes its place.\(entry.writesRegistry ? "\nA DLL override is written to the bottle, for this game only." : "")

                Verifying the game's files in Steam undoes this. It can be put back from here.
                """)
            }
        }
        .confirmationDialog("Uninstall \(current.name)?",
                            isPresented: $confirmingUninstall,
                            titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { runUninstall(for: current) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Uninstall.warning(for: current))
        }
        .task(id: gameFolder) {
                    await fix.load(folder: gameFolder,
                                   bottles: appGlobals.configuredBottles,
                                   hasGame: game != nil)
                }
        .onChange(of: focus.current) { _, control in
            guard let control else { return }
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(control, anchor: .center) }
        }
        // The list of reachable controls follows the panel: a toggle that
        // hides a section changes what down means.
        .onChange(of: panelState(current)) { _, state in focus.update(for: state) }
        .onAppear { takeGamepad(current) }
        .onDisappear { releaseGamepad() }
    }
            } else {
            EmptyView()
        }
    }
    
    @MainActor

    // MARK: - The controller

    /// What the panel is showing, so the reachable list is the visible one.
    private func panelState(_ current: Game) -> OptionPanelState {
        OptionPanelState(isNative: current.isNative,
                         backend: gameOptions.cxGraphicsBackend,
                         hudEnabled: gameOptions.mtlHudEnabled,
                         metalFXOn: gameOptions.dxmtMetalFXSpatial,
                         dxmtCapOn: gameOptions.dxmtPreferredMaxFrameRate > 20,
                         d3dCapOn: gameOptions.d3dMaxFPS > 20,
                         osVersion: Int(OSVersion),
                         armShown: showArmSupport)
    }

    /// Take the pad from the grid. Given back in `releaseGamepad`; the grid
    /// re-wires itself when the sheet goes, so nothing is left with nobody
    /// reading it.
    private func takeGamepad(_ current: Game) {
        focus.update(for: panelState(current))
        // onAppear can run more than once for this view -- its body sits in
        // a conditional SwiftUI is free to rebuild -- so a second take
        // replaces the first rather than stacking on top of it.
        if let padToken { gamepad.release(padToken) }
        padToken = gamepad.take(onMove: { direction in
            // An open popup is a column of its own: up and down walk it, and
            // nothing reaches the panel behind it until it closes.
            if var open = menu {
                open.move(direction); menu = open; return
            }
            focus.update(for: panelState(current))
            focus.selectFirstIfNeeded()
            switch direction {
            case .up, .down:
                focus.move(direction)
            case .left, .right:
                // Sideways is an adjustment, not a move: a slider goes one
                // step, a picker one entry. Nothing to the side to move to.
                guard let control = focus.current else { return }
                _ = apply(direction == .right ? .right : .left, to: control)
            }
        }, onPress: { press in
            if let open = menu {
                switch press {
                case .select: pick(open.currentID, for: open.control); menu = nil
                case .back:   menu = nil
                case .options: break
                }
                return
            }
            switch press {
            case .back:
                // Closing saves, through the sheet's one closing path. There
                // is no "keep changes?" here on purpose: Undo, before B, is
                // how to not keep them.
                dismiss()
            case .select:
                guard let control = focus.current else { focus.selectFirstIfNeeded(); return }
                switch apply(.select, to: control) {
                case .activate(let button): activate(button)
                case .openMenu(let popup):  openMenu(popup)
                case .changed, .nothing:    break
                }
            case .options:
                break
            }
        })
    }

    /// Give the pad back. Only this view's own entry goes; whoever was
    /// listening underneath is what remains.
    private func releaseGamepad() {
        if let padToken { gamepad.release(padToken) }
        padToken = nil
        focus.clear()
    }

    /// What a press does to the form. Toggles flip on A; pickers cycle on A
    /// or sideways; sliders step sideways; buttons are handed back to be run.
    private func apply(_ adjust: OptionFocus.Adjust, to control: OptionControl) -> OptionFocus.Outcome {
        let forward = adjust != .left
        func flip(_ path: ReferenceWritableKeyPath<GameOptions, Bool>) -> OptionFocus.Outcome {
            guard adjust == .select else { return .nothing }
            gameOptions[keyPath: path].toggle(); return .changed
        }
        func step(_ path: ReferenceWritableKeyPath<GameOptions, Double>,
                  by size: Double, in range: ClosedRange<Double>) -> OptionFocus.Outcome {
            guard adjust != .select else { return .nothing }
            gameOptions[keyPath: path] = OptionAdjust.nudge(gameOptions[keyPath: path], by: size,
                                                             in: range, forward: forward)
            return .changed
        }
        if adjust == .select, control.opensMenu { return .openMenu(control) }
        switch control {
        case .backend:
            gameOptions.cxGraphicsBackend = OptionAdjust.cycle(gameOptions.cxGraphicsBackend,
                                                                in: OptionAdjust.backends, forward: forward)
            return .changed
        case .x87:          return flip(\.x87PatchEnabled)
        case .mtlHud:       return flip(\.mtlHudEnabled)
        case .advertiseAVX: return flip(\.advertiseAVX)
        case .msync:        return flip(\.wineMSync)
        case .sdl:          return flip(\.enableSDL)
        case .hidraw:       return flip(\.disableHidraw)
        case .ue4Hack:      return flip(\.ue4Hack)
        case .mvkArgBuff:   return flip(\.mvkArgBuff)
        case .dxmtMetalFX:  return flip(\.dxmtMetalFXSpatial)
        case .d3dMtl4:      return flip(\.d3dMtl4Enabled)
        case .dxmtCap:
            guard adjust == .select else { return .nothing }
            gameOptions.dxmtPreferredMaxFrameRate = OptionAdjust.cap(!(gameOptions.dxmtPreferredMaxFrameRate > 20))
            return .changed
        case .d3dCap:
            guard adjust == .select else { return .nothing }
            gameOptions.d3dMaxFPS = OptionAdjust.cap(!(gameOptions.d3dMaxFPS > 20))
            return .changed
        case .dxmtMaxFPS:   return step(\.dxmtPreferredMaxFrameRate, by: OptionAdjust.fpsStep, in: 19...240)
        case .d3dMaxFPS:    return step(\.d3dMaxFPS, by: OptionAdjust.fpsStep, in: 19...240)
        case .dxmtUpscale:  return step(\.dxmtMetalSpatialUpscaleFactor, by: OptionAdjust.upscaleStep, in: 1.0...2.0)
        case .hudOpacity:   return step(\.mtlHudOpacity, by: OptionAdjust.opacityStep, in: 0.1...1.0)
        case .hudDetail:
            gameOptions.mtlHudDetail = OptionAdjust.cycle(gameOptions.mtlHudDetail,
                                                          in: MetalHudDetail.allCases.map(\.rawValue), forward: forward)
            return .changed
        case .hudAlignment:
            gameOptions.mtlHudAlignment = OptionAdjust.cycle(gameOptions.mtlHudAlignment,
                                                             in: MetalHudAlignment.allCases.map(\.rawValue), forward: forward)
            return .changed
        case .save, .undo, .reset, .autoconfigure:
            return adjust == .select ? .activate(control) : .nothing
        }
    }

    /// The same list the mouse gets, for the control that was pressed.
    private func openMenu(_ control: OptionControl) {
        switch control {
        case .backend:
            menu = MenuFocus(control: control,
                             options: cxGraphicsBackend.map { (id: $0.id, label: $0.label) },
                             selected: gameOptions.cxGraphicsBackend)
        case .hudAlignment:
            menu = MenuFocus(control: control,
                             options: MetalHudAlignment.allCases.map { corner in (id: corner.rawValue, label: corner.label) },
                             selected: gameOptions.mtlHudAlignment)
        default:
            break
        }
    }

    private func pick(_ id: String, for control: OptionControl) {
        switch control {
        case .backend:      gameOptions.cxGraphicsBackend = id
        case .hudAlignment: gameOptions.mtlHudAlignment = id
        default: break
        }
    }

    /// The popup, drawn as one: a column beside the control, highlighted row
    /// and all. Rows are buttons, so the mouse can pick from it too, and a
    /// hover moves the highlight so both devices agree on what a press picks.
    @ViewBuilder
    private func menuPopover(for control: OptionControl) -> some View {
        if let open = menu, open.control == control {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(zip(open.ids, open.labels)), id: \.0) { id, label in
                    Button {
                        pick(id, for: control); menu = nil
                    } label: {
                        HStack {
                            Text(label)
                            Spacer(minLength: 12)
                            if id == open.currentID { Image(systemName: "checkmark").font(.footnote) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .frame(minWidth: 150, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(id == open.currentID ? Color.accentColor.opacity(0.35) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in if inside, var m = menu { m.highlight(id); menu = m } }
                }
            }
            .padding(6)
        }
    }

    /// The buttons, run from the pad exactly as from a click.
    private func activate(_ control: OptionControl) {
        switch control {
        case .save:          session.save(gameOptions)
        case .undo:          session.undo(into: gameOptions)
        case .reset:         gameOptions.set(data: GameOptionsData(data: GameOptions()))
        case .autoconfigure: Task { await runAutoconfigure() }
        default: break
        }
    }

    /// One place, for the button and for the pad. It configures, and if the
    /// title still needs its fix it asks to put it on -- the asking is not
    /// ceremony: that step renames a file in the user's game folder.
    /// Removing a game belongs to the store that installed it -- see
    /// `Uninstall` for why. This only knocks: the client asks for
    /// confirmation in its own window and does the removal itself.
    ///
    /// Deliberately outside the pad's focus ring. While this panel is up the
    /// controller belongs to it, and the confirmation this opens is a dialog
    /// the pad cannot answer: a control reachable with the stick that leads
    /// somewhere the stick cannot leave. It is a rare, destructive step, and
    /// the pointer is the way into it.
    private func uninstallRow(_ route: Uninstall.Route, game: Game) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Uninstall").font(.callout)
                Text(Uninstall.explanation(route)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button(Uninstall.buttonTitle(route), role: .destructive) {
                if Uninstall.needsConfirmation(route) {
                    confirmingUninstall = true
                } else {
                    runUninstall(for: game)
                }
            }
        }.padding(.top, 4)
    }

    private func runUninstall(for game: Game) {
        guard let route = Uninstall.route(for: game) else { return }
        switch route {
        case .steam(let appID):
            let steamX86AppPath = appGlobals.windowsSteamFolder?
                .appendingPathComponent("Steam.exe").path(percentEncoded: false)
                ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
            console.log("uninstall: asking Steam for \(game.name) (\(appID))")
            uninstallSteamGame(id: appID, cxAppPath: appGlobals.cxAppPath,
                               selectedBottle: appGlobals.selectedBottle,
                               SteamX86AppPath: steamX86AppPath)
        case .epic(let uri):
            guard let epic = EpicLaunch.target(settings: StoreConfig.settings(for: .epic),
                                               selectedBottle: appGlobals.selectedBottle) else {
                console.error("uninstall: no bottle configured for the Epic launcher")
                return
            }
            console.log("uninstall: opening the Epic library for \(game.name)")
            openEpic(cxAppPath: appGlobals.cxAppPath, bottle: epic.bottle,
                     clientPath: epic.clientPath, uri: uri)
        }
    }

    private func runAutoconfigure() async {
        isLoading = true
        do {
            try await autoconfig()
        } catch {
            autoconfigError = error.localizedDescription
        }
        isLoading = false
        if fix.canInstall { confirmingInstall = true }
    }

    private func autoconfig() async throws {
        // Per game, as the fixes application already works: the catalogue is
        // consulted for THIS title, so the button reports what it needs rather
        // than only filling in the form.
        await fix.load(folder: gameFolder,
                       bottles: appGlobals.configuredBottles,
                       hasGame: game != nil)
        // The remote settings first, the measured catalogue second.
        //
        // importAutoConfig overwrites every non-nil field, so whichever runs
        // last wins. Until the catalogue carried a backend the measured branch
        // returned nothing and the order did not matter; now it does, and a
        // measurement made on this hardware should not lose to a server.
        if let id = game?.steamAppID {
            if let autoconfigData = try await api.fetchAutoConfig(steamID: String(id)) {
                gameOptions.importAutoConfig(data: autoconfigData)
            }
        }
        if let recommended = fix.recommendedOptions {
            gameOptions.importAutoConfig(data: recommended)
        }
    }
}

#Preview {
    @State @Previewable var game: Game? = .mock
    @StateObject @Previewable var gameOptions: GameOptions = GameOptions(cxGraphicsBackend: "dxmt")
    
    @StateObject @Previewable var appGlobals: AppGlobals = AppGlobals()

    @StateObject @Previewable var libraryPageGlobals: LibraryPageGlobals = LibraryPageGlobals()

    GameOptionsView(game: $game)
        .environmentObject(gameOptions)
        .environmentObject(appGlobals)
        .environmentObject(libraryPageGlobals)

}
