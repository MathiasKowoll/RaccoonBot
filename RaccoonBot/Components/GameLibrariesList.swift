//
//  GameLibrariesList.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 31/03/2026.
//
//  Made store-aware: Steam scatters a library across as many folders as you
//  point it at, Epic records one install path per title. So the list is a list
//  for one store and a single slot for the other, and the button says which.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct GameLibrariesList: View {
    var store: Store = .steam
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @MainActor var load: @Sendable () async -> Void

    /// Steam's folders are still held by LibraryPageGlobals, because the scan,
    /// the security-scoped bookmarks and the launch path all read them from
    /// there. Every other store keeps its own in StoreConfig. Moving Steam over
    /// is worth doing, and is not worth doing in the same change as adding a
    /// second store.
    @State private var otherStoreLibraries: [String] = []

    private var folders: [String] {
        store == .steam ? libraryPageGlobals.folders : otherStoreLibraries
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 6) {
                StoreGlyph(store: store, size: 12)
                Text(store.supportsMultipleLibraries ? "Game libraries" : "Game library")
            }
            .padding(.horizontal)

            VStack {
                Divider()
                if folders.isEmpty {
                    HStack {
                        Text(store == .steam
                             ? "None yet — they are found automatically when you choose a bottle."
                             : "Not set.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                ForEach(folders, id: \.self) { folder in
                    HStack(alignment: .center) {
                        Text(extractFolderNameRegex(folder))
                        Spacer()
                        Button(action: { remove(folder) }) {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                    .padding(.horizontal)
                }
                Divider()
            }
            .listStyle(.bordered)

            // One store, one button, and it says what it does. A store that
            // holds a single library offers to replace it rather than to add a
            // second one that would never be read.
            if store.supportsMultipleLibraries || folders.isEmpty {
                Button(action: add) {
                    Label(store.supportsMultipleLibraries
                          ? "Add a \(store.label) library"
                          : "Set the \(store.label) library",
                          systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal)
            } else {
                Button(action: add) {
                    Label("Change the \(store.label) library", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 10)
        .background(.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task(id: store) {
            guard store != .steam else { return }
            otherStoreLibraries = StoreConfig.settings(for: store).libraries
        }
    }

    private func add() {
        guard let url = openFolderSelectorPanel() else { return }
        if store == .steam {
            validateAddSteamFolder(url, to: &libraryPageGlobals.folders)
            Task { await load() }
        } else {
            var settings = StoreConfig.settings(for: store)
            let path = url.path(percentEncoded: false)
            settings.libraries = store.supportsMultipleLibraries
                ? Array(Set(settings.libraries + [path])).sorted()
                : [path]
            StoreConfig.save(settings, for: store)
            otherStoreLibraries = settings.libraries
        }
    }

    private func remove(_ folder: String) {
        if store == .steam {
            removeSteamFolderPath(folder)
            libraryPageGlobals.folders = getSteamFolderPaths()
            Task { await load() }
        } else {
            var settings = StoreConfig.settings(for: store)
            settings.libraries.removeAll { $0 == folder }
            StoreConfig.save(settings, for: store)
            otherStoreLibraries = settings.libraries
        }
    }
}
