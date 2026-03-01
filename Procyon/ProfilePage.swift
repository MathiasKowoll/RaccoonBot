//
//  ProfilePage.swift
//  Procyon
//
//  Created by Italo Mandara on 28/02/2026.
//

import SwiftUI
import Kingfisher

struct ProfilePage: View {
    @EnvironmentObject var appGlobals: AppGlobals
    @EnvironmentObject var router: Router
    @State var showOptions: Bool = false
    @State var isLoading: Bool = true
    @State var profileData: UserInfo? = nil
    
    var body: some View {
        VStack() {
            if isLoading {
                ProgressView("Loading profile…")
            } else if let p = profileData {
                let lastLogOff = Date(timeIntervalSince1970: Double(p.lastLogOff)).formatted()
                let timeCreated = Date(timeIntervalSince1970: Double(p.timeCreated)).formatted()
                
                VStack(alignment: .leading, spacing: 8) {
                    VStack {
                        KFImage(URL(string: p.avatarFull))
                            .placeholder {
                                ProgressView()
                            }
                            .resizable()
                            .scaledToFit()
                    }.frame(width: 82).cornerRadius(20)
                    HStack (alignment: .bottom){
                        Text(p.personaName).font(.largeTitle)
                        Flag(countryCode: p.locCountryCode!).font(.largeTitle)
                    }
                    Text("steamID: \(p.steamID)")
                    Text("profileURL: \(p.profileURL)")
                    Text("communityVisibilityState: \(p.communityVisibilityState)")
                    Text("profileState: \(p.profileState)")
//                    Text("avatarHash: \(p.avatarHash)")
                    Text("lastLogOff: \(lastLogOff)")
                    Text("personaState: \(p.personaState)")
                    Text("primaryClanID: \(p.primaryClanID)")
                    Text("timeCreated: \(timeCreated)")
                    Text("personaStateFlags: \(p.personaStateFlags)")
//                    Text("locStateCode: \(p.locStateCode ?? "-")")
                }
                .frame(width: 400, alignment: .leading)
                .padding()
                .background(.black.opacity(0.5))
                .cornerRadius(20)
            } else {
                Text("No profile data")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
                    Button(action: {
                        api.deleteProfileDataCache()
                        showOptions = false
                    }) {
                        Label("Delete profile cache", systemImage: "trash")
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
        }.task {
            await load()
        }
    }
    @MainActor
    private func load() async {
        defer {
            Task {
                isLoading = false
            }
        }
        do {
            if(appGlobals.userID != nil){
                profileData = try await api.fetchProfileDetails(userID: appGlobals.userID!)
            }
        } catch {
            console.error(error.localizedDescription)
        }
    }
}


#Preview {
    ProfilePage()
}
