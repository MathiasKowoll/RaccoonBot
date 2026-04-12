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
    var scrollable: Bool? = true
    let content: Content
    
    init(_ title: String? = nil, showModal: Binding<Bool>, collapse: Bool? = nil, scrollable: Bool = true, @ViewBuilder content: () -> Content) {
        self._showModal = showModal
        self.title = title
        self.collapse = collapse
        self.content = content()
        self.scrollable = scrollable
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            if(scrollable == true) {
                ScrollView(.vertical) {
                    content
                        .padding(.top, collapse == true ? 0 : 45)
                        .padding(.horizontal, collapse == true ? 0 : 15)
                }
            } else {
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
                .background(.ultraThinMaterial)
                .clipShape(.capsule)
            }
        }
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        .procyonAccent.mix(with: .black, by: 0.2),
                        .procyonAccent.mix(with: .black, by: 0.4)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
            }
        )
    }
}
