//
//  MGVFCatalogTests.swift
//  RaccoonBotTests
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
import Foundation
@testable import RaccoonBot

private final class MemoryStore: MGVFDecisionStore {
    var fingerprints: [String: String] = [:]
    func appliedFingerprint(for folder: String) -> String? { fingerprints[folder] }
    func setAppliedFingerprint(_ fingerprint: String?, for folder: String) {
        if let fingerprint { fingerprints[folder] = fingerprint } else { fingerprints.removeValue(forKey: folder) }
    }
    var pairs: [String: String] = [:]
    var dismissed: Set<String> = []
    func pairedTitle(for folder: String) -> String? { pairs[folder] }
    func setPairedTitle(_ title: String?, for folder: String) {
        if let title { pairs[folder] = title } else { pairs.removeValue(forKey: folder) }
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
             carrierDir: "", why: "test", writesRegistry: false, scope: nil,
             backend: nil, gptk: nil, env: nil, codec: nil)
}

private func manifest(_ games: [MGVFGame]) -> MGVFManifest {
    MGVFManifest(schema: 2, version: "v0", commit: "test", games: games, scopeWarning: nil, engine: nil)
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
                 writesRegistry: false, scope: nil, backend: backend, gptk: gptk, env: env, codec: nil)
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
    @Test func aRecommendationCarriesOnlyWhatItRecommends() {
        // The one that would have cost real settings. GameOptionsData has two
        // initialisers and they mean opposite things: init(data:) is a snapshot
        // of a whole GameOptions, and 19 of that class's 23 fields are not
        // optional, so a fresh one is nineteen concrete defaults wearing the
        // costume of an empty patch. importAutoConfig writes every non-nil
        // field, so "recommend dxmt for this title" would also have reset the
        // frame cap, the environment, the ARM bottle and sixteen others -- to
        // legal values, which is why nothing would have looked wrong.
        let patch = options(entry(backend: "dxmt", gptk: nil))
        #expect(patch?.cxGraphicsBackend == "dxmt")
        #expect(patch?.envVariables == nil)
        #expect(patch?.gameArguments == nil)
        #expect(patch?.useArmBottle == nil)
        #expect(patch?.wineMSync == nil)
        #expect(patch?.mtlHudEnabled == nil)
        #expect(patch?.x87PatchEnabled == nil)
        #expect(patch?.dx9PatchEnabled == nil)
        #expect(patch?.advertiseAVX == nil)
        #expect(patch?.dxmtPreferredMaxFrameRate == nil)
        #expect(patch?.dxmtMetalFXSpatial == nil)
        #expect(patch?.dxmtMetalSpatialUpscaleFactor == nil)

        // And the same for the environment branch: it must not drag a backend
        // along with it.
        let envOnly = options(entry(backend: nil, gptk: nil, env: ["FEX_X87REDUCEDPRECISION": "1"]))
        #expect(envOnly?.envVariables == "FEX_X87REDUCEDPRECISION=1")
        #expect(envOnly?.cxGraphicsBackend == nil)
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

struct MGVFSchemaThreeTests {

    private func titled(_ name: String, script: String, gptk: String? = "", codec: String? = "") -> MGVFGame {
        MGVFGame(name: name, script: script, exe: "", files: [], carrier: "c.dll",
                 keptAs: "c_real.dll", carrierDir: "Engine/Binaries/ThirdParty/Ogg/Win64",
                 why: "because \(name)", writesRegistry: false, scope: nil,
                 backend: "d3dmetal", gptk: gptk, env: nil, codec: codec)
    }

    @Test func pairingKeepsTheTitleNotTheScript() throws {
        // install-runtime-fix.sh serves four games. Keyed by script, pairing
        // "Wo Long" showed "DYNASTY WARRIORS: ORIGINS" -- wrong name, wrong
        // reason, in the dialog that is about to write to disk.
        let a = titled("Wo Long: Fallen Dynasty", script: "install-runtime-fix.sh")
        let b = titled("Mortal Shell 2", script: "install-runtime-fix.sh")
        let folder = try makeSharedFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }

        let catalog = MGVFCatalog(manifest: MGVFManifest(schema: 3, version: "v", commit: "c",
                                                         games: [a, b], scopeWarning: nil, engine: nil),
                                  directory: URL(fileURLWithPath: "/tmp"),
                                  store: SharedMemoryStore())
        catalog.pair(folder: folder, to: b)
        #expect(catalog.entry(forFolder: folder)?.name == "Mortal Shell 2")
        #expect(catalog.entry(forFolder: folder)?.why == "because Mortal Shell 2")
    }

    @Test func aCodecOnlyTitleHasNothingToInstall() async throws {
        // Devil May Cry 5 needs a staged decoder and no file beside the game.
        // Offering to install something would be offering nothing.
        let folder = try makeSharedFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let dmc = titled("Devil May Cry 5", script: "", codec: "libgstlibav")
        let catalog = MGVFCatalog(manifest: MGVFManifest(schema: 3, version: "v", commit: "c",
                                                         games: [dmc], scopeWarning: nil, engine: nil),
                                  directory: URL(fileURLWithPath: "/tmp"),
                                  store: SharedMemoryStore())
        catalog.pair(folder: folder, to: dmc)
        #expect(dmc.isCodecOnly)
        #expect(await catalog.state(forFolder: folder) == .noFix)
    }

    @Test func namesTheCarrierWhereItActuallyIs() {
        // Five of seventeen keep the carrier in a subfolder. The dialog that
        // says what is about to be renamed must name that path, not the game
        // folder.
        let g = titled("Mortal Shell 2", script: "install-runtime-fix.sh")
        let path = g.carrierPath(inGameFolder: "/games/Sparta")
        #expect(path == "/games/Sparta/Engine/Binaries/ThirdParty/Ogg/Win64/c.dll")
    }
}

