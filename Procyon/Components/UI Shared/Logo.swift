//
//  Logo.swift
//  Procyon
//
//  Created by Italo Mandara on 03/03/2026.
//

import SwiftUI

struct Logo: View {
    var size: CGFloat = 50
    
    var body: some View {
        Image(.procyon).resizable()
            .scaledToFit()
            .frame(height: size)
            .padding(.bottom)
    }
}

#Preview {
    Logo()
}
