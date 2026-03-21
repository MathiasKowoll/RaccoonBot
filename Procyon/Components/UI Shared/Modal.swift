//
//  Modal.swift
//  Procyon
//
//  Created by Italo Mandara on 01/02/2026.
//

import SwiftUI

struct Modal<Content: View>: View {
    @Binding var showModal: Bool
    var title: String? = nil
    var collapse: Bool? = false
    let content: Content
    
    init(_ title: String? = nil, showModal: Binding<Bool>, collapse: Bool? = nil, @ViewBuilder content: () -> Content) {
        self._showModal = showModal
        self.title = title
        self.collapse = collapse
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical) {
                content
                    .padding(.top, collapse == true ? 0 : 45)
                    .padding(.horizontal, collapse == true ? 0 : 15)
            }
        }
        .overlay(alignment: .topLeading) {
            if collapse == true || title == nil {
                CloseModalButton(show: $showModal)
                    .padding(15)
            } else {
                HStack(alignment: .top) {
                    CloseModalButton(show: $showModal)
                    Text(title!)
                        .font(Font.title3.bold())
                        .padding(.trailing)
                        .lineLimit(1)
                }
                .frame(alignment: .leading)
                .padding(15)
//                .padding(.trailing, 45)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
        }
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
