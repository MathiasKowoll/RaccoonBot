//
//  GameLauncher.swift
//  RaccoonBot
//
//  Starting a game, from wherever the user asked.
//
//  This lived inside GameThumbnail, which meant the grid was the only place a
//  game could be launched from. Adding a Play button to the list view by
//  copying it would have copied the fix gate too -- and a second copy of a
//  safety check is a second copy that can drift out of step with the first.
//  There is one launch path, and the gate is in it.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// What happened, so the caller can say so in its own way.
enum LaunchOutcome: Equatable {
    case started
    /// The title needs its video fix and was NOT started.
    ///
    /// Asked before the game starts: that is the moment the reason is obvious,
    /// and the only moment a user who never opens the options hears it at all.
    /// It asks rather than acts -- applying a fix renames a file in the game
    /// folder, and doing that behind a play button is not something to do
    /// quietly.
    case needsFix
    /// A custom entry with nothing to run.
    case noExecutable
    case alreadyPlaying
}

/// Not observable: it publishes nothing. What the interface watches --
/// playingID, the loader -- already lives on LibraryPageGlobals, and a second
/// source for the same state is how two views end up disagreeing about whether
/// a game is running.
@MainActor
final class GameLauncher {
    static let shared = GameLauncher()

    private var observers: [String: TerminationObserver] = [:]

    /// The engine's SeizeDevice answer, per engine file as it is on disk.
    ///
    /// The question reads all of winebus.sys, and it is asked on every launch
    /// that starts a Windows title. Keyed on the file's modification date as
    /// well as its path -- a stat, not a read -- because an engine can be
    /// rebuilt in place while this application runs, and a stale "no" is a
    /// console line that stays away until the next restart.
    private var seizeAnswers: [String: Bool] = [:]

    /// Decides whether a title may start, without starting it.
    ///
    /// Separate so the gate can be tested without launching anything, and so
    /// every caller asks the same question. Nothing about a controller is in
    /// it: a pad is never a reason not to start.
    nonisolated static func outcome(for game: Game,
                                    isPlaying: Bool,
                                    needsFix: Bool,
                                    hasEpicLauncher: Bool = true) -> LaunchOutcome {
        if isPlaying { return .alreadyPlaying }
        if game.isNative { return .started }
        if game.isCustom == true && game.appExeURL == nil { return .noExecutable }
        // An Epic title is started by the Epic launcher, through its URI
        // scheme; with no launcher in the bottle there is nothing to start it.
        if game.isEpic && !hasEpicLauncher { return .noExecutable }
        if needsFix { return .needsFix }
        return .started
    }

    /// The console's lines about macOS's idle cut for one launch: measurement
    /// only, never an outcome.
    ///
    /// The pads are a closure, called only for a Windows title whose launch
    /// goes ahead: asking IOKit, and possibly the engine binary, is not free,
    /// and a title that is running, native, has nothing to run or needs its
    /// fix has no business paying for it. See MacIdleDisconnect.
    nonisolated static func padLines(for game: Game, outcome: LaunchOutcome,
                                     padsAtRisk: () -> [SonyPads.Pad]) -> [String] {
        guard outcome == .started, !game.isNative else { return [] }
        return padsAtRisk().map(MacIdleDisconnect.consoleLine(for:))
    }

