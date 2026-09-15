//
//  AccentTag.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 05/02/2026.
//

import SwiftUI

struct AccentTag: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        Text(text)
            .lineLimit(1)
            // Dark ink, not white: white on the mint is 1.35:1 and cannot be
            // read; this ink is 10.1:1.
            .foregroundStyle(.raccoonOnAccent)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 4)
            // RaccoonBot's mint (#7CF2D8) now, the raccoon's own eyes; the
            // name is historical, kept from Procyon.
            .background(Color.procyonAccent)
            .clipShape(Capsule())
    }
}

#Preview {
   VStack {
        AccentTag("I'm a tag")
   }.padding(20)
}
