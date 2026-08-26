//
//  Flag.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 01/03/2026.
//

import SwiftUI

extension String {
    var flagEmoji: String {
        let base: UInt32 = 127397
        var s = ""
        for v in self.uppercased().unicodeScalars {
            guard let scalar = UnicodeScalar(base + v.value) else { continue }
            s.unicodeScalars.append(scalar)
        }
        return s
    }
}

struct Flag: View {
    let countryCode: String

    var body: some View {
        Text(countryCode.flagEmoji)
            .accessibilityLabel(Text(Locale.current.localizedString(forRegionCode: countryCode) ?? countryCode))
    }
}

#Preview {
    Flag(countryCode: "GB")
}

