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

/// The inset between the track and the thing selected inside it.
///
/// The selected rectangle's radius is derived from the track's minus this, so
/// the two curves stay concentric. Left as independent numbers they drift: at
/// one point the selection was a 5pt corner inside a 10pt capsule with almost
/// no margin, which reads as a square trying to escape a round hole.
let switcherInset: CGFloat = 4
let switcherTrackRadius: CGFloat = 10
var switcherSelectionRadius: CGFloat { switcherTrackRadius - switcherInset }

struct TabSwitcher: View {
    @Binding var selection: LibraryTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LibraryTab.allCases) { tab in
                Text(tab.label)
                    .font(.system(size: 11, weight: selection == tab ? .semibold : .regular))
                    .padding(.horizontal, 14)
                    .frame(height: toolbarCapsuleHeight - switcherInset * 2)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: switcherSelectionRadius)
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
        .padding(.horizontal, switcherInset)
        .frame(height: toolbarCapsuleHeight)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: switcherTrackRadius))
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
                    .frame(width: 24, height: toolbarCapsuleHeight - switcherInset * 2)
                    .background {
                        if selection == option {
                            RoundedRectangle(cornerRadius: switcherSelectionRadius)
                                .fill(.white.opacity(0.20))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
                    .help(help(option))
                    .accessibilityAddTraits(selection == option ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, switcherInset)
        .frame(height: toolbarCapsuleHeight)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: switcherTrackRadius))
        .fixedSize()
    }
}
