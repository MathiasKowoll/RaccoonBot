//
//  ToolsView.swift
//  Procyon
//
//  Created by Italo Mandara on 06/07/2026.
//

import SwiftUI

struct ToolsView: View {
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
            }.padding(.vertical, 10)
        }
    }
}

#Preview {
    ToolsView(load: {})
}
