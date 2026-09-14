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
    /// Off where the label is drawn by the layout around the control -- a grid
    /// whose first column holds every label, so the controls line up. The
    /// label still names the control for accessibility.
    var showsLabel: Bool = true
    
    var body: some View {
        if OSVersion < 27 {
            Picker(label, selection: $value) {
                ForEach(options, id: \.id) { (id, label) in
                    Text(label).tag(id)
                }
            }
            .labelsHidden(!showsLabel)
        } else {
            HStack {
                // The label this was given, not the name of the first control
                // that ever used one. It was written here as a literal, so on
                // macOS 27 and later every dropdown in the application called
                // itself "Graphics Backend" -- the Vulkan library picker did,
                // and so would any picker added beside it.
                if showsLabel {
                    Text(label).lineLimit(1)
                }
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
                .accessibilityLabel(label)
            }
        }
    }
}

#Preview {
    @Previewable @State var selected = "1"
    DropDown(options: [("1", "Option 1"), ("2", "Option 2")], label: "Dropdown", value: $selected)
}

private extension View {
    /// `labelsHidden()` when asked, and nothing otherwise.
    @ViewBuilder func labelsHidden(_ hidden: Bool) -> some View {
        if hidden { self.labelsHidden() } else { self }
    }
}
