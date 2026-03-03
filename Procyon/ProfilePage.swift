//
//  ProfilePage.swift
//  Procyon
//
//  Created by Italo Mandara on 28/02/2026.
//

import SwiftUI

struct ProfilePage: View {
    @EnvironmentObject var router: Router
    @State var showOptions: Bool = false
    
    var body: some View {
        VStack{}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .sheet(isPresented: $showOptions) {
            Modal(
                showModal: $showOptions,
            ) {
                VStack {
                    Text("Options").padding(.bottom)                    
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
                }.padding(.horizontal)
            }
        }
    }
}


#Preview {
    ProfilePage()
}
