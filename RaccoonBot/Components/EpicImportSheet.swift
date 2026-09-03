//
//  EpicImportSheet.swift
//  RaccoonBot
//
//  Games found in the Epic library folders that the launcher does not know
//  yet, and the one button that tells it.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct EpicImportSheet: View {
    let bottle: URL
    let libraries: [URL]
    @MainActor var load: @Sendable () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var found: [EpicImport.Found] = []
    @State private var scanned = false
    @State private var result: String?
    @State private var failed: String?
    @State private var live = false

    private var ready: [EpicImport.Found] { found.filter { $0.status == .ready } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Games on the disk").font(.title3.bold())
            Text("What the Epic library folders hold, and whether the launcher in this bottle knows it. Registering writes the launcher's own records for a game that is already there, so it is not downloaded again.")
                .font(.footnote).foregroundStyle(.secondary)
            if !scanned {
                ProgressView().frame(maxWidth: .infinity)
            } else if found.isEmpty {
                Text("No game with an .egstore folder was found in the configured Epic folders.")
                    .foregroundStyle(.secondary)
            } else {
                List(found) { g in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.title).font(.body.weight(g.kind == .game ? .semibold : .regular))
                            Text("\(g.kind == .dlc ? "DLC · " : "")\(g.build.buildVersion) · \(g.folder.lastPathComponent)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let note = g.note { Text(note).font(.caption).foregroundStyle(.orange) }
                        }
                        Spacer()
                        Text(label(for: g.status)).font(.caption).foregroundStyle(color(for: g.status))
                    }
                }
                .frame(minHeight: 160, maxHeight: 320)
            }
            if live {
                Text("The bottle is running. Close the launcher and every game in it first; the launcher's records are written only while it is down.")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if let result { Text(result).font(.footnote).foregroundStyle(.green) }
            if let failed { Text(failed).font(.footnote).foregroundStyle(.red) }
            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button("Scan again") { Task { await scan() } }
                Button("Register \(ready.count) with the launcher") { register() }
                    .buttonStyle(.borderedProminent)
                    .disabled(ready.isEmpty || live || result != nil)
            }
        }
        .padding(20)
        .frame(width: 620)
        .task { await scan() }
    }

    private func label(for s: EpicImport.Found.Status) -> String {
        switch s {
        case .registered:   return "Known to the launcher"
        case .ready:        return "Not registered"
        case .unknownTitle: return "Not in the catalogue"
        }
    }
    private func color(for s: EpicImport.Found.Status) -> Color {
        switch s {
        case .registered:   return .secondary
        case .ready:        return .accentColor
        case .unknownTitle: return .orange
        }
    }

    private func scan() async {
        scanned = false; result = nil; failed = nil
        let bottle = bottle, libraries = libraries
        let (list, isLive) = await Task.detached(priority: .userInitiated) { () -> ([EpicImport.Found], Bool) in
            let catalog = EpicLibrary.dataDirectory(bottle: bottle).flatMap(EpicCatalog.read)
            let registered = EpicImport.registered(in: bottle)
            var all: [EpicImport.Found] = []
            for lib in libraries { all += EpicImport.scan(library: lib, catalog: catalog, registered: registered) }
            return (all, BottleProcesses.serverIsAlive(inBottleAt: bottle))
        }.value
        found = list; live = isLive; scanned = true
    }

    private func register() {
        do {
            let applied = try EpicImport.apply(found, bottle: bottle)
            result = "Registered \(applied.registered.count): \(applied.registered.joined(separator: ", ")). The launcher will list them at its next start."
            console.log("epic: registered \(applied.registered.count) game(s) with the launcher, revision \(applied.revision)")
            Task { await load() }
        } catch EpicImport.Failure.bottleIsLive {
            live = true
        } catch {
            failed = "Could not register: \(error)"
            console.error("epic: register failed: \(error)")
        }
    }
}
