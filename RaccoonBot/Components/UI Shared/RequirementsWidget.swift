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
                // Wraps rather than grows. A requirements block is a whole
                // specification list, and a Text with no width limit takes its
                // ideal width -- one very long line -- which pushed the entire
                // detail page wider than its own sheet.
                Text("\(requirements!.minimum ?? "")")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.bottom, 5)
            if(requirements!.recommended != nil){
                Divider()
                HStack (alignment: .top) {
                    Text("Recommended:").frame(width: 100, alignment: .topLeading)
                    Text("\(requirements!.recommended!)")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom)
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
