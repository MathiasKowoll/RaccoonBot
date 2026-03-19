//
//  OIcon.swift
//  Procyon
//
//  Created by Italo Mandara on 19/03/2026.
//

import SwiftUI

struct OIcon: View {
    var icon: String
    var size: CGFloat = 16
    
    init(_ icon: String) {
        self.icon = icon
    }
    
    var body: some View {
        Image(systemName: icon)            // icon size
            .resizable()
            .frame(width: size, height: size)
            .padding(8)                                // space inside the circle
            .background(Color.black.opacity(0.1))     // semi-transparent black
            .clipShape(Circle())                       // make it circular
            .foregroundStyle(.white.opacity(0.9))                   // icon color
    }
}

#Preview {
    OIcon("trash")
}
