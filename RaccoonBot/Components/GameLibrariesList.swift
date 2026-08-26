//
//  GameLibrariesList.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 31/03/2026.
//

import SwiftUI

struct GameLibrariesList: View {
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @MainActor var load: @Sendable () async -> Void
    
    var body: some View {
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
    }
}
