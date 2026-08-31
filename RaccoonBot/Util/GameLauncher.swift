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

    /// Decides whether a title may start, without starting it.
    ///
    /// Separate so the gate can be tested without launching anything, and so
    /// every caller asks the same question.
    nonisolated static func outcome(for game: Game,
                                    isPlaying: Bool,
                                    needsFix: Bool) -> LaunchOutcome {
        if isPlaying { return .alreadyPlaying }
        if game.isNative { return .started }
        if game.isCustom == true && game.appExeURL == nil { return .noExecutable }
        if needsFix { return .needsFix }
        return .started
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
        let outcome = Self.outcome(for: item, isPlaying: isPlaying, needsFix: needsFix)
        guard outcome == .started else {
            if outcome == .noExecutable {
                console.error("custom game doesn't have an executable associated")
            }
            return outcome
        }

        libraryPageGlobals.selectedGame = updatedItem
        libraryPageGlobals.setLoader(state: true)

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

                Task(priority: .background) {
                    let observer = try await getGameTracker(
                        appNames: updatedItem.appNames,
                        cxAppPath: appGlobals.cxAppPath!,
                        bottle: appGlobals.selectedBottle,
                        onLoad: { appName in
                            libraryPageGlobals.playingID = item.id
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
                        steamID: item.isCustom == true ? nil : item.steamAppID,
                        steamPath: appGlobals.windowsSteamFolder?.path(percentEncoded: false) ?? "")
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
                                                selectedBottle: gameOptions.useArmBottle
                                                    ? appGlobals.selectedArmBottle
                                                    : appGlobals.selectedBottle,
                                                steamExePath: steamExePath,
                                                options: gameOptions,
                                                appExeURL: item.appExeURL)
                }
            } catch {
                console.error(String(reflecting: error))
                libraryPageGlobals.setLoader(state: false)
            }
        }
        return .started
    }
}
