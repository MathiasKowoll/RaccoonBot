//
//  MGVFCatalogTests.swift
//  ProcyonTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import Procyon

private final class MemoryStore: MGVFDecisionStore {
    var pairs: [String: String] = [:]
    var dismissed: Set<String> = []
    func pairedScript(for folder: String) -> String? { pairs[folder] }
    func setPairedScript(_ script: String?, for folder: String) {
        if let script { pairs[folder] = script } else { pairs.removeValue(forKey: folder) }
    }
    func isDismissed(_ folder: String) -> Bool { dismissed.contains(folder) }
    func setDismissed(_ value: Bool, for folder: String) {
        if value { dismissed.insert(folder) } else { dismissed.remove(folder) }
    }
}

private func game(_ script: String, exe: String = "") -> MGVFGame {
    MGVFGame(name: script.replacingOccurrences(of: "install-", with: ""),
             script: script, exe: exe, files: ["proxy.dll"],
             carrier: "carrier.dll", keptAs: "carrier_real.dll",
             carrierDir: "", why: "test", writesRegistry: false,
             backend: nil, gptk: nil, env: nil)
}

private func manifest(_ games: [MGVFGame]) -> MGVFManifest {
    MGVFManifest(schema: 2, version: "v0", commit: "test", games: games, scopeWarning: nil)
}

private func makeFolder(_ build: (URL) throws -> Void) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mgvf-cat-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try build(dir)
    return dir.path(percentEncoded: false)
}

struct MGVFMatchingTests {

    @Test func matchesByTheShippingExecutable() throws {
        let folder = try makeFolder { dir in
            try "x".write(to: dir.appendingPathComponent("NieR Replicant ver.1.22474487139.exe"),
                          atomically: true, encoding: .utf8)
        }
        defer { try? FileManager.default.removeItem(atPath: folder) }

        let catalog = MGVFCatalog(
            manifest: manifest([game("install-nier-bridge.sh", exe: "NieR Replicant ver.1.22474487139.exe"),
                                game("install-tmnt-fix.sh", exe: "TMNTSF.exe")]),
            directory: URL(fileURLWithPath: "/tmp"),
            store: MemoryStore())

        #expect(catalog.entry(forFolder: folder)?.script == "install-nier-bridge.sh")
    }

    @Test func findsAnUnrealExecutableUnderBinariesWin64() throws {
        // The Unreal titles keep the shipping binary at
        // <folder>/<Project>/Binaries/Win64, not in the folder itself.
        let folder = try makeFolder { dir in
            let deep = dir.appendingPathComponent("Sparta/Binaries/Win64")
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            try "x".write(to: deep.appendingPathComponent("Sparta-Win64-Shipping.exe"),
                          atomically: true, encoding: .utf8)
        }
        defer { try? FileManager.default.removeItem(atPath: folder) }

        let catalog = MGVFCatalog(
            manifest: manifest([game("install-runtime-fix.sh", exe: "Sparta-Win64-Shipping.exe")]),
            directory: URL(fileURLWithPath: "/tmp"),
            store: MemoryStore())

        #expect(catalog.entry(forFolder: folder)?.script == "install-runtime-fix.sh")
    }

    @Test func doesNotGuessFromTheFolderName() throws {
        // The folder is named "Sparta" and the entry is for Mortal Shell 2.
        // Valve chooses that name and it says nothing about the title, which is
        // exactly why the executable is the identity.
        let folder = try makeFolder { dir in
            try "x".write(to: dir.appendingPathComponent("something-else.exe"),
                          atomically: true, encoding: .utf8)
        }
        defer { try? FileManager.default.removeItem(atPath: folder) }

        let catalog = MGVFCatalog(manifest: manifest([game("install-runtime-fix.sh", exe: "Sparta-Win64-Shipping.exe")]),
                                  directory: URL(fileURLWithPath: "/tmp"),
                                  store: MemoryStore())
        #expect(catalog.entry(forFolder: folder) == nil)
    }

    @Test func fallsBackToWhatTheUserPaired() throws {
        // Eight of the ten entries carry no executable today, so this is not a
        // safety net for a bad guess -- it is the only answer available.
        let folder = try makeFolder { _ in }
        defer { try? FileManager.default.removeItem(atPath: folder) }

        let store = MemoryStore()
        let catalog = MGVFCatalog(manifest: manifest([game("install-p5s-bridge.sh")]),
                                  directory: URL(fileURLWithPath: "/tmp"),
                                  store: store)

        #expect(catalog.entry(forFolder: folder) == nil)
        catalog.pair(folder: folder, to: catalog.pairableGames[0])
        #expect(catalog.entry(forFolder: folder)?.script == "install-p5s-bridge.sh")
        catalog.unpair(folder: folder)
        #expect(catalog.entry(forFolder: folder) == nil)
    }

    @Test func remembersPerFolderNotPerTitle() throws {
        // Two copies of the same game in two libraries are two installations.
        let a = try makeFolder { _ in }, b = try makeFolder { _ in }
        defer { try? FileManager.default.removeItem(atPath: a); try? FileManager.default.removeItem(atPath: b) }

        let catalog = MGVFCatalog(manifest: manifest([game("install-nioh-bridge.sh")]),
                                  directory: URL(fileURLWithPath: "/tmp"),
                                  store: MemoryStore())
        catalog.pair(folder: a, to: catalog.pairableGames[0])
        #expect(catalog.entry(forFolder: a) != nil)
        #expect(catalog.entry(forFolder: b) == nil)
    }
}

