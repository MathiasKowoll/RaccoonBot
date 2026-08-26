//
//  Locale.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 24/02/2026.
//

import Foundation
import AppKit


func localizedString(forKey: String, value: String? = nil) -> String {
    return "\(forKey) \(value ?? "")"
}

func showFolder(url: URL) {
    let targetURL: URL = url
    NSWorkspace.shared.open(targetURL)
}
