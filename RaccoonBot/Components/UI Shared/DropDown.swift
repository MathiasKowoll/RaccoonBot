//
//  DropDown.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 02/07/2026.
//

import SwiftUI

struct DropDown: View {
    var options: DropdownOptions
    var label: String
    @Binding var value: String
    
    var body: some View {
        if OSVersion < 27 {
            Picker(label, selection: $value) {
                ForEach(options, id: \.id) { (id, label) in
                    Text(label).tag(id)
                }
            }
        } else {
            HStack {
                Text("Graphics Backend").lineLimit(1)
                Menu {
                    ForEach(options, id: \.id) { (id, label) in
                        Button {
                            value = id
                        } label: {
                            if value == id {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                } label: {
                    Text(options.first(where: { $0.id == value })?.label ?? "Select")
                }
                .fixedSize()
            }
        }
    }
}

#Preview {
    @Previewable @State var selected = "1"
    DropDown(options: [("1", "Option 1"), ("2", "Option 2")], label: "Dropdown", value: $selected)
}
