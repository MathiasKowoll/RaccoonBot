//
//  ProminentButton.swift
//  Procyon
//
//  Created by Italo Mandara on 21/03/2026.
//

import SwiftUI

struct ProminentButton : View {
    var action: () -> Void
    var text: String
    var systemImage: String?
    var image: String?
    
    init(_ text: String, systemImage: String? = nil , image: String? = nil , action: @escaping () -> Void) {
        self.text = text
        self.systemImage = systemImage
        self.image = image
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            action()
        }) {
            if systemImage != nil {
                Label(text, systemImage: systemImage!)
            } else if image != nil{
                HStack {
                    Image(self.image!).resizable().scaledToFit().frame(height: 20)
                    Text(text)
                }
            } else {
                Text(text)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

#Preview {
    ProminentButton("Hello") {
        print("Hello!")
    }
}
