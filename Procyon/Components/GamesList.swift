//
//  GameView.swift
//  Procyon
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI

let columns = [
    GridItem(.adaptive(minimum: 250, maximum: 325), spacing: 10),
]

struct GamesList: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @EnvironmentObject var appGlobals: AppGlobals
    @State private var showProfile: Bool = false
    @State private var showAddCustomGameView: Bool = false
    
    var load: @Sendable () async -> Void
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(libraryPageGlobals.filteredGames) { item in
                    GameThumbnail(item: item, isResizable: appWindowResizable)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .sheet(isPresented: $showAddCustomGameView) {
            Modal("Custom Game Editor", showModal: $showAddCustomGameView, scrollable: false)  {
                CustomGameView(isPresented: $showAddCustomGameView)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                HStack {
                    if(!appGlobals.selectedBottle.isEmpty){
                        ProfileWidget()
                        Divider()
                    }
                    Button {
                        libraryPageGlobals.showOptions = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showAddCustomGameView = true
                } label: {
                    Image(systemName: "rectangle.badge.plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    api.deleteOwnedGamesIDsCache()
                    libraryPageGlobals.gamesMeta.removeAll()
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task {
                        try! await closeWineActivities()
                        libraryPageGlobals.isLaunchingGame = false
                    }
                } label: {
                    Image(systemName: "exclamationmark.octagon")
                }
            }
            ToolbarItemGroup(placement: .principal) {
                HStack {
                    HStack {
                        Button {
                            if (libraryPageGlobals.filter.isEmpty) {
                                return
                            } else {
                                libraryPageGlobals.filter = ""
                            }
                        } label: {
                            Image(systemName: libraryPageGlobals.filter.isEmpty ? "magnifyingglass": "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        TextField("Search Game...", text: $libraryPageGlobals.filter)
                            .textFieldStyle(.plain)
                            .disableAutocorrection(true)
                            .focusEffectDisabled()
                            .textFieldStyle(.plain)
                            .frame(width: 100)
                            
                    }.controlSize(.small)
                    Divider()
                    HStack {
                        Image(systemName: "arrow.up.arrow.down.circle")
                        Picker("", selection: $libraryPageGlobals.sortBy) {
                            Text("Name").tag(SortingOptions.name)
                            Text("Release Date").tag(SortingOptions.releaseDate)
                            Text("Publisher").tag(SortingOptions.publisher)
                            Text("Developer").tag(SortingOptions.developer)
                            Text("Installed").tag(SortingOptions.installed)
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }
                    Divider()
                    Text("Showing \(libraryPageGlobals.filteredGames.count)/\(libraryPageGlobals.allGamesCount)").font(Font.footnote)
                }.padding(.horizontal)
            }
        }
    }
}

