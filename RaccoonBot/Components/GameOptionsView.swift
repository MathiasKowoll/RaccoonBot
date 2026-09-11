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

    /// The pending write. One at a time: every edit cancels the last one and
    /// starts it again, so a slider dragged across its range is one write and
    /// not one per frame. See `Autosave` for the rule it is following.
    @State private var autosaveTask: Task<Void, Never>?

    /// What the rumble test last said, and whether that was a complaint.
    /// Never cleared back to nil: the panel keeps the last answer on screen,
    /// because "it did nothing" is exactly the reading this button exists to
    /// prevent.
    @State private var rumbleSaid: String?
    @State private var rumbleFailed = false
    @State private var rumbleRunning = false

    /// One width for every control in the controller section, so that
    /// choosing a longer entry in a picker moves nothing beside it, and the
    /// width for the sentence under the test button.
    private static let controllerControlWidth: CGFloat = 330
    private static let controllerSentenceWidth: CGFloat = 560

    /// What the sentence under the test button says before it has been
    /// pressed. It states the two things somebody would otherwise have to
    /// guess: that this reaches the pad directly, and that it therefore says
    /// nothing about what a game will feel.
    private static let rumbleInvitation =
        "Buzzes the attached pad now, through IOKit, with the choice and the percentage above. It does not go near the bottle, so it says what the setting feels like and not whether this engine would apply it to a game."

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

    /// The stored vibration choice, folded through the enum. A raw value this
    /// build does not know reads as the default here as it does everywhere
    /// else, so the slider cannot be hidden or shown by a leftover.
    private var vibrationChoice: DualSenseVibration {
        DualSenseVibration(rawValue: gameOptions.dualSenseVibration) ?? .byDefault
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
                                    // Everything about the pad used to be here,
                                    // under MSync. It has its own section now:
                                    // five settings that describe a physical
                                    // device rather than a rendering choice do
                                    // not fit in a column of toggles, and the
                                    // one that broke it was a picker whose
                                    // label rendered as "Vibra...".
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
                    if !current.isNative {
                        Divider()
                        // The pad's own section, in the idiom the DXMT and HUD
                        // sections already use. Five settings and a button
                        // that describe a physical device rather than a
                        // rendering choice, and two of them are pickers whose
                        // entries are sentences -- "Wired standard DualSense"
                        // has nowhere to go in a column sized for the word
                        // "MSync".
                        //
                        // Every control here is pinned to one width. A picker
                        // that is as wide as whatever is selected moves its
                        // neighbours every time the choice changes, which is
                        // what this panel was doing; the strength slider keeps
                        // its row whether or not the choice uses one, for the
                        // same reason. Room is spent rather than saved: the
                        // sheet is wider than it was, and it is wider in the
                        // one place the width is decided.
                        Section("Controller") {
                            Toggle("Enable SDL", isOn: $gameOptions.enableSDL)
                                .optionFocus(.sdl, current: focus.current, shown: gamepad.showsFocus)
                            Toggle("Disable Hidraw", isOn: $gameOptions.disableHidraw)
                                .optionFocus(.hidraw, current: focus.current, shown: gamepad.showsFocus)
                            DropDown(options: DualSensePresentation.dropdownOptions,
                                     label: "Pad seen as",
                                     value: $gameOptions.dualSensePresentation)
                                .pickerStyle(.menu)
                                .frame(width: Self.controllerControlWidth, alignment: .leading)
                                .help("What a DualSense looks like to this game. Needs the engine controller set built with the USB-emulation patch, in Options. It applies when the pad next arrives, not at once: start with Steam closed, or reconnect the pad afterwards. For a title whose own Sony library only accepts a wired pad -- and Steam Input must be off for that title, or Steam hands the game an Xbox pad whatever this says. Both DualSense models are served, so an Edge asked to look like a plain DualSense is created as one. The choice is written whether or not a pad is attached at launch, so it is already there when the pad comes back; the console says what each pad actually got.")
                                .optionFocus(.padSeenAs, current: focus.current, shown: gamepad.showsFocus)
                                .popover(isPresented: Binding(get: { menu?.control == .padSeenAs },
                                                              set: { if !$0 { menu = nil } }),
                                         arrowEdge: .bottom) { menuPopover(for: .padSeenAs) }
                            // One control for one idea: which way the pad is
                            // asked to buzz. The percentage below is the
                            // detail two of the three answers need.
                            DropDown(options: DualSenseVibration.dropdownOptions,
                                     label: "Vibration",
                                     value: $gameOptions.dualSenseVibration)
                                .pickerStyle(.menu)
                                .frame(width: Self.controllerControlWidth, alignment: .leading)
                                .help("What this game's rumble does. A preference and not a repair -- the default sends every packet exactly as the game wrote it. \"Stronger motors\" rewrites the game's choice of the haptic vibration path to the legacy motors: a title measured here asks for the full 255 and still feels soft, and on a six-pulse ladder the legacy motors at the same value felt stronger to one person here, which is a hand and not a meter. \"Custom strength\" scales what the game asks without changing the path it chose, and at 0% it silences the pad for this title whatever the game asks, including a game with no setting of its own. The percentage saturates at the top of the range, so a game already asking for everything cannot be made louder. It needs the engine controller set from Options, applies to a DualSense on either transport, and takes effect when the pad next arrives: start with Steam closed, or reconnect the pad.")
                                .optionFocus(.vibration, current: focus.current, shown: gamepad.showsFocus)
                                .popover(isPresented: Binding(get: { menu?.control == .vibration },
                                                              set: { if !$0 { menu = nil } }),
                                         arrowEdge: .bottom) { menuPopover(for: .vibration) }
                            // Held in place rather than removed. The strength
                            // belongs to "Custom" alone -- the other two
                            // choices are complete sentences without a number,
                            // and one under "As the game asks" would
                            // contradict its own name -- so the row is faded
                            // and dead there. Taking it away instead moved
                            // every section below it each time the picker
                            // changed. The controller's own list drops it
                            // while it is unusable, so a pad cannot land on it.
                            VStack(alignment: .leading, spacing: 2) {
                                // 0 is the end of the slider and it is not
                                // "no vibration at 0%": it is off, and it says
                                // so, because a number alone would read as a
                                // very quiet pad rather than a silent one.
                                Text(gameOptions.dualSenseVibrationGain == 0 ? "Rumble strength: off"
                                     : "Rumble strength \(Int(gameOptions.dualSenseVibrationGain))%")
                                Slider(value: $gameOptions.dualSenseVibrationGain,
                                       in: DualSenseVibration.gainRange,
                                       step: OptionAdjust.gainStep)
                                    .optionFocus(.vibrationGain, current: focus.current, shown: gamepad.showsFocus)
                            }
                            .frame(width: Self.controllerControlWidth, alignment: .leading)
                            .opacity(vibrationChoice.usesGain ? 1 : 0)
                            .disabled(!vibrationChoice.usesGain)
                            .accessibilityHidden(!vibrationChoice.usesGain)
                            // Off unless a title asks, and the help says why
                            // rather than only what. This one changes what the
                            // game SEES rather than how the pad behaves, and it
                            // can take the pad away from a game that was
                            // perfectly happy -- so the caution belongs on the
                            // control, not in a release note nobody reads.
                            Toggle("Rumble through XInput", isOn: $gameOptions.xinputRumble)
                                .help("For a game that has a controller but no vibration. Some titles read the pad directly and rumble it themselves; others only know how to rumble through XInput, and a DualSense is not an XInput device, so they stay silent. This offers the pad's motors to XInput as a small device of its own, beside the pad -- the pad itself is not replaced, wrapped or hidden, so its adaptive triggers, touchpad and PlayStation glyphs are exactly as they were. TRY IT ONLY WHERE A GAME DOES NOT RUMBLE. A game that reads XInput for its INPUT can take that little device for the controller and stop seeing the pad at all: one title measured here lost the pad entirely with this on and was perfectly fine with it off. It also costs a few percent of the frame time, which shows up only in a game with no headroom left -- one measured here dropped 3 to 5 fps at 60 and none at all with a 50 fps cap. Needs the engine controller set from Options, and takes effect when the pad next arrives: start with Steam closed, or reconnect the pad.")
                                .optionFocus(.xinputRumble, current: focus.current, shown: gamepad.showsFocus)
                            // Felt, not imagined. This is the one control in
                            // the panel that does something to the hardware
                            // now: it writes the pad's own report through
                            // IOKit, with the choice and the percentage on
                            // screen, and never touches the bottle -- so it
                            // says nothing about whether the engine carries
                            // the patch that would apply the same choice to a
                            // game. See DualSenseRumble for what goes out.
                            Button(rumbleRunning ? "Buzzing..." : "Test rumble now") { runRumbleTest() }
                                .disabled(rumbleRunning)
                                .optionFocus(.rumbleTest, current: focus.current, shown: gamepad.showsFocus)
                            // A diagnostic, and it sits beside the pad because
                            // that is what it traces. Off by default and never
                            // suggested: a trace is hundreds of megabytes and
                            // costs the game frames of its own, which is the
                            // one thing this section spent a day removing.
                            Toggle("Keep a HID trace", isOn: $gameOptions.hidTraceEnabled)
                                .help("Keeps everything winebus says about the controller for this launch, in a dated file on the Desktop. For diagnosing a pad that does not rumble, is not seen, or costs frames -- read it with MacGameVideoFix's diagnostics/read-hid-trace.sh. It slows the game while it runs and the file grows to hundreds of megabytes, so turn it off again afterwards.")
                                .optionFocus(.hidTrace, current: focus.current, shown: gamepad.showsFocus)
                            // Always there, three lines tall, whether it is
                            // holding the invitation or the answer: a sentence
                            // that appears when the button is pressed would
                            // move the panel under the hand that pressed it.
                            Text(rumbleSaid ?? Self.rumbleInvitation)
                                .font(.footnote)
                                .foregroundStyle(rumbleFailed ? .orange : .secondary)
                                .lineLimit(3, reservesSpace: true)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: Self.controllerSentenceWidth, alignment: .leading)
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
                        // "Saved", always, because it always is: an edit is
                        // committed a quarter of a second after it is made,
                        // and the panel no longer has an unsaved state worth
                        // naming. A title that flipped between two words for
                        // a fraction of a second on every keystroke would be
                        // reporting the timer rather than the file.
                        //
                        // It stays a button, and pressing it still writes,
                        // because that is what somebody about to press Auto
                        // configure wants: the file now, not in a moment. It
                        // cancels the pending write first, so the two cannot
                        // both fire.
                        Button("Saved") {
                            console.log("saving")
                            commitNow()
                        }
                        .buttonStyle(.borderedProminent)
                            .optionFocus(.save, current: focus.current, shown: gamepad.showsFocus)
                        // Undo goes back to what the file held when this panel
                        // opened -- not to the last write, which autosave has
                        // been moving all along. It is still the escape hatch
                        // before closing, and it is still a state that cannot
                        // be wrong; the undone form is then committed like any
                        // other edit. Reset, beside it, goes to factory
                        // defaults -- a different and much larger step, left
                        // as it was.
                        Button("Undo") {
                            console.log("undoing")
                            session.undo(into: gameOptions)
                        }
                        .disabled(!session.canUndo(gameOptions))
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
        // The whole edited record, not one field and not the dirty flag: the
        // flag is already true on the second edit and would never fire again,
        // and a per-field list is a list somebody adding a control forgets to
        // join. GameOptionsData is what the file holds and what "different"
        // means, so comparing it is comparing the thing that matters.
        .onChange(of: GameOptionsData(data: gameOptions)) { _, _ in scheduleAutosave() }
        .onAppear { takeGamepad(current) }
        .onDisappear {
            releaseGamepad()
            // Dropped, not awaited. The sheet writes on the way out through
            // `closing`, so an edit made in the last quarter-second is in the
            // file either way; leaving the task alive would be a second writer
            // for a panel that no longer exists.
            autosaveTask?.cancel()
            autosaveTask = nil
        }
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
                         vibrationGainShown: vibrationChoice.usesGain,
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
        padToken = gamepad.take(inSheet: true, onMove: { direction in
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
        case .padSeenAs:
            gameOptions.dualSensePresentation = OptionAdjust.cycle(gameOptions.dualSensePresentation,
                                                                    in: DualSensePresentation.allCases.map(\.rawValue),
                                                                    forward: forward)
            return .changed
        case .vibration:
            gameOptions.dualSenseVibration = OptionAdjust.cycle(gameOptions.dualSenseVibration,
                                                                in: DualSenseVibration.allCases.map(\.rawValue),
                                                                forward: forward)
            return .changed
        case .vibrationGain:
            return step(\.dualSenseVibrationGain, by: OptionAdjust.gainStep, in: DualSenseVibration.gainRange)
        case .x87:          return flip(\.x87PatchEnabled)
        case .mtlHud:       return flip(\.mtlHudEnabled)
        case .advertiseAVX: return flip(\.advertiseAVX)
        case .msync:        return flip(\.wineMSync)
        case .hidTrace:     return flip(\.hidTraceEnabled)
        case .sdl:          return flip(\.enableSDL)
        case .hidraw:       return flip(\.disableHidraw)
        case .xinputRumble: return flip(\.xinputRumble)
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
        case .save, .undo, .reset, .autoconfigure, .rumbleTest:
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
        case .padSeenAs:
            menu = MenuFocus(control: control,
                             options: DualSensePresentation.dropdownOptions,
                             selected: gameOptions.dualSensePresentation)
        case .vibration:
            menu = MenuFocus(control: control,
                             options: DualSenseVibration.dropdownOptions,
                             selected: gameOptions.dualSenseVibration)
        default:
            break
        }
    }

    private func pick(_ id: String, for control: OptionControl) {
        switch control {
        case .backend:      gameOptions.cxGraphicsBackend = id
        case .hudAlignment: gameOptions.mtlHudAlignment = id
        case .padSeenAs:    gameOptions.dualSensePresentation = id
        case .vibration:    gameOptions.dualSenseVibration = id
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
        case .save:          commitNow()
        case .undo:          session.undo(into: gameOptions)
        case .reset:         gameOptions.set(data: GameOptionsData(data: GameOptions()))
        case .autoconfigure: Task { await runAutoconfigure() }
        case .rumbleTest:    runRumbleTest()
        default: break
        }
    }

    // MARK: - Saving as it is edited

    /// An edit happened. The write is put off until the edits stop, which is
    /// what makes dragging a slider one write; `Autosave` says why.
    ///
    /// The rule about what deserves a write is not repeated here -- the
    /// session asks `Autosave` when the moment comes, so a form put back to
    /// where it was during the pause writes nothing at all.
    @MainActor
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: Autosave.quietPeriod)
            guard !Task.isCancelled else { return }
            if session.autosave(gameOptions) { console.log("options saved") }
        }
    }

    /// Write it now, whatever the timer was going to do. The Save button and
    /// the pad's own press both come here.
    @MainActor
    private func commitNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        session.autosave(gameOptions)
    }

    // MARK: - The rumble test

    /// Buzz the pad with what is on screen, and say what happened.
    ///
    /// Off the main thread, because the pulse is a send, a wait and a second
    /// send: doing that here would freeze the panel for the length of it. The
    /// choice and the percentage are read before leaving, so what is felt is
    /// what was on screen when the button was pressed.
    @MainActor
    private func runRumbleTest() {
        guard !rumbleRunning else { return }
        rumbleRunning = true
        let choice = vibrationChoice
        let percent = gameOptions.dualSenseVibrationGain
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                DualSenseRumble.pulse(vibration: choice, percent: percent)
            }.value
            rumbleSaid = outcome.message
            rumbleFailed = outcome.isProblem
            rumbleRunning = false
            if outcome.isProblem { console.error("rumble test: \(outcome.message)") }
            else { console.log("rumble test: \(outcome.message)") }
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
        case .steamOnMac(let appID):
            // The Mac's own Steam, through the system handler -- not the one in
            // the bottle, which never installed this and must not be asked to
            // remove it.
            guard let url = URL(string: "steam://uninstall/\(appID)") else { return }
            console.log("uninstall: asking the Mac Steam for \(game.name) (\(appID))")
            NSWorkspace.shared.open(url)
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
