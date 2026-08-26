//
//  TabSwitcher.swift
//  RaccoonBot
//
//  The Installed / Not installed switch.
//
//  Not .pickerStyle(.segmented): AppKit's segmented control draws its selection
//  as a heavily rounded pill whose radius is not settable, which at this size
//  reads as a button floating inside another button. This is the same control
//  with a selection that fits what it is selecting.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct TabSwitcher: View {
    @Binding var selection: LibraryTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LibraryTab.allCases) { tab in
                Text(tab.label)
                    .font(.system(size: 11, weight: selection == tab ? .semibold : .regular))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(.white.opacity(0.20))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = tab }
                    .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
    }
}
