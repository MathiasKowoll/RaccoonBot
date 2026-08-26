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
    /// Needed to tell the user whether an ARM bottle has been chosen at all.
    /// Provided by the sheet that presents this view.
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @StateObject private var fix = MGVFCoordinator()
    @State private var confirmingInstall = false
    @State private var autoconfigError: String?
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
        let gameOptKey = namespacedKey("GameOptions", id)
        VStack (alignment: .leading, spacing: 5){
            Text("id:\(id)").font(Font.footnote).foregroundStyle(.procyonBrightGray)
            Form {
                VStack(alignment: .leading, spacing: 20) {
                    Section("Generic options") {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .trailing){
                                if !current.isNative {
                                    DropDown(options: cxGraphicsBackend, label: "Graphics Backend", value: $gameOptions.cxGraphicsBackend)
                                }
                                Divider()
                                TextField("Game arguments", text: $gameOptions.gameArguments)
                                TextField("Env variables", text: $gameOptions.envVariables)
                                if !current.isNative {
                                    Divider()
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
                                    Divider()
                                    Text("32Bits options")
                                    Toggle("Reduced x87 precision", isOn: $gameOptions.x87PatchEnabled)
                                    Toggle("Use DX9", isOn: $gameOptions.dx9PatchEnabled).onChange(of: gameOptions.dx9PatchEnabled) { oldValue, newValue in
                                        if(newValue == true) {
                                            gameOptions.cxGraphicsBackend = "wine"
                                        }
                                    }  // WINEDLLOVERRIDES=d3d9=n,b;d3d8=n,b has been removed
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Toggle("Metal HUD", isOn: $gameOptions.mtlHudEnabled)
                                Toggle("Advertise AVX", isOn: $gameOptions.advertiseAVX)
                                if !current.isNative {
                                    Toggle("MSync", isOn: $gameOptions.wineMSync)
                                    Toggle("Enable SDL", isOn: $gameOptions.enableSDL)
                                    Toggle("Disable Hidraw", isOn: $gameOptions.disableHidraw)
                                    Divider()
                                    Text("Vulkan options")
                                    Toggle("Enable UE4 Hack", isOn: $gameOptions.ue4Hack)
                                    Toggle("MTL arg. buffers", isOn: $gameOptions.mvkArgBuff)
                                    DropDown(options: cxVulkanBackend, label: "VK lib", value: $gameOptions.vulkanLib)
                                    .pickerStyle(.menu)
                                }
                            }
                        }
                    }
                    if(gameOptions.cxGraphicsBackend == "dxmt") {
                        Divider()
                        Section("DXMT Options") {
                            VStack{
                                Text(localizedString(forKey: "preferredMaxFrameRate", value: preferredMaxFrameRate))
                                Slider(
                                    value: $gameOptions.dxmtPreferredMaxFrameRate,
                                    in: 19...240,
                                    step: 1.0
                                )
                                .help(localizedString(forKey: "preferredMaxFrameRateHelp"))
                            }
                            
                            Toggle("metalFXSpatial", isOn: $gameOptions.dxmtMetalFXSpatial)
                                .help(localizedString(forKey: "metalFXSpatialHelp"))
                                .onChange(of: gameOptions.dxmtMetalFXSpatial) { oldValue, newValue in
                                    if (!newValue) {
                                        $gameOptions.dxmtMetalSpatialUpscaleFactor.wrappedValue = 1.0
                                    }
                                }
                            
                            if (gameOptions.dxmtMetalFXSpatial) {
                                VStack {
                                    Text(localizedString(forKey:"metalSpatialUpscaleFactor", value: String($gameOptions.dxmtMetalSpatialUpscaleFactor.wrappedValue)))
                                    Slider(
                                        value: $gameOptions.dxmtMetalSpatialUpscaleFactor,
                                        in: 1.0...2.0,
                                        step: 0.125
                                    )
                                    .help(localizedString(forKey: "metalFXSpatialHelp"))
                                }
                            }
                        }
                    }
                    if(gameOptions.cxGraphicsBackend == "d3dmetal4") {
                        Divider()
                        Section("D3DMetal Options") {
                            Toggle("Metal 4 Backend", isOn: $gameOptions.d3dMtl4Enabled)
                                .help(localizedString(forKey: "metal4Backend"))
                                .disabled(OSVersion < 27)
                                .opacity(OSVersion < 27 ? 0.5 : 1.0)
                            VStack{
                                Text(localizedString(forKey: "preferredMaxFrameRate", value: d3dMaxFPS))
                                Slider(
                                    value: $gameOptions.d3dMaxFPS,
                                    in: 19...240,
                                    step: 1.0
                                )
                                .help(localizedString(forKey: "preferredMaxFrameRateHelp"))
                            }
                        }
                    }
                    HStack {
                        Button("Save settings") {
                            console.log("saving")
                            persistUsrDefData(key: gameOptKey, data: GameOptionsData(data: gameOptions))
                        }.buttonStyle(.borderedProminent)
                        //                        Button("Undo") {
                        //                            console.log("resetting")
                        //                            if let data: GameOptionsData = readUsrDefData(key: gameOptKey) {
                        //                                self.gameOptions.set(data: data)
                        //                            }
                        //                        }
                        Button("Reset") {
                            console.log("resetting")
                            gameOptions.set(data: GameOptionsData(data: GameOptions()))
                        }
                        Spacer()
                        ProminentButton("Auto configure", systemImage: "wand.and.sparkles", isLoading: isLoading) {
                            Task {
                                isLoading = true
                                do {
                                    try await autoconfig()
                                } catch {
                                    autoconfigError = error.localizedDescription
                                }
                                isLoading = false
                                // One button: it configures, and if the title
                                // still needs its fix it asks to put it on.
                                // The asking is not ceremony -- this is the
                                // step that renames a file in the user's game
                                // folder, and it says which one before it does.
                                if fix.canInstall { confirmingInstall = true }
                            }
                        }
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
        .task(id: gameFolder) { await fix.load(folder: gameFolder, hasGame: game != nil) }
            } else {
            EmptyView()
        }
    }
    
    @MainActor
    private func autoconfig() async throws {
        // Per game, as the fixes application already works: the catalogue is
        // consulted for THIS title, so the button reports what it needs rather
        // than only filling in the form.
        await fix.load(folder: gameFolder, hasGame: game != nil)
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
