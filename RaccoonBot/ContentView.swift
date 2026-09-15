//
//  ContentView.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 29/01/2026.
//

import SwiftUI
import Combine

enum AppRoute {
    case libraryPage
    case profilePage
}

final class Router: ObservableObject {
    @Published var route: AppRoute = .libraryPage

    // Convenience helpers if you like
    func go(to newRoute: AppRoute) {
        route = newRoute
    }
}

struct ContentView: View {
    @StateObject var router = Router()
    @StateObject var appGlobals = AppGlobals(
        selectedBottle: readUsrDefOptionString(key: "selectedBottle"),
        cxAppPath: readUsrDefOptionString(key: "cxAppPath"),
    )
    
    var body: some View {
        Group {
            switch(router.route){
            case .libraryPage:
                LibraryPage()
            case .profilePage:
                Text("Profile Page")
            }
        }
        .animation(.easeInOut, value: router.route)
        .preferredColorScheme(.dark)
        .environmentObject(router)
        .environmentObject(appGlobals)
        // RaccoonBot's own grey, not a shade of Procyon's indigo, so the fork
        // is not mistaken for the app it came from. The user tried a teal and
        // a dark green first and chose this. The stops are colours of their
        // own rather than the accent darkened: the accent is the raccoon's
        // mint, and mixing it with black stays mint. The top stop, #302F2F, is
        // the user's choice; the bottom one, #181717, keeps its hue and takes
        // two thirds of its OKLab lightness, the share the earlier stops used.
        //
        // Cards, the toolbar and the detail page are lighter than the
        // background, not darker: a surface darkened from a background this
        // dark all but disappears into it. They are the top stop mixed with
        // white -- 0.23 where a surface is drawn at 0.9 opacity, 0.26 where it
        // is drawn at 0.8 -- so both land on the same colour over the top stop.
        // Figures computed from the colour values (OKLab mixing, sRGB
        // compositing), not read back from SwiftUI's rendering as the green
        // theme's were: the stops 1.34:1 apart; a surface 1.80:1 off the top
        // stop and at least 2.26:1 off the bottom one; white text 7.4:1 on a
        // surface; the mint tags 5.5:1 against it. The pills keep Procyon's
        // green (ProcyonSecondary, #96B952), which the user preferred to a
        // cyan: black text on it 9.4:1, the pill 3.3:1 against a surface.
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        .raccoonBackgroundTop,
                        .raccoonBackgroundBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
            }
        )
        .onAppear() {
            if let steamPath = readUsrDefOptionString(key: "windowsSteamFolder") {
                console.log("fetching steam path")
                appGlobals.windowsSteamFolder = URL(string: steamPath)
                console.log(path.debugDescription)
            } else {
                console.log("windowsSteamFolder not set")
            }
            if(appGlobals.selectedBottle != ""){
                let usingURL = appGlobals.windowsSteamFolder?.appendingPathComponent("config", isDirectory: true) ?? URL(string: appGlobals.selectedBottle)!.appendingPathComponent(DEFAULT_STEAM_WINE_CONFIG_PATH)
                appGlobals.userID = getSteamUserID(usingURL: usingURL)
            }
        }
    }
}

#Preview {
    ContentView()
}

