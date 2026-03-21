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
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    var load: @Sendable () async -> Void
    var body: some View {
        Modal(
            "Options",
            showModal: $libraryPageGlobals.showOptions,
        ) {
            VStack (alignment: .center){
                VStack(alignment: .leading) {
                    Text("Game libraries")
                        .padding(.horizontal)
                    VStack {
                        Divider()
                        ForEach(libraryPageGlobals.folders, id: \.self) {folder in
                            HStack(alignment: .center) {
                                Text(extractFolderNameRegex(folder))
                                Spacer()
                                Button(action: {
                                    removeSteamFolderPath(folder)
                                    libraryPageGlobals.folders = getSteamFolderPaths()
                                    Task { await load() }
                                }) {
                                    Image(systemName: "trash")
                                }.buttonStyle(.borderless)
                            }
                            .padding(.horizontal)
                        }
                        Divider()
                    }
                    .listStyle(.bordered)
                    Button(action: {
                        if let url = openFolderSelectorPanel() {
                            validateAddSteamFolder(url, to: &libraryPageGlobals.folders)
                            Task { await load() }
                        }
                    }) {
                        Label("Add a steam library", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal)
                }
                .padding(.vertical, 10)
                .background(.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.bottom)
                VStack(alignment: .leading) {
                    Button(URL(string: appGlobals.cxAppPath ?? "")?.lastPathComponent ?? "Select a Crossover App...") {
                        if let url = openFolderSelectorPanel(type: .application) {
                            appGlobals.selectedBottle = ""
                            bottles = getAllBottles(appDir: url)
                            appGlobals.cxAppPath = url.path(percentEncoded: false)
                            persistUsrDefOptionString(key: "cxAppPath", value: url.relativePath)
                            persistUsrDefOptionString(key: "cxCompleteAppPath", value: url.path(percentEncoded: false))
                            makeX87CrossoverPatchedCopy(sourceCXPath: url)
                        }
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
                                    do {
                                        try cpyd8d9DLLs(to: getSystemWOW64URL(from: URL(string: newValue)!))
                                    } catch {
                                        console.error(String(reflecting: error))
                                    }
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
                            Button {
                                showFolder(url: (URL(string:appGlobals.selectedBottle)) ?? URL(string: "/")!)
                            } label: {
                                Image(systemName: "eye")
                            }
                        }
                    } else {
                        Text("No bottles found")
                        Text("Create a new bottle first").font(.footnote)
                    }
                    HStack {
                        Button(action: {
                            api.deleteOwnedGamesIDsCache()
                            Task {
                                await load()
                            }
                            libraryPageGlobals.showOptions = false
                        }) {
                            Label("Delete Owned games cache", systemImage: "trash")
                        }
                        .cornerRadius(20)
                        Divider()
                        Button(action: {
                            api.deleteGameCache()
                            api.deleteBlacklistCache()
                            Task {
                                await load()
                            }
                            libraryPageGlobals.showOptions = false
                        }) {
                            Label("Delete cache", systemImage: "trash")
                        }
                        .cornerRadius(20)
                    }
                    
                    if(debugEnabled == true) {
                        Divider().padding(.top, 10)
                        Text("Debug")
                            .padding(.vertical, 5)
                        HStack {
                            Button(action: { console.enableLogFile = true }) {
                                Label("Start Logging", systemImage: "ant")
                            }
                            .cornerRadius(20)
                            Spacer()
                            Button(action: {
                                console.saveLogs()
                            }) {
                                Label("Download logs", systemImage: "square.and.arrow.down")
                            }
                            .cornerRadius(20)
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

