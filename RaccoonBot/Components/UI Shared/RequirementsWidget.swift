//
//  RequirementsWidget.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 28/02/2026.
//

import SwiftUI

struct RequirementsWidget: View {
    @State var requirements: Requirements?
    
    var body: some View {
        VStack (alignment: .leading) {
            HStack (alignment: .top) {
                Text("Minimum:").frame(width: 100, alignment: .topLeading)
                Text("\(requirements!.minimum ?? "")")
            }.padding(.bottom, 5)
            if(requirements!.recommended != nil){
                Divider()
                HStack (alignment: .top) {
                    Text("Recommended:").frame(width: 100, alignment: .topLeading)
                    Text("\(requirements!.recommended!)").padding(.bottom)
                }.padding(.top, 5)
            }
        }
        .padding()
        .background(.white.opacity(0.05))
        .cornerRadius(10)
    }
}

#Preview {
    RequirementsWidget()
}
