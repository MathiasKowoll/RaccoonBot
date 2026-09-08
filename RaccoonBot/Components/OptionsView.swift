//
//  Options.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 31/01/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct OptionsView: View {
    @State var bottles: [URL] = []
    @State var progress: Double = 0
    @State var progressLabel = "Processing..."
    @State var downloading: Bool = false
    @State var shouldShowBottleSelector: Bool = false
    /// Which store's settings are on screen. One panel, switched, rather than
    /// every store's settings stacked -- with three stores that becomes a page
    /// nobody reads to the bottom of.
    @State private var configuringStore: Store = .steam
    @State private var storeBottle: String = ""



    /// What the fix row says. The counting and the wording live in
    /// `FixSummary`, where they can be tested without a view.
    private func fixSummary(_ targets: [PatchAll.Target]) -> Text {
        guard !targets.isEmpty else { return Text(FixSummary.allWell) }
        let needs = targets.map { fixLibrary.need(folder: $0.folder) }
        return Text(FixSummary.sentence(missing: needs.filter { $0 == .missing }.count,
                                        outdated: needs.filter { $0 == .outdated }.count,
                                        unverified: needs.filter { $0 == .unverified }.count))
    }

    /// Bottles that can actually serve a game marked to run on ARM: ARM
    /// architecture AND an engine that ships FEX. An ARM bottle on CrossOver 26
    /// runs ARM-native Windows binaries only, so listing it here would offer
    /// the one bottle that cannot run the game.
    private var armBottles: [BottleInfo] {
        bottles.compactMap { bottleInfo($0) }.filter { $0.isARM && $0.canRunX86 }
    }
    @State var creatingBottle: Bool = false
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject private var gamepad: GamepadInput
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @MainActor var load: @Sendable () async -> Void
    @State private var showEpicImport = false
    @State var createBtlPrc: Process?
    @State var cleard3dmCacheStatus: DeleteStatus = DeleteStatus.idle
    /// Read once, off the main thread, and remembered. NEVER computed in the
    /// body: reading it runs otool and blocks on waitUntilExit(), and SwiftUI
    /// evaluates a body repeatedly and re-entrantly. Doing that inside the
    /// body getter segfaulted the application on opening this screen.
    @State private var gstStatus: GStreamerStatus?
    @StateObject private var patchAll = PatchAll()
    @StateObject private var fixLibrary = MGVFLibrary.shared
    /// The controller-bus set: what is wanted, what the engine holds, and
    /// the script's refusal when it would not write. Read off the main actor
    /// like `gstStatus`, for the same reason.
    @StateObject private var controllerBus = ControllerBusSwitch()
    
    var body: some View {
        Modal(
            "Options",
            showModal: $libraryPageGlobals.showOptions,
        ) {
            VStack (alignment: .leading){
                // Shown before the button that uses it, because this is the
                // value the copy is made with and it decides which bottles the
                // engine will ever see.
                // One row: where the bottles live, and which engine runs them.
                // Two short buttons, and the sheet is wide enough for both.
                HStack(alignment: .center, spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Bottles in").font(.footnote)
                        Button(URL(fileURLWithPath: appGlobals.bottlesRoot).lastPathComponent) {
                            if let picked = openFolderSelectorPanel(
                                initialDirectory: URL(fileURLWithPath: appGlobals.bottlesRoot),
                                title: "Where RaccoonBot keeps its bottles") {
                                let path = picked.path(percentEncoded: false)
                                appGlobals.bottlesRoot = path
                                persistUsrDefOptionString(key: "bottlesRoot", value: path)
                            }
                        }
                        .help(appGlobals.bottlesRoot)
                    }
                    Button(URL(string: appGlobals.cxAppPath ?? "")?.lastPathComponent ?? "Select a Crossover App...") {
                        shouldShowBottleSelector = false
                        if let url = openFolderSelectorPanel(type: .application) {
                            // Refused before anything is copied, rather than after
                            // an hour of patching. One rule, in EngineLayout.
                            if let refusal = EngineLayout.refusal(for: url) {
                                console.error(refusal)
                                progressLabel = refusal
                                return
                            }
                            appGlobals.selectedBottle = ""
                            Task { @MainActor in
                                // MacGameVideoFix makes the copy now, with the
                                // script this application carries. What comes out
                                // declares itself in mgvf-origin.json; the patcher
                                // this replaced left 26.3p0.1.x and nothing else,
                                // which is how a copy's maker can be told apart.
                                downloading = true
                                let patchedAppURL: URL
                                do {
                                    patchedAppURL = try await EngineMaker.make(
                                        from: url,
                                        bottlesRoot: appGlobals.bottlesRoot,
                                        replacing: true,
                                        progress: { p, m in Task { @MainActor in progress = p; progressLabel = m } })
                                } catch {
                                    downloading = false
                                    progress = 0
                                    progressLabel = error.localizedDescription
                                    console.error(error.localizedDescription)
                                    return
                                }
                                downloading = false
                                progress = 0
                                appGlobals.cxAppPath = patchedAppURL.path(percentEncoded: false)
                                persistUsrDefOptionString(key: "cxAppPath", value: patchedAppURL.relativePath)
                                persistUsrDefOptionString(key: "cxCompleteAppPath", value: patchedAppURL.path(percentEncoded: false))
                                // The optional set goes in after the copy is made
                                // and signed -- the media set is already in, from
                                // the script's step [3/6] -- and only when the
                                // switch says so. The installer re-signs. A refusal
                                // (a bottle up, an engine the set was not built
                                // for) is a sentence in the controller-bus row,
                                // not a failed engine: the copy is made and usable.
                                if appGlobals.controllerBusEnabled {
                                    await controllerBus.apply(.install, engine: patchedAppURL.path(percentEncoded: false))
                                }
                                if !bottles.isEmpty {
                                    shouldShowBottleSelector = true
                                }
                                if (DEBUG_ENABLED) {
                                    console.saveLogs()
                                }
                            }
                            do {
                                bottles = try getAllBottles(appDir: url)
                            } catch {
                                console.error(String(reflecting: error))
                            }
                        } else {
                            if !bottles.isEmpty{
                                shouldShowBottleSelector = true
                            }
                        }
                    }
                    Spacer()
                }
                // Off means this application registers nothing on any pad, so a
                // game reading the same device through wine is its only reader.
                // A diagnostic as much as a preference: Mortal Shell 2 lost its pad
                // minutes into play, and this is how to find out whether we were
                // the second reader. The arrow keys work either way.
                Toggle("Use a game controller", isOn: $gamepad.enabled)
                    .font(.footnote)
                    .help("Off: RaccoonBot does not touch the controller at all. Arrow keys still navigate.")
                // Which bus a pad is on, told to the games: MacGameVideoFix's
                // controller-bus set, an improvement rather than a fix. No title
                // needs it, so it is a switch, and off puts CrossOver's own three
                // files back. The switch is what is wanted; the row under it is
                // what the engine holds, read from the engine, and the two are
                // allowed to disagree out loud -- see ControllerBusSwitch.
                Toggle("Tell games which bus a controller is on", isOn: $appGlobals.controllerBusEnabled)
                    .font(.footnote)
                    .disabled(controllerBus.busy || !(controllerBus.status?.isBundled ?? true))
                    .help("On: the engine carries MacGameVideoFix's winebus, setupapi and ntoskrnl, and a DualSense on Bluetooth keeps rumble, the touchpad and the PS button. Off: CrossOver's own three files are put back.")
                    .onChange(of: appGlobals.controllerBusEnabled) { _, on in
                        persistUsrDefOptionBool(key: AppGlobals.controllerBusKey, value: on)
                        Task { await controllerBus.apply(on ? .install : .remove, engine: appGlobals.cxAppPath) }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        if let bus = controllerBus.status {
                            let light = bus.light(enabled: appGlobals.controllerBusEnabled)
                            Image(systemName: light == .good ? "checkmark.circle"
                                            : light == .warning ? "exclamationmark.triangle" : "circle.dashed")
                                .foregroundStyle(light == .good ? Color.green
                                                 : light == .warning ? Color.orange : Color.secondary)
                            Text(bus.summary(enabled: appGlobals.controllerBusEnabled))
                                .font(.footnote)
                                .foregroundStyle(light == .warning ? Color.primary : Color.secondary)
                            Spacer()
                            if controllerBus.busy {
                                ProgressView().controlSize(.small)
                            } else if let action = bus.wantsAction(enabled: appGlobals.controllerBusEnabled) {
                                // The one action that makes the engine agree with
                                // the switch. Its own verb, not the switch's value:
                                // a half-installed set is removed first even with
                                // the switch on.
                                Button(action == .install ? "Install" : "Remove") {
                                    Task { await controllerBus.apply(action, engine: appGlobals.cxAppPath) }
                                }
                            }
                        } else {
                            ProgressView().controlSize(.small)
                            Text("Checking the engine's controller bus…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    // Refused rather than attempted: not an error, a reason.
                    if let refused = controllerBus.refusedReason {
                        Text(refused).font(.footnote).foregroundStyle(.orange)
                    }
                }
                .task(id: appGlobals.cxAppPath ?? "") {
                    await controllerBus.refresh(engine: appGlobals.cxAppPath)
                }
                if(downloading){
                    ProgressView(value: progress, total: 100) {
                        Text(progressLabel).font(.footnote)
                    }.padding(.top)
                }
                // The application's, not any one store's. Moving the bottle
                // pickers into the store panel swept these in with them, so
                // selecting Epic made Patch all and the GStreamer status
                // vanish -- for settings that have nothing to do with which
                // store is selected.
                    // Said here rather than discovered later: a title whose
                    // video needs a decoder is silent in exactly the same way
                    // whether the framework is missing, the staging was never
                    // built, or it was built against a CrossOver that has since
                    // been updated.
                    // Every installed title that needs its fix, in one go.
                    let targets = PatchAll.targets(from: libraryPageGlobals.gamesMeta,
                                                   needsPatch: { fixLibrary.need(folder: $0) != .none })
                    VStack(alignment: .leading, spacing: 4) {
                        // Which fixes are running, where a person can see it.
                        //
                        // Ten unpacked versions sit under Application Support
                        // on this machine, 153 MB of them, and nothing said
                        // which was in use -- so a fix that misbehaved could
                        // only be traced by reading directory dates. Version
                        // and source both, because those are the two questions
                        // asked afterwards and neither is answerable from a
                        // launch line.
                        if let loaded = fixLibrary.loaded {
                            Text("Fixes \(loaded.version) · \(loaded.describedSource)")
                                .font(.footnote)
                                .foregroundStyle(.procyonBrightGray)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: targets.isEmpty ? "checkmark.circle" : "wand.and.sparkles")
                                .foregroundStyle(targets.isEmpty ? .green : .orange)
                            fixSummary(targets)
                                .font(.footnote)
                            Spacer()
                            if !targets.isEmpty {
                                Button(patchAll.running
                                       ? "Patching \(patchAll.done)/\(patchAll.total)…"
                                       : "Patch all") {
                                    Task { await patchAll.run(targets, bottles: appGlobals.configuredBottles) }
                                }
                                .disabled(patchAll.running)
                            }
                        }
                        if let current = patchAll.current {
                            Text(current).font(.footnote).foregroundStyle(.secondary)
                        }
                        // Refused rather than attempted: not an error, a reason.
                        if let refused = patchAll.refusedReason {
                            Text(refused).font(.footnote).foregroundStyle(.orange)
                        }
                        if !patchAll.patched.isEmpty && !patchAll.running {
                            Text(FixSummary.patched(patchAll.patched.count) + ".")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        // Named, not counted. "3 failed" tells you nothing you
                        // can act on.
                        ForEach(patchAll.failures) { failure in
                            Text("\(failure.title): \(failure.reason)")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    Group {
                        if let gst = gstStatus {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: gst.isOK ? "checkmark.circle" : "exclamationmark.triangle")
                                    .foregroundStyle(gst.isOK ? .green : .orange)
                                Text(gst.summary).font(.footnote)
                                    .foregroundStyle(gst.isOK ? .secondary : .primary)
                                Spacer()
                            }
                        } else {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Checking the engine's decoders…").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .task(id: appGlobals.cxAppPath ?? "") {
                        let path = appGlobals.cxAppPath
                        gstStatus = await Task.detached { GStreamerStatus.read(engineAppPath: path) }.value
                    }
                    if showArmSupport {
                        Text("ARM bottles draw through DXMT, which reaches Direct3D 11. Direct3D 12 titles will not run in one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                // One section per store: the bottle its client lives in, the
                // ARM bottle where that applies, and where its games are
                // installed. Switched rather than stacked -- at three stores
                // the stacked version is a page nobody reads to the bottom of.
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $configuringStore) {
                        ForEach(Store.allCases) { store in
                            Text(store.label).tag(store)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if configuringStore == .steam {
                    if(shouldShowBottleSelector) {
                        HStack {
                            Text("Select a bottle").frame(width: 110, alignment: .leading)
                            Picker("", selection: $appGlobals.selectedBottle) {
                                Text("No bottle selected").tag("")
                                ForEach(bottles, id: \.absoluteString) { bottle in
                                    let components = bottle.pathComponents
                                    let lastTwo = Array(components.suffix(2))
                                    let label = lastTwo.joined(separator: "/")
                                    Text(label).tag(bottle.absoluteString)
                                }
                            }
                        .labelsHidden()
                        .onChange(of: appGlobals.selectedBottle) { oldValue, newValue in
                                if(newValue != "") {
                                    appGlobals.windowsSteamFolder = URL(string: newValue)?.appendingPathComponent(DEFAULT_STEAM_WINE_PATH)
                                    persistUsrDefOptionString(key: "windowsSteamFolder", value: appGlobals.windowsSteamFolder!.path(percentEncoded: false))
                                    libraryPageGlobals.folders.removeAll()
                                    resetPersistedFolderAccess()
                                    let from = appGlobals.windowsSteamFolder?.appendingPathComponent("config") ?? URL(string: newValue)!.appendingPathComponent(DEFAULT_STEAM_WINE_CONFIG_PATH)
                                    let steamLibrariesURLs = getSteamLibraryFolders(bottleURL: URL(string: newValue)!,from: from)
                                    steamLibrariesURLs.forEach { url in
                                        validateAddSteamFolder(url, to: &libraryPageGlobals.folders)
                                    }
                                    Task { await load() }
                                    persistUsrDefOptionString(key: "selectedBottle", value: newValue)
                                }
                            }
                        }
                        if showArmSupport {
                            // Second slot, not another entry in the same picker: a
                            // bottle's architecture is fixed when it is created, so
                            // there is no promoting the normal one. Either an ARM
                            // bottle exists or the game cannot run on ARM.
                            HStack {
                                Text("ARM bottle").frame(width: 110, alignment: .leading)
                                Picker("", selection: $appGlobals.selectedArmBottle) {
                                    Text("None").tag("")
                                    ForEach(armBottles, id: \.url.absoluteString) { info in
                                        Text(info.name).tag(info.url.absoluteString)
                                    }
                                }
                            .labelsHidden()
                            .onChange(of: appGlobals.selectedArmBottle) { _, newValue in
                                    persistUsrDefOptionString(key: "selectedArmBottle", value: newValue)
                                }
                            }
                            if armBottles.isEmpty {
                                Text("No ARM bottle found. Create one in CrossOver, choosing the ARM architecture, on CrossOver 27 — it is the engine that ships FEX to emulate x86.")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else if(bottles.isEmpty) {
                        if appGlobals.cxAppPath != nil {
                        Text("No bottles found")
                        Text("Create a new bottle first").font(.footnote)
                            ProminentButton("Create new bottle", systemImage: "waterbottle") {
                                if creatingBottle {
                                    return
                                }
                                if let cxAppPath = appGlobals.cxAppPath {
                                    creatingBottle = true
                                    createBtlPrc = try? createBottle(cxAppPath: cxAppPath)
                                    if let proc = createBtlPrc {
                                        proc.terminationHandler = { _ in
                                            DispatchQueue.main.async {
                                                creatingBottle = false
                                                if let cxCompleteAppPath = readUsrDefOptionString(key: "cxCompleteAppPath") {
                                                    do{
                                                        bottles = try getAllBottles(appDir: URL(fileURLWithPath: cxCompleteAppPath))
                                                        shouldShowBottleSelector = true
                                                    } catch {
                                                        console.error(String(reflecting: error))
                                                    }
                                                } else {
                                                    console.error("Failed to load all bottles")
                                                }
                                            }
                                        }
                                    } else {
                                        creatingBottle = false
                                        console.error("Bottle creation failed")
                                    }
                                } else {
                                    console.error("Can't create a bottle before bottle is selected")
                                }
                            }
                        }
                        if creatingBottle {
                            ProgressView().progressViewStyle(.linear).frame(maxWidth: .infinity)
                            Button("Cancel") {
                                createBtlPrc!.terminate()
                                creatingBottle = false
                            }
                        }
                    } else {
                        ProgressView().progressViewStyle(.linear).frame(maxWidth: .infinity)
                    }
                    } else {
                        // Every other store keeps its own bottle here. This
                        // setting has to exist whatever is decided about
                        // one-bottle-per-store: RaccoonBot cannot launch a
                        // client it cannot find.
                        HStack {
                            Text("Select a bottle").frame(width: 110, alignment: .leading)
                            Picker("", selection: $storeBottle) {
                                Text("No bottle selected").tag("")
                                ForEach(bottles, id: \.absoluteString) { bottle in
                                    Text(Array(bottle.pathComponents.suffix(2)).joined(separator: "/"))
                                        .tag(bottle.absoluteString)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: storeBottle) { _, newValue in
                                var settings = StoreConfig.settings(for: configuringStore)
                                settings.bottle = newValue
                                StoreConfig.save(settings, for: configuringStore)
                            }
                        }
                        // Present and disabled rather than absent: the slot says
                        // the concept exists for this store too, and that it is
                        // off because nobody has established it works -- not
                        // because RaccoonBot forgot about it.
                        HStack {
                            Text("ARM bottle").frame(width: 110, alignment: .leading)
                            Picker("", selection: .constant("")) {
                                Text("Not available").tag("")
                            }
                            .labelsHidden()
                            .disabled(true)
                        }
                        Text("Running \(configuringStore.label) in an ARM bottle has not been tested, so the option is off.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if configuringStore == .epic,
                           let epic = EpicLaunch.target(settings: StoreConfig.settings(for: .epic),
                                                        selectedBottle: appGlobals.selectedBottle) {
                            HStack(alignment: .center, spacing: 12) {
                                ProminentButton("Open Epic Games Launcher", systemImage: "e.circle.fill") {
                                    openEpic(cxAppPath: appGlobals.cxAppPath, bottle: epic.bottle, clientPath: epic.clientPath)
                                }
                                .disabled(!EpicLaunch.isInstalled(epic))
                                Text(EpicLaunch.isInstalled(epic)
                                     ? "Opens the launcher in this bottle, on whatever the engine holds."
                                     : "Not installed in this bottle. Install it from CrossOver first.")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }

                    GameLibrariesList(store: configuringStore, load: load)
                    // Games already on the disk that the launcher does not
                    // know: it is told, rather than made to download them.
                    if configuringStore == .epic,
                       let epic = EpicLaunch.target(settings: StoreConfig.settings(for: .epic),
                                                    selectedBottle: appGlobals.selectedBottle),
                       EpicLaunch.isInstalled(epic),
                       let bottleDir = BottleReference(epic.bottle)?.directory,
                       !StoreConfig.settings(for: .epic).libraries.isEmpty {
                        HStack(alignment: .center, spacing: 12) {
                            ProminentButton("Register games on the disk", systemImage: "externaldrive.badge.plus") {
                                showEpicImport = true
                            }
                            Text("Tells the launcher about games already in the Epic folders above, so it lists them installed instead of downloading them again.")
                                .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .sheet(isPresented: $showEpicImport) {
                            EpicImportSheet(bottle: bottleDir,
                                            // Stored as POSIX paths by GameLibrariesList; URL(string:) would take
                                            // a path without spaces for a scheme-less URL that no file API opens.
                                            libraries: StoreConfig.settings(for: .epic).libraries.map { URL(fileURLWithPath: $0) },
                                            load: load)
                        }
                    }
                }
                .task(id: configuringStore) {
                    storeBottle = StoreConfig.settings(for: configuringStore).bottle
                }

                .padding(.vertical)
                // Steam's own. The other stores do not have a Windows client in
                // the bottle to point at, so the button only appears for Steam --
                // and only once a bottle is chosen, since the path lives inside it.
                if configuringStore == .steam, appGlobals.selectedBottle != "" {
                    HStack(alignment: .center, spacing: 12) {
                            ProminentButton("Set Steam path", image: "steam-fill") {
                                if let bottlePath = URL(string: appGlobals.selectedBottle) {
                                    if let url = openFolderSelectorPanel(type: .directory, initialDirectory: bottlePath.appendingPathComponent("drive_c"), title: "Select your Steam folder (where steam.exe is located)") {
                                        let fallbackPath = bottlePath.appendingPathComponent(DEFAULT_STEAM_WINE_PATH).path(percentEncoded: false)
                                        appGlobals.windowsSteamFolder = url
                                        persistUsrDefOptionString(key: "windowsSteamFolder", value: appGlobals.windowsSteamFolder?.path(percentEncoded: false) ?? fallbackPath)
                                        let from = appGlobals.windowsSteamFolder?.appendingPathComponent("config") ?? URL(string: appGlobals.selectedBottle)!.appendingPathComponent(DEFAULT_STEAM_WINE_CONFIG_PATH)
                                        let steamLibrariesURLs = getSteamLibraryFolders(bottleURL: URL(string: appGlobals.selectedBottle)! ,from: from)
                                        steamLibrariesURLs.forEach { url in
                                            validateAddSteamFolder(url, to: &libraryPageGlobals.folders)
                                        }
                                        Task { await load() }
                                    }
                                }
                            }
                            Text(appGlobals.windowsSteamFolder?.path(percentEncoded: false) ?? "Not set")
                                .font(.footnote).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                                .help(appGlobals.windowsSteamFolder?.path(percentEncoded: false) ?? "Not set")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical)
        }
        .onAppear() {
            let f = FileManager.default
            if let path = readUsrDefOptionString(key: "cxCompleteAppPath") {
                console.log("loading paths for bottles")
                if !f.fileExists(atPath: path) {
                    appGlobals.cxAppPath = nil
                }
                do {
                    bottles = try getAllBottles(appDir: URL(fileURLWithPath: path))
                    if(!bottles.isEmpty && appGlobals.cxAppPath != nil) {
                        shouldShowBottleSelector = true
                    }
                } catch {
                    console.error(String(reflecting: error))
                }
                console.log(bottles.debugDescription)
            }
        }
    }
}

#Preview {
    OptionsView(
        load: { },
    )
}

