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
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @MainActor var load: @Sendable () async -> Void
    var body: some View {
        Modal(
            "Options",
            showModal: $libraryPageGlobals.showOptions,
        ) {
            VStack (alignment: .leading){
                Button(URL(string: appGlobals.cxAppPath ?? "")?.lastPathComponent ?? "Select a Crossover App...") {
                    if let url = openFolderSelectorPanel(type: .application) {
                        appGlobals.selectedBottle = ""
                        bottles = getAllBottles(appDir: url)
                        Task { @MainActor in
                            let patchedAppURL = await makeCrossoverPatchedCopy(sourceCXPath: url, setProgress: { p,m in progress = p; progressLabel = m  }, setLoading: { state in downloading = state })
                            progress = 0
                            await makeX87CrossoverPatchedCopy(sourceCXPath: url, patchedApp: patchedAppURL)
                            appGlobals.cxAppPath = patchedAppURL.path(percentEncoded: false)
                            persistUsrDefOptionString(key: "cxAppPath", value: patchedAppURL.relativePath)
                            persistUsrDefOptionString(key: "cxCompleteAppPath", value: patchedAppURL.path(percentEncoded: false))
                        }
                    }
                }
                if(downloading){
                    ProgressView(value: progress, total: 100) {
                        Text(progressLabel).font(.footnote)
                    }.padding(.top)
                }
                if(!bottles.isEmpty) {
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
                                libraryPageGlobals.folders.removeAll()
                                resetPersistedFolderAccess()
                                let steamLibrariesURLs = getSteamLibraryFolders(from: URL(string: newValue)!)
                                steamLibrariesURLs.forEach { url in
                                    validateAddSteamFolder(url, to: &libraryPageGlobals.folders)
                                }
                                Task { await load() }
                                persistUsrDefOptionString(key: "selectedBottle", value: newValue)
                            }
                        }
                    }
                } else {
                    Text("No bottles found")
                    Text("Create a new bottle first").font(.footnote)
                }
                GameLibrariesList(load: load)
                .padding(.vertical)
                VStack(alignment: .leading) {
                    ProminentButton("Open Crossover", image: "crossover-fill") {
                        if let cxPath = appGlobals.cxAppPath {
                            let url = URL(fileURLWithPath: cxPath)
                            NSWorkspace.shared.open(url)
                        }
                    }
                    ProminentButton("Open Steam", image: "steam-fill") {
                        openSteam(cxAppPath: appGlobals.cxAppPath, selectedBottle: appGlobals.selectedBottle)
                    }
                    ProminentButton("Open current bottle", systemImage: "waterbottle"){
                        if let selectedBottleURL = URL(string: appGlobals.selectedBottle){
                            showFolder(url: selectedBottleURL)
                        }
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
                    if(debugEnabled == true) {
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
            if let path = readUsrDefOptionString(key: "cxCompleteAppPath") {
                console.log("loading paths for bottles")
                bottles = getAllBottles(appDir: URL(fileURLWithPath: path))
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