    /// Measures those lines for a launch that is going ahead, and holds them
    /// until the title is seen running. Called by the detail page's own
    /// launch too, which does not come through `play`.
    ///
    /// Measured here, before the launch, because that is the moment the
    /// detector was written for; whether the driver's attachment reads the
    /// same once the bottle holds the pad has not been looked at. Written
    /// only from the tracker's onLoad, because a launch can still stop short
    /// after this -- no bottle, a refused engine, a throw -- and a line about
    /// a bottle holding the pad is not true of a title that never started.
    func padLinesAtLaunch(for game: Game, outcome: LaunchOutcome, cxAppPath: String?) -> PendingPadLines {
        PendingPadLines(Self.padLines(for: game, outcome: outcome) {
            let started = Date()
            let atRisk = MacIdleDisconnect.padsAtRisk(pads: SonyPads.attached(),
                                                      driverSerials: MacIdleDisconnect.driverSerials(),
                                                      engineSeizes: engineSeizesThePad(cxAppPath: cxAppPath))
            // Its main-actor cost has not been measured; this line is how.
            console.log("controller: gamepad driver check took \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            return atRisk
        })
    }

    private func engineSeizesThePad(cxAppPath: String?) -> Bool {
        guard let cxAppPath, !cxAppPath.isEmpty else { return false }
        let sys = cxAppPath + "/Contents/SharedSupport/CrossOver/lib/wine/x86_64-windows/winebus.sys"
        let modified = (try? FileManager.default.attributesOfItem(atPath: sys)[.modificationDate] as? Date)
            .map { String($0.timeIntervalSince1970) } ?? "absent"
        let key = sys + "|" + modified
        if let known = seizeAnswers[key] { return known }
        let answer = DualSenseRoute.engineSeizesThePad(cxAppPath: cxAppPath)
        seizeAnswers[key] = answer
        return answer
    }

    @discardableResult
    func play(_ item: Game,
              updatedItem: Game,
              isPlaying: Bool,
              gameFolder: String?,
              appGlobals: AppGlobals,
              libraryPageGlobals: LibraryPageGlobals,
              fixes: MGVFLibrary) -> LaunchOutcome {

        let needsFix = gameFolder.map { fixes.needsPatch(folder: $0) } ?? false
        let epicPlan = item.isEpic
            ? EpicLaunch.plan(for: item, settings: StoreConfig.settings(for: .epic), selectedBottle: appGlobals.selectedBottle)
            : nil
        let outcome = Self.outcome(for: item, isPlaying: isPlaying, needsFix: needsFix,
                                   hasEpicLauncher: !item.isEpic || epicPlan != nil)
        guard outcome == .started else {
            if outcome == .noExecutable {
                console.error(item.isEpic ? "epic: no Epic Games Launcher in the bottle to start \(item.name); set one up from the Epic panel"
                                          : "custom game doesn't have an executable associated")
            }
            return outcome
        }
        let padLines = padLinesAtLaunch(for: item, outcome: outcome, cxAppPath: appGlobals.cxAppPath)

        libraryPageGlobals.selectedGame = updatedItem
        libraryPageGlobals.setLoader(state: true)
        // Until the game is seen running, a pad left still is not idle.
        IdlePadWatcher.shared.launchStarted()

        Task {
            do {
                let id = item.steamAppID != 0 ? String(describing: item.steamAppID) : String(describing: item.id)
                let gameOptKey = GameDefaults.key(forAppID: item.steamAppID,
                                                  id: String(describing: item.id))
                let gameOptions = GameOptions()
                // A title with nothing saved is configured here and then read
                // back, rather than launched from a fresh object. Falling back
                // to defaults is what let the interface show one toolkit while
                // the launch installed another -- see GameDefaults.
                GameDefaults.seedIfAbsent(key: gameOptKey)
                if let saved: GameOptionsData = readUsrDefData(key: gameOptKey) {
                    gameOptions.set(data: saved)
                    console.log("options retrieved")
                } else {
                    // Now genuinely exceptional: the write above failed.
                    console.error("no saved options for \(gameOptKey) and none could be written; "
                                  + "launching on defaults, which may not be what is configured")
                }

                // Where this title actually runs, decided once.
                //
                // The launch below worked this out for itself and the watcher
                // above was given something else: for a title with the ARM
                // toggle on, the game started in the ARM bottle while the
                // watcher polled, closed and quit the other one. Since the
                // launch generation began counting per bottle, a disagreement
                // here also means a teardown comparing a counter its own
                // launch never bumped -- which reads as "nothing has been
                // launched since" and is the answer that kills a running
                // game. One value, both places.
                let launchBottle = epicPlan?.bottle
                    ?? (gameOptions.useArmBottle ? appGlobals.selectedArmBottle : appGlobals.selectedBottle)

                Task(priority: .background) {
                    let observer = try await getGameTracker(
                        appNames: updatedItem.appNames,
                        cxAppPath: appGlobals.cxAppPath!,
                        bottle: launchBottle,
                        onLoad: { appName in
                            libraryPageGlobals.playingID = item.id
                            Task { @MainActor in padLines.write() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                libraryPageGlobals.setLoader(state: false)
                                Task { activateApp(appName) }
                            }
                        },
                        onTerminate: {
                            libraryPageGlobals.setLoader(state: false)
                            libraryPageGlobals.playingID = nil
                            Task { @MainActor in self.observers[item.id] = nil }
                        },
                        isNative: item.isNative,
                        steamID: (item.isCustom == true || item.isEpic) ? nil : item.steamAppID,
                        steamPath: appGlobals.windowsSteamFolder?.path(percentEncoded: false) ?? "",
                        isEpic: item.isEpic)
                    await MainActor.run { self.observers[item.id] = observer }
                }

                if item.isNative {
                    try await launchNativeGame(id: String(item.steamAppID),
                                               cxAppPath: appGlobals.cxAppPath ?? "",
                                               selectedBottle: appGlobals.selectedBottle,
                                               options: gameOptions,
                                               appExeURL: item.appExeURL)
                } else {
                    let steamExePath = appGlobals.windowsSteamFolder?
                        .appendingPathComponent("Steam.exe").path(percentEncoded: false)
                        ?? "C:\\Program Files (x86)\\Steam\\Steam.exe"
                    try await launchWindowsGame(id: String(item.steamAppID),
                                                cxAppPath: appGlobals.cxAppPath ?? "",
                                                // An Epic title runs where its launcher is.
                                                selectedBottle: launchBottle,
                                                steamExePath: steamExePath,
                                                options: gameOptions,
                                                appExeURL: epicPlan?.launcher ?? item.appExeURL,
                                                launcherURI: epicPlan?.uri)
                }
            } catch {
                console.error(String(reflecting: error))
                libraryPageGlobals.setLoader(state: false)
            }
        }
        return .started
    }
}

/// One launch's console lines about macOS's idle cut, measured before the
/// launch and written the first time the title is seen running.
///
/// Once: the trackers call onLoad again when a title comes back after a gap,
/// and that is the same session, not a second measurement.
@MainActor
final class PendingPadLines {
    private var lines: [String]

    init(_ lines: [String]) { self.lines = lines }

    /// The lines not yet written, and none from then on.
    func take() -> [String] {
        defer { lines = [] }
        return lines
    }

    func write() { take().forEach { console.warn($0) } }
}