struct MGVFStateTests {

    @Test func installedIsPatchedAndAbsentNeedsPatching() {
        func result(_ state: FixState?) -> MGVFResult {
            MGVFResult(state: state, stdout: "", stderr: "", exitCode: 0)
        }
        #expect(MGVFCatalog.state(from: result(.installed)) == .patched)
        #expect(MGVFCatalog.state(from: result(.absent)) == .needsPatch)
    }

    @Test func brokenAndHalfAskToBeAppliedAgain() {
        // A fix that is present and not working is a reason to offer applying
        // it, not a reason to claim nothing is there.
        func result(_ state: FixState?) -> MGVFResult {
            MGVFResult(state: state, stdout: "", stderr: "", exitCode: 0)
        }
        #expect(MGVFCatalog.state(from: result(.broken)) == .needsPatch)
        #expect(MGVFCatalog.state(from: result(.half)) == .needsPatch)
    }

    @Test func noAnswerIsNotAbsent() {
        // The whole point. "Could not look" must never be shown as "not
        // installed", because one of those is a reason to write to the user's
        // game folder and the other is not.
        let result = MGVFResult(state: nil,
                                stdout: "",
                                stderr: "install-nier-bridge.sh: line 40: HOME: this needs HOME\n",
                                exitCode: 1)
        let state = MGVFCatalog.state(from: result)
        #expect(state != .needsPatch)
        if case .unknown(let detail) = state {
            #expect(detail.contains("HOME"))
        } else {
            Issue.record("expected unknown, got \(state)")
        }
    }

    @Test func redactsTheHomeFromWhatItShows() {
        let result = MGVFResult(state: nil,
                                stdout: "",
                                stderr: "cannot read \(NSHomeDirectory())/Library/x\n",
                                exitCode: 1)
        if case .unknown(let detail) = MGVFCatalog.state(from: result) {
            #expect(!detail.contains(NSHomeDirectory()))
        } else {
            Issue.record("expected unknown")
        }
    }

    @Test func aDeliberateRemovalIsNotReOffered() async throws {
        // A patch can stop being necessary. Asking again on every launch turns
        // the user's decision into a nag.
        let folder = try makeFolder { _ in }
        defer { try? FileManager.default.removeItem(atPath: folder) }

        let store = MemoryStore()
        let catalog = MGVFCatalog(manifest: manifest([game("install-dwo-bridge.sh")]),
                                  directory: URL(fileURLWithPath: "/tmp"),
                                  store: store)
        catalog.pair(folder: folder, to: catalog.pairableGames[0])
        catalog.dismiss(folder: folder)
        #expect(await catalog.state(forFolder: folder) == .dismissed)

        catalog.undismiss(folder: folder)
        // With no real script at /tmp the run fails, which is `unknown` -- and
        // that is the correct answer, not `needsPatch`.
        let state = await catalog.state(forFolder: folder)
        #expect(state != .dismissed)
        #expect(state != .needsPatch)
    }

    @Test func aTitleWithNoFixIsNotAProblem() async throws {
        let folder = try makeFolder { _ in }
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let catalog = MGVFCatalog(manifest: manifest([]),
                                  directory: URL(fileURLWithPath: "/tmp"),
                                  store: MemoryStore())
        #expect(await catalog.state(forFolder: folder) == .noFix)
    }
}

struct MGVFRecommendedOptionsTests {

    private func entry(backend: String?, gptk: String?, env: [String: String]? = nil) -> MGVFGame {
        MGVFGame(name: "t", script: "s.sh", exe: "t.exe", files: [],
                 carrier: "c.dll", keptAs: "c_real.dll", carrierDir: "", why: "",
                 writesRegistry: false, backend: backend, gptk: gptk, env: env)
    }

    @MainActor
    private func options(_ game: MGVFGame) -> GameOptionsData? {
        let c = MGVFCoordinator()
        c.setEntryForTesting(game)
        return c.recommendedOptions
    }

    @MainActor
    @Test func pinsTheGenerationATitleRequires() {
        // Life is Strange needs 4 and Procyon's default branch installs 3, so
        // this pair had been receiving the generation that breaks them.
        #expect(options(entry(backend: "d3dmetal", gptk: "4"))?.cxGraphicsBackend == "d3dmetal4")
        #expect(options(entry(backend: "d3dmetal", gptk: "3"))?.cxGraphicsBackend == "d3dmetal3")
    }

    @MainActor
    @Test func leavesTheChoiceAloneWhenEitherGenerationServes() {
        // Empty is an answer: the catalogue reports a generation only where it
        // is a requirement. Pinning one for a title that does not care is worse
        // than not touching it.
        #expect(options(entry(backend: "d3dmetal", gptk: nil)) == nil)
        #expect(options(entry(backend: nil, gptk: nil)) == nil)
    }

    @MainActor
    @Test func dxmtIsOneChoiceNotTwo() {
        #expect(options(entry(backend: "dxmt", gptk: nil))?.cxGraphicsBackend == "dxmt")
        #expect(options(entry(backend: "dxmt", gptk: "3"))?.cxGraphicsBackend == "dxmt")
    }

    @MainActor
    @Test func carriesEnvironmentOnlyWhenThereIsSome() {
        #expect(options(entry(backend: nil, gptk: nil, env: [:])) == nil)
        let withEnv = options(entry(backend: nil, gptk: nil, env: ["D3DM_MTL4": "0"]))
        #expect(withEnv?.envVariables == "D3DM_MTL4=0")
    }
}
