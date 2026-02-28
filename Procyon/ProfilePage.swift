//
//  ProfilePage.swift
//  Procyon
//
//  Created by Italo Mandara on 28/02/2026.
//

import SwiftUI

struct ProfilePage: View {
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var router: Router
    @State var showOptions: Bool = false
    
    var body: some View {
        VStack() {
            Text("Profile Page")
            Text("User ID: \(appGlobals.userID ?? "...")").padding(.vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showOptions) {
            Modal(
                showModal: $showOptions,
            ) {
                VStack {
                    Text("Options").padding(.bottom)
                    Image(.procyon).resizable()
                        .scaledToFit()
                        .frame(height: 50)
                        .padding(.bottom)
                    Button(action: {
                        api.deleteOwnedGamesIDsCache()
                        showOptions = false
                    }) {
                        Label("Delete Owned games cache", systemImage: "trash")
                    }
                    .cornerRadius(20)
                }
                .frame(width: 300, height: 300)
                .padding()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showOptions = true
                } label: {
                    Image(systemName: "gear")
                }
            }
            ToolbarItemGroup(placement: .secondaryAction) {
                HStack{
                    Button("Library") {
                        router.go(to: .libraryPage)
                    }.controlSize(.small)
                    Divider()
                    Button("Profile") {
                        router.go(to: .profilePage)
                    }.controlSize(.small)
                }.padding(.horizontal)
            }
        }
    }
}

#Preview {
    ProfilePage()
}