private final class SharedMemoryStore: MGVFDecisionStore {
    var fingerprints: [String: String] = [:]
    func appliedFingerprint(for folder: String) -> String? { fingerprints[folder] }
    func setAppliedFingerprint(_ fingerprint: String?, for folder: String) {
        if let fingerprint { fingerprints[folder] = fingerprint } else { fingerprints.removeValue(forKey: folder) }
    }
    var pairs: [String: String] = [:]
    var dismissed: Set<String> = []
    func pairedTitle(for folder: String) -> String? { pairs[folder] }
    func setPairedTitle(_ title: String?, for folder: String) {
        if let title { pairs[folder] = title } else { pairs.removeValue(forKey: folder) }
    }
    func isDismissed(_ folder: String) -> Bool { dismissed.contains(folder) }
    func setDismissed(_ value: Bool, for folder: String) {
        if value { dismissed.insert(folder) } else { dismissed.remove(folder) }
    }
}

private func makeSharedFolder() throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mgvf-s3-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path(percentEncoded: false)
}

struct LaunchGateTests {

    private func game(native: Bool = false, custom: Bool = false, exe: URL? = nil) -> Game {
        var g = Game(from: Game.steamMock, id: "1", isNative: native,
                     downloadProgress: 100, isInstalled: true, appNames: [])
        g.isCustom = custom
        g.appExeURL = exe
        return g
    }

    @Test func refusesToStartAWindowsTitleThatNeedsItsFix() {
        // The gate this whole project exists for. It used to live inside
        // GameThumbnail, which meant the grid was the only place that checked;
        // adding Play to the list by copying the launch code would have been a
        // second copy of a safety check, free to drift out of step.
        #expect(GameLauncher.outcome(for: game(), isPlaying: false, needsFix: true) == .needsFix)
        #expect(GameLauncher.outcome(for: game(), isPlaying: false, needsFix: false) == .started)
    }

    @Test func doesNotGateANativeTitle() {
        // The fixes are for Windows video decoding under CrossOver. A macOS
        // build has nothing to patch, and stopping it would be a warning about
        // something that cannot apply.
        #expect(GameLauncher.outcome(for: game(native: true), isPlaying: false, needsFix: true) == .started)
    }

    @Test func willNotStartACustomEntryWithNothingToRun() {
        #expect(GameLauncher.outcome(for: game(custom: true, exe: nil),
                                     isPlaying: false, needsFix: false) == .noExecutable)
    }

    @Test func doesNotStartWhatIsAlreadyRunning() {
        #expect(GameLauncher.outcome(for: game(), isPlaying: true, needsFix: true) == .alreadyPlaying)
    }
}

struct PatchAllTargetTests {

    private func meta(_ dir: String, downloaded: Bool = true, root: URL) -> GamesMeta {
        let m = GamesMeta(appid: "1", installdir: dir,
                          bytesDownloaded: downloaded ? "0" : "5",
                          BytesTodownload: downloaded ? "0" : "10")
        m.gameURL = root.appendingPathComponent(dir)
        m.name = dir
        return m
    }

    @Test func skipsTitlesWhoseFolderIsNotThere() throws {
        // Steam libraries live on external drives. An entry for an unmounted
        // one is a path that simply is not there, and patching it would be
        // writing into nothing -- or worse, into a mount point.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("patchall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Here"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let targets = PatchAll.targets(from: [meta("Here", root: root),
                                              meta("Gone", root: root)],
                                       needsPatch: { _ in true })
        #expect(targets.map(\.title) == ["Here"])
    }

    @Test func skipsWhatIsNotFinishedDownloading() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("patchall-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Half"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A half-downloaded game has no executable to patch yet.
        #expect(PatchAll.targets(from: [meta("Half", downloaded: false, root: root)],
                                 needsPatch: { _ in true }).isEmpty)
    }

    @Test func skipsOwnedTitlesThatAreNotInstalled() {
        // fetchOwnedGamesIDs used to append metas with an empty installdir.
        // Those are titles you own, not titles that are here.
        let m = GamesMeta(appid: "1", installdir: "", bytesDownloaded: "0", BytesTodownload: "0")
        #expect(PatchAll.targets(from: [m], needsPatch: { _ in true }).isEmpty)
    }
}
