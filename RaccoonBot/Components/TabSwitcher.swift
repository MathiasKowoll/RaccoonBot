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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
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
        // Four points of track around the selection rather than two: at two,
        // the selected rectangle sat close enough to the capsule's edge to look
        // like it was escaping it.
        .padding(4)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .fixedSize()
    }
}

/// The same switch, for a pair of icons.
///
/// Shares TabSwitcher's geometry deliberately: these two controls now sit in
/// the same toolbar capsule, and AppKit's segmented pill beside a 5pt selection
/// looks like a mistake.
struct IconSwitcher<Value: Hashable & Identifiable>: View {
    @Binding var selection: Value
    let options: [Value]
    let symbol: (Value) -> String
    var help: (Value) -> String = { _ in "" }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Image(systemName: symbol(option))
                    .font(.system(size: 11))
                    .frame(width: 22, height: 18)
                    .background {
                        if selection == option {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(.white.opacity(0.20))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
                    .help(help(option))
                    .accessibilityAddTraits(selection == option ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
    }
}
