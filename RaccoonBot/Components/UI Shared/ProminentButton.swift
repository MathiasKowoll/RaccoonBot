//
//  ProminentButton.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 21/03/2026.
//

import SwiftUI

struct ProminentButton : View {
    var action: () -> Void
    var text: String
    var systemImage: String?
    var image: String?
    var isLoading: Bool = false
    
    init(_ text: String, systemImage: String? = nil , image: String? = nil , isLoading: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.systemImage = systemImage
        self.image = image
        self.action = action
        self.isLoading = isLoading
    }
    
    var body: some View {
        Button(action: {
            action()
        }) {
            if systemImage != nil {
                ZStack() {
                    Label(text, systemImage: systemImage!)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } else if image != nil {
                HStack {
                    Image(self.image!).resizable().scaledToFit().frame(height: 20)
                    ZStack {
                        Text(text)
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            } else {
                ZStack() {
                    Text(text)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
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
