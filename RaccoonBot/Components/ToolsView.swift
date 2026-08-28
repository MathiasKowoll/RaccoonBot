//
//  ToolsView.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 06/07/2026.
//

import SwiftUI

struct ToolsView: View {
    @State private var savedLogResult: String?
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
    @State var cleard3dmCacheStatus: DeleteStatus = DeleteStatus.idle
    
    var body: some View {
        Modal(
            "Tools",
            showModal: $libraryPageGlobals.showTools,
        ) {
            VStack(alignment: .leading) {
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
                ProminentButton("Delete D3dmetal Cache", systemImage: "trash") {
                    cleard3dmCacheStatus = removeD3DMetalCaches()
                }
                ProminentButton("Show D3dmetal Cache Folder", systemImage: "folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: darwinUserCacheDir()!.appendingPathComponent(D3DM_CACHE_FOLDER, isDirectory: true).path)
                }
                if(DEBUG_ENABLED == true) {
                    Divider().padding(.top, 10)
                    Text("Debug")
                        .padding(.vertical, 5)
                    VStack(alignment: .leading, spacing: 8) {
                        // Start Logging used to be here. It set enableLogFile
                        // to true, which is already true whenever this section
                        // is visible -- the section and the flag are both
                        // decided by DEBUG_ENABLED. A button that can only
                        // ever be a no-op reads as something not working.
                        Text("Logging is on. Messages are kept in memory until you save them, and are lost if the application is quit first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(Console.logURL.path(percentEncoded: false))
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        ProminentButton("Save logs", systemImage: "square.and.arrow.down") {
                            let lines = console.logMessages.count
                            console.saveLogs()
                            let url = Console.logURL
                            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                                savedLogResult = "^[\(lines) line](inflect: true) saved."
                                // Straight to it, because the next thing anyone
                                // wants is the file.
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } else {
                                savedLogResult = "Could not write \(url.path(percentEncoded: false))"
                            }
                        }

                        if let savedLogResult {
                            Text(savedLogResult)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(.vertical, 10)
        }
    }
}

#Preview {
    ToolsView(load: {})
}
