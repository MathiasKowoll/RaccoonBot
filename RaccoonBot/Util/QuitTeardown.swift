//
//  QuitTeardown.swift
//  RaccoonBot
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AppKit

/// Closing a bottle that is still up before this application quits.
///
/// Measured 2026-09-15 at 18:44, with Steam open in the Steam bottle and no
/// game. This application answered applicationShouldTerminate with
/// NSTerminateNow and exited at 18:44:55.08. At 18:44:56.19 every wine process
/// of that bottle logged "Handling Quit AppleEvent", all in the same
/// millisecond. wine's Mac driver turns that into an end-session request
/// (winemac.drv, macdrv_app_quit_requested). The wineserver was gone 0.2 s
/// later, and Steam.exe was left without it: window up, buttons dead, near
/// 300% CPU, and no LogOff in its log. The quit at 10:50:44 the same morning
/// logged the same Quit in every wine process. The log does not say who sends
/// the Quit; it does show that it arrives.
///
/// So a quit with a bottle still up waits, and closes that bottle the way the
/// toolbar's Stop does -- game, exit syncs, clients, closeBottle -- before it
/// replies. By the time the Quit reaches wine, nothing is left to receive it.
enum QuitTeardown {

    /// How long a quit waits for its bottles before it goes anyway. Chosen,
    /// not measured: Steam's exit-sync wait and closeBottle's thirty seconds
    /// fit inside it with room to spare, and a teardown that hangs cannot hold
    /// the quit for ever.
    nonisolated static let bound: TimeInterval = 120

    /// The bottles a quit closes: those among `candidates` that have a wine
    /// server up, each once by directory, in the order given.
    ///
    /// Only bottles this application is configured with are candidates. A
    /// server up in any other prefix belongs to somebody else, CrossOver's own
    /// bottles among them, and is none of this quit's business. A bottle given
    /// by name alone cannot be looked in, so it is not closed. `hasServer` is a
    /// parameter so a test can say which bottles are up.
    nonisolated static func bottlesToClose(candidates: [String], hasServer: (URL) -> Bool) -> [String] {
        var seen: Set<String> = []
        return candidates.filter { candidate in
            guard let directory = BottleReference(candidate)?.directory else { return false }
            var key = directory.path(percentEncoded: false)
            while key.count > 1 && key.hasSuffix("/") { key.removeLast() }
            guard seen.insert(key).inserted else { return false }
            return hasServer(directory)
        }
    }

    /// The line the window shows while bottles close: their names, as
    /// CrossOver names them.
    nonisolated static func message(closing names: [String]) -> String {
        let shown = names.filter { !$0.isEmpty }
        guard !shown.isEmpty else { return "Closing Wine before quitting…" }
        return "Closing \(shown.joined(separator: " and ")) before quitting…"
    }

    nonisolated enum Decision: Equatable {
        /// Nothing is up, or nothing can be closed without an engine: quit as
        /// before.
        case quitNow
        /// Close these first, then quit.
        case closeFirst([String])
        /// A second request while the first is still closing. Refused; the
        /// first one carries on and quits when it is done.
        case refuse
    }

    nonisolated static func decide(closing: Bool, cxAppPath: String?, bottles: [String]) -> Decision {
        if closing { return .refuse }
        guard let cxAppPath, !cxAppPath.isEmpty, !bottles.isEmpty else { return .quitNow }
        return .closeFirst(bottles)
    }

    /// One reply to a quit answered later, however many paths reach it: the
    /// teardown finishing and the bound running out.
    nonisolated final class Reply: @unchecked Sendable {
        private let lock = NSLock()
        private var sent = false

        /// True the first time only.
        func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if sent { return false }
            sent = true
            return true
        }
    }

    /// The configured bottles, as the settings store them, and the Epic
    /// launcher's bottle, which can be a different one.
    static func candidates() -> [String] {
        let selected = readUsrDefOptionString(key: "selectedBottle") ?? ""
        var list = [selected]
        if ConfiguredBottles.armIncluded { list.append(readUsrDefOptionString(key: "selectedArmBottle") ?? "") }
        if let epic = EpicLaunch.target(settings: StoreConfig.settings(for: .epic), selectedBottle: selected) {
            list.append(epic.bottle)
        }
        return list
    }

    /// Whether a wine server is up in this bottle: something holds its server
    /// directory open, and a wineserver is among it.
    nonisolated static func serverIsUp(inBottleAt directory: URL) -> Bool {
        BottleProcesses.includesServer(BottleProcesses.running(inBottleAt: directory))
    }
}

/// The application delegate, for the one thing SwiftUI's App does not offer:
/// answering a quit later.
final class RaccoonBotAppDelegate: NSObject, NSApplicationDelegate {
    private var closing = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let cxAppPath = readUsrDefOptionString(key: "cxAppPath")
        // One lsof per candidate, a fifth of a second each, and only when no
        // teardown is already running.
        let bottles = closing ? [] : QuitTeardown.bottlesToClose(candidates: QuitTeardown.candidates(),
                                                                  hasServer: QuitTeardown.serverIsUp(inBottleAt:))
        switch QuitTeardown.decide(closing: closing, cxAppPath: cxAppPath, bottles: bottles) {
        case .quitNow:
            return .terminateNow
        case .refuse:
            console.log("quit: still closing the bottles from the first request")
            return .terminateCancel
        case .closeFirst(let bottles):
            guard let cxAppPath else { return .terminateNow }
            closing = true
            // Said on screen, and the window brought forward to say it: a quit
            // from the Dock finds this application in the background, and a
            // wait nobody can see reads as a quit that did nothing.
            QuitProgress.shared.message = QuitTeardown.message(closing: bottles.compactMap { BottleReference($0)?.name })
            NSApp.activate()
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            let reply = QuitTeardown.Reply()
            DispatchQueue.main.asyncAfter(deadline: .now() + QuitTeardown.bound) {
                guard reply.claim() else { return }
                console.warn("quit: the bottles did not close within \(Int(QuitTeardown.bound)) s; quitting anyway")
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            Task { @MainActor in
                for bottle in bottles {
                    let name = BottleReference(bottle)?.name ?? bottle
                    console.log("quit: closing \(name) first, as Stop does, so nothing in it is told to quit by macOS")
                    let press = stopPressed(isEpic: false, selectedBottle: bottle)
                    do {
                        try await stopEverything(press, target: .everything, cxAppPath: cxAppPath)
                    } catch {
                        console.error("quit: closing \(name) failed: \(error.localizedDescription)")
                    }
                }
                guard reply.claim() else { return }
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}
