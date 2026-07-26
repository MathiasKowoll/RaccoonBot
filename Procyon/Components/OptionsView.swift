//
//  Options.swift
//  Procyon
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
    @State var creatingBottle: Bool = false
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @MainActor var load: @Sendable () async -> Void
    @State var createBtlPrc: Process?
    
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
//                            await makeX87CrossoverPatchedCopy(sourceCXPath: url, patchedApp: patchedAppURL)
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
                if(shouldShowBottleSelector) {
                    HStack {
                        Picker("Select a bottle", selection: $appGlobals.selectedBottle) {
                            Text("No bottle selected").tag("")
                            ForEach(bottles, id: \.absoluteString) { bottle in
                                let components = bottle.pathComponents
                                let lastTwo = Array(components.suffix(2))
                                let label = lastTwo.joined(separator: "/")
                                Text(label).tag(bottle.absoluteString)
                            }
                        }.onChange(of: appGlobals.selectedBottle) { oldValue, newValue in
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
                GameLibrariesList(load: load)
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
                    VStack(alignment: .leading) {
                        Divider().padding(.top, 10)
                        Text("Cache management")
                            .padding(.vertical, 5)
                        ProminentButton("Delete Owned games cache", systemImage: "trash") {
                            api.deleteOwnedGamesIDsCache()
                            libraryPageGlobals.gamesMeta.removeAll()
                            Task {
                                await load()
                            }
                            libraryPageGlobals.showOptions = false
                        }
                        ProminentButton("Delete cache", systemImage: "trash") {
                            api.deleteGameCache()
                            api.deleteBlacklistCache()
                            libraryPageGlobals.games.removeAll()
                            Task {
                                await load()
                            }
                            libraryPageGlobals.showOptions = false
                        }
                        ProminentButton("Delete all downloads cache", systemImage: "trash") {
                            TarDownloader.deleteAllDownloadCache()
                        }
                    }
                    if(DEBUG_ENABLED == true) {
                        Divider().padding(.top, 10)
                        Text("Debug")
                            .padding(.vertical, 5)
                        VStack(alignment: .leading) {
                            ProminentButton("Start Logging", systemImage: "ant") {
                                console.enableLogFile = true
                            }
                            Spacer()
                            ProminentButton("Download logs", systemImage: "square.and.arrow.down") {
                                console.saveLogs()
                            }
                        }
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

