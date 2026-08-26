//
//  ProcyonApp.swift
//  Procyon
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI
import CoreData

let appName = "procyon"
let windowWidth: CGFloat = 1024
let windowHeight: CGFloat = 750
let appWindowResizable: Bool = {
    let env = ProcessInfo.processInfo.environment["PROCYON_LAYOUT_RESIZABLE"]?.lowercased()
    switch env {
    case "1", "true", "yes":
        return true
    case "0", "false", "no":
        return false
    default:
        return false
    }
}()
var api = SteamAPI()

@main
struct ProcyonApp: App {
    init() {
        // Before anything reads a setting: the bundle identifier changed when
        // this stopped sharing one with the application it came from, and
        // UserDefaults.standard follows the identifier.
        Migration.run()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: appWindowResizable ? nil : windowWidth, height: appWindowResizable ? nil : windowHeight)
                .onAppear {
                    // Disable "Show Tab Bar" globally
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: windowWidth, height: windowHeight)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { } // replaces "New Window" with nothing
        }
    }
    
}
