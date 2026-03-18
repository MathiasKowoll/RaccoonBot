//
//  AddEditCustomGameView.swift
//  Procyon
//
//  Created by Italo Mandara on 18/03/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct AddCustomGameView: View {
    @State private var text: String = ""
    @State private var game: Game = Game(from: Game.steamEmptyGame, id: UUID().uuidString, isNative: true, downloadProgress: 100, isInstalled: true, appNames: [], isCustom: true)
    @State private var id: String = ""
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @Binding var isPresented: Bool
    
    var customGames: [Game] {
        libraryPageGlobals.customAddedGames.filter { $0.isCustom == true }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Custom Game Editor")
            Picker("Select a Game to edit", selection: $id) {
                Text("Select a Game").tag("")
                ForEach(customGames, id: \.id) { game in
                    Text(game.name).tag(game.id)
                }
            }.onChange(of: id) {
                if id != "" {
                    if let currentGame = libraryPageGlobals.getCustomAddedGame(id: id) {
                        game = currentGame
                    }
                }
            }
            GameThumbnail(item: game)
            TextField("Game Title", text: $game.name)
            // Native toggle
            HStack(alignment: .top){
                Toggle("Is a Mac Game", isOn: $game.isNative)
                // Platforms toggles
                Spacer()
                VStack {
                    Text("Supported Platforms")
                    HStack {
                        Toggle("Windows", isOn: $game.platforms.windows)
                        Toggle("macOS", isOn: $game.platforms.mac)
                        Toggle("Linux", isOn: $game.platforms.linux)
                    }
                }
            }
            // Executable path
            Button(game.appExeURL?.path(percentEncoded: false) ?? "Select a Game App...") {
                if let url = openFolderSelectorPanel(type: .executable) {
                    game.appExeURL = url
                    game.appNames.append(url.lastPathComponent)
                    if id == "" {
                        game.id = UUID().uuidString + url.path(percentEncoded: false)
                    }
                }
            }
            // Descriptions
            TextField("Detailed Description", text: $game.detailedDescription, axis: .vertical)
                .lineLimit(3...6)
            TextField("About The Game", text: $game.aboutTheGame, axis: .vertical)
                .lineLimit(3...6)
            TextField("Short Description", text: $game.shortDescription)
            // Header image URL
            TextField("Header Image URL", text: $game.headerImage)
            // Developers and Publishers as comma-separated lists
            TextField(
                "Developers (comma-separated)",
                text: Binding(
                    get: { game.developers.joined(separator: ", ") },
                    set: { newValue in
                        game.developers = newValue
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                )
            )
            TextField(
                "Publishers (comma-separated)",
                text: Binding(
                    get: { game.publishers.joined(separator: ", ") },
                    set: { newValue in
                        game.publishers = newValue
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                )
            )
            // Categories as comma-separated by description
            TextField(
                "Categories (comma-separated descriptions)",
                text: Binding(
                    get: { game.categories.map { $0.description }.joined(separator: ", ") },
                    set: { newValue in
                        let parts = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        // Preserve existing IDs when possible, otherwise assign incremental IDs starting at 1
                        var newCats: [Category] = []
                        for (idx, desc) in parts.enumerated() {
                            if idx < game.categories.count {
                                newCats.append(Category(id: game.categories[idx].id, description: desc))
                            } else {
                                newCats.append(Category(id: idx + 1, description: desc))
                            }
                        }
                        game.categories = newCats
                    }
                )
            )
            TextField(
                "Genres (comma-separated descriptions)",
                text: Binding(
                    get: { game.genres?.map { $0.description }.joined(separator: ", ") ?? "" },
                    set: { newValue in
                        let parts = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        // Preserve existing IDs when possible, otherwise assign incremental IDs starting at 1
                        var newGenre: [Genre] = []
                        for (idx, desc) in parts.enumerated() {
                            if game.genres != nil && idx < game.genres?.count ?? 0 {
                                newGenre.append(Genre(id: game.genres![idx].id, description: desc))
                            } else {
                                newGenre.append(Genre(id: String(idx + 1), description: desc))
                            }
                        }
                        game.genres = newGenre
                    }
                )
            )
            if id != "" {
                Button("Update Game") {
                    libraryPageGlobals.updateCustomAddedGames(gameData: game)
                    isPresented = false
                }
            } else {
                Button("Add Game") {
                    game.isCustom = true
                    libraryPageGlobals.customAddedGames.append(game)
                    libraryPageGlobals.saveCustomAddedGames()
                    isPresented = false
                }
            }
        }
        .padding()
    }
}

#Preview {
    AddCustomGameView(isPresented: .constant(true))
}

