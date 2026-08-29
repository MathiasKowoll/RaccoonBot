//
//  RaccoonBotApp.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI
import CoreData

/// NOT renamed with the application: it is a path component of the downloads
/// cache (see Misc.swift), so changing it abandons what is there rather than
/// moving it. Same rule as the bottles directory and the app group.
let appName = "procyon"
/// Wide enough that the adaptive grid opens at four columns: the cards ask for
/// 250 points minimum, so four of them plus spacing and padding needs roughly
/// 1100 of content.
let windowWidth: CGFloat = 1280
let windowHeight: CGFloat = 820
/// Never narrower than the toolbar needs.
///
/// 1024 was this window's fixed size before it could be resized, and it is
/// still the right floor -- not for the grid, which reflows happily at 860, but
/// for the toolbar. macOS collapses a toolbar group into an overflow menu the
/// moment it decides there is no room, and it decides that silently: controls
/// simply stop existing. A minimum that fits the pill means it never has to.
let windowMinWidth: CGFloat = 1024
let windowMinHeight: CGFloat = 600

/// Resizable, and therefore able to go full screen.
///
/// This defaulted to FALSE, and together with .frame(width:height:) and
/// .windowResizability(.contentSize) it pinned the window at 1024x750 with the
/// green button inert. There was no reason for it: the library grid is
/// GridItem(.adaptive(minimum: 250, maximum: 325)) and already reflows, so the
/// only thing the lock achieved was keeping it at three columns forever.
///
/// The environment variable stays as an escape hatch, under both names, in case
/// a layout somewhere really does need the old fixed geometry.
let appWindowResizable: Bool = {
    let environment = ProcessInfo.processInfo.environment
    let value = (environment["RACCOONBOT_LAYOUT_RESIZABLE"]
                 ?? environment["PROCYON_LAYOUT_RESIZABLE"])?.lowercased()
    switch value {
    case "0", "false", "no": return false
    default: return true
    }
}()
var api = SteamAPI()

@main
struct RaccoonBotApp: App {
    init() {
        // Before anything reads a setting: the bundle identifier changed when
        // this stopped sharing one with the application it came from, and
        // UserDefaults.standard follows the identifier.
        Migration.run()

        // Anything wine left running belongs to a session that is over: this
        // application closed before a bottle came down, or a game was force
        // quit. Those services keep the bottle's devices and registry claimed
        // and the next launch fails because of them -- one survived exactly
        // that way tonight and was still there half an hour later.
        //
        // Off the main thread because it asks lsof about every prefix on the
        // machine, which is a second and a half, and nobody should wait for it
        // to see a window.
        Task(priority: .background) {
            await BottleProcesses.clearResidualAtStartup()
        }

        // A fixes bundle published while this was open used to go unseen until
        // the next launch, and the catalogue was only ever fetched once. The
        // check has existed, with its tests and its six-hour throttle, since
        // before tonight -- nothing called it.
        Task(priority: .background) {
            await MGVFLibrary.shared.watchForNewFixes()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: appWindowResizable ? windowMinWidth : windowWidth,
                       maxWidth: appWindowResizable ? .infinity : windowWidth,
                       minHeight: appWindowResizable ? windowMinHeight : windowHeight,
                       maxHeight: appWindowResizable ? .infinity : windowHeight)
                .onAppear {
                    // Disable "Show Tab Bar" globally
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: windowWidth, height: windowHeight)
        // contentSize pins the window to exactly what the content asks for,
        // which with a fixed frame means it cannot be dragged or zoomed at all.
        // contentMinSize honours the minimum and lets the user have the rest.
        .windowResizability(appWindowResizable ? .contentMinSize : .contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { } // replaces "New Window" with nothing
        }
    }
    
}
