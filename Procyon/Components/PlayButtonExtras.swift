//
//  PlayButtonExtras.swift
//  Procyon
//
//  Created by Italo Mandara on 06/03/2026.
//

import SwiftUI

struct PlayButtonExtras: View {
    var playAction: () -> Void
    var optionsAction: () -> Void
    var folderAction: () -> Void
    var isPlaying: Bool
    
    var body: some View {
        HStack{
            Button { playAction() } label: {
                Text(isPlaying ? "Stop" : "Play")
                    .padding(.vertical, 5)
                    
            }
            Divider()
            Button { optionsAction() } label: {
                Image(systemName: "gear")
                    .padding(.vertical, 5)
                    
            }
            Divider()
            Button {
                folderAction()
            } label: {
                Image(systemName: "folder.fill")
                    .padding(.vertical, 5)
                                               
            }
        }
        .padding(.horizontal, 20)
        .buttonStyle(.plain)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(.black)
        .background(.procyonSecondary)
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .clipShape(.capsule)
        .frame(height: 30)
        .padding(.leading, 24)
    }
}

#Preview {
    PlayButtonExtras(playAction: {
    
    }, optionsAction: {
        
    }, folderAction: {
        
    }, isPlaying: false)
}
