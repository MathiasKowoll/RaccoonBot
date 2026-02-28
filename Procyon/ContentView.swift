//
//  ContentView.swift
//  Procyon
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

<<<<<<< Updated upstream
final class AppGlobals: ObservableObject {
    @Published var selectedBottle: String = ""
    @Published var cxAppPath: String?
    
    init(selectedBottle: String? = "", cxAppPath: String? = nil) {
        self.selectedBottle = readUsrDefOptionString(key: "selectedBottle") ?? ""
        self.cxAppPath = readUsrDefOptionString(key: "cxAppPath")
    }
}

=======
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
            case .profile:
                VStack() {
                    Text("Profile Page")
                    Button("Go to Library") {
                        router.go(to: .library)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
=======
            case .profilePage:
                ProfilePage()
>>>>>>> Stashed changes
            }
        }
        .animation(.easeInOut, value: router.route)
        .preferredColorScheme(.dark)
        .environmentObject(router)
        .environmentObject(appGlobals)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        .accentColor.mix(with: .black, by: 0.2),
                        .accentColor.mix(with: .black, by: 0.4)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
            }
        )
    }
}

#Preview {
    ContentView()
}

