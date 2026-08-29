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
    @State private var gstBusy = false
    @State private var gstMessage: String?

    /// Bottles that can actually serve a game marked to run on ARM: ARM
    /// architecture AND an engine that ships FEX. An ARM bottle on CrossOver 26
    /// runs ARM-native Windows binaries only, so listing it here would offer
    /// the one bottle that cannot run the game.
    /// Offer the version the engines on this machine can actually use.
    ///
    /// Prescriptive rather than defensive: it says which one and why, and it
    /// holds someone at an older series only while an older engine is still
    /// installed. Drop that engine and the answer moves on by itself.
    private func installGStreamer() async {
        gstBusy = true
        defer { gstBusy = false }
        let installer = GStreamerInstall()
        do {
            let available = try await installer.publishedVersions()
            let series = installedEngineSeries()
            guard let version = GStreamerInstall.chooseVersion(available: available,
                                                               engineSeries: series) else {
                gstMessage = "Could not work out which GStreamer these engines need"
                return
            }
            gstMessage = "Downloading GStreamer \(version) — macOS will ask for your password to install it"
            try await installer.downloadAndOpen(version: version)
            gstMessage = "GStreamer \(version) downloaded. Finish the install, then reopen this window."
        } catch {
            gstMessage = error.localizedDescription
        }
    }

/// The GStreamer series each installed CrossOver runs, read from its own
    /// core rather than assumed from its version number.
    private func installedEngineSeries() -> [Int] {
        var series: Set<Int> = []
        let f = FileManager.default
        for root in ["/Applications", f.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path(percentEncoded: false)] {
            for name in (try? f.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".app") {
                let app = root + "/" + name
                for sub in ["lib64", "lib/x86_64"] {
                    let lib = "\(app)/Contents/SharedSupport/CrossOver/\(sub)/libgstreamer-1.0.0.dylib"
                    guard f.fileExists(atPath: lib) else { continue }
                    if let s = GStreamerStatus.series(ofCoreAt: lib) { series.insert(s) }
                }
            }
        }
        return Array(series)
    }

    private var armBottles: [BottleInfo] {
        bottles.compactMap { bottleInfo($0) }.filter { $0.isARM && $0.canRunX86 }
    }
    @State var creatingBottle: Bool = false
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @MainActor var load: @Sendable () async -> Void
    @State var createBtlPrc: Process?
    @State var cleard3dmCacheStatus: DeleteStatus = DeleteStatus.idle
    /// Read once, off the main thread, and remembered. NEVER computed in the
    /// body: reading it runs otool and blocks on waitUntilExit(), and SwiftUI
    /// evaluates a body repeatedly and re-entrantly. Doing that inside the
    /// body getter segfaulted the application on opening this screen.
    @State private var gstStatus: GStreamerStatus?
    @StateObject private var patchAll = PatchAll()
    @StateObject private var fixLibrary = MGVFLibrary.shared
    
    var body: some View {
        Modal(
            "Options",
            showModal: $libraryPageGlobals.showOptions,
        ) {
            VStack (alignment: .leading){
                Button(URL(string: appGlobals.cxAppPath ?? "")?.lastPathComponent ?? "Select a Crossover App...") {
                    shouldShowBottleSelector = false
                    if let url = openFolderSelectorPanel(type: .application) {
                        appGlobals.selectedBottle = ""
                        Task { @MainActor in
                            let patchedAppURL = await makeCrossoverPatchedCopy(sourceCXPath: url, setProgress: { p,m in progress = p; progressLabel = m  }, setLoading: { state in downloading = state })
                            progress = 0
                            await makeX87CrossoverPatchedCopy(sourceCXPath: url, patchedApp: patchedAppURL)
                            appGlobals.cxAppPath = patchedAppURL.path(percentEncoded: false)
                            persistUsrDefOptionString(key: "cxAppPath", value: patchedAppURL.relativePath)
                            persistUsrDefOptionString(key: "cxCompleteAppPath", value: patchedAppURL.path(percentEncoded: false))
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
                                                   needsPatch: { fixLibrary.needsPatch(folder: $0) })
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: targets.isEmpty ? "checkmark.circle" : "wand.and.sparkles")
                                .foregroundStyle(targets.isEmpty ? .green : .orange)
                            Text(targets.isEmpty
                                 ? "Every installed title that needs a fix has one."
                                 : "^[\(targets.count) installed title](inflect: true) needs its video fix.")
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
                            Text("^[Patched \(patchAll.patched.count) title](inflect: true).")
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
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: gst.isOK ? "checkmark.circle" : "exclamationmark.triangle")
                                        .foregroundStyle(gst.isOK ? .green : .orange)
                                    Text(gst.summary).font(.footnote)
                                        .foregroundStyle(gst.isOK ? .secondary : .primary)
                                    Spacer()
                                    if case .missing = gst.framework {
                                        Button(gstBusy ? "Downloading…" : "Install GStreamer…") {
                                            Task { await installGStreamer() }
                                        }.disabled(gstBusy)
                                    }
                                }
                                if let gstMessage {
                                    Text(gstMessage).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Checking GStreamer…").font(.footnote).foregroundStyle(.secondary)
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
                    }

                    GameLibrariesList(store: configuringStore, load: load)
                }
                .task(id: configuringStore) {
                    storeBottle = StoreConfig.settings(for: configuringStore).bottle
                }

                .padding(.vertical)
                VStack(alignment: .leading) {
                    if appGlobals.selectedBottle != "" {
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
                        Text("\(appGlobals.windowsSteamFolder?.path(percentEncoded: false) ?? "Not set")")
                    }
                }
            }
            .frame(width: 300)
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

