//
//  ToolsView.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 06/07/2026.
//

import SwiftUI

struct ToolsView: View {
    @State private var savedLogResult: String?
    @State private var debugLogging: Bool = debugLoggingEnabled
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
    
    /// What the retry button says on hover, including whether it has anything
    /// to do. A title lands in that list when the store answers that it has no
    /// record of it -- delisted, unreleased, or not a store item at all -- and
    /// it keeps its card and its name from the .acf either way; what it loses
    /// is the cover and the description.
    private var skippedHelp: String {
        let count = api.skippedCount
        guard count > 0 else {
            return "Nothing has been skipped. Titles the store answers nothing for are "
                 + "set aside so they are not asked about again; this asks again."
        }
        return "\(count) title\(count == 1 ? "" : "s") set aside because the store had no record of "
             + "\(count == 1 ? "it" : "them"). They keep their cards and their names, without a cover "
             + "or a description. This asks the store about them again, without touching the rest of the cache."
    }

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
                    libraryPageGlobals.games.removeAll()
                    Task {
                        await load()
                    }
                    libraryPageGlobals.showOptions = false
                }
                .help("Throws away every stored store record and asks for them all again, one title roughly every two seconds.")

                // Its own button, and its own words.
                //
                // Clearing the skipped titles used to be something "Delete
                // cache" did on the side, without saying so. That is the only
                // way back for a title the store answered nothing for, and it
                // cost the whole record cache to use -- four hundred titles
                // re-fetched at one every two seconds to undo a handful. The
                // two are separate now, and this one names what it undoes.
                ProminentButton("Retry skipped titles", systemImage: "arrow.clockwise") {
                    api.deleteBlacklistCache()
                    Task {
                        await load()
                    }
                    libraryPageGlobals.showOptions = false
                }
                .help(skippedHelp)
                ProminentButton("Delete all downloads cache", systemImage: "trash") {
                    TarDownloader.deleteAllDownloadCache()
                }
                ProminentButton("Delete D3dmetal Cache", systemImage: "trash") {
                    cleard3dmCacheStatus = removeD3DMetalCaches()
                }
                ProminentButton("Show D3dmetal Cache Folder", systemImage: "folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: darwinUserCacheDir()!.appendingPathComponent(D3DM_CACHE_FOLDER, isDirectory: true).path)
                }
                // The only way back from "Start, and don't show this again".
                // That button mutes a warning about a real disconnect, and a
                // mute with no way back in the application is a trap.
                ProminentButton("Show the DualSense disconnect notice again", systemImage: "gamecontroller") {
                    UserDefaults.standard.removeObject(forKey: MacIdleDisconnect.suppressionKey)
                }
                .help("Play warns again before a game starts when macOS is set to disconnect a DualSense on Bluetooth about 15 minutes into play.")
                // Always here, not only when a variable was set before
                // launch. Somebody being asked "can you send me the log" has
                // to be able to find this without a terminal.
                Group {
                    Divider().padding(.top, 10)
                    Text("Debug")
                        .padding(.vertical, 5)
                    VStack(alignment: .leading, spacing: 8) {
                        // Start Logging used to be here. It set enableLogFile
                        // to true, which is already true whenever this section
                        // is visible -- the section and the flag are both
                        // decided by DEBUG_ENABLED. A button that can only
                        // ever be a no-op reads as something not working.
                        Toggle("Keep a log", isOn: Binding(
                            get: { debugLogging },
                            set: { on in
                                setDebugLogging(on)
                                debugLogging = on
                            }))
                        .disabled(debugLoggingFromEnvironment)

                        Text(debugLoggingFromEnvironment
                             ? "On, because the environment asked for it. It cannot be turned off here."
                             : debugLogging
                               ? "Messages are kept in memory until you save them, and are lost if the application is quit first."
                               : "Nothing is being recorded. Turn this on, reproduce the problem, then save.")
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
                                savedLogResult = lines == 1 ? "1 line saved." : "\(lines) lines saved."
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
