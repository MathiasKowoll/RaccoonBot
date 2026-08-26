//
//  FileAccess.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 24/02/2026.
//

import Foundation

func withSecurityScope<T>(for url: URL, _ body: () throws -> T) rethrows -> T? {
    guard url.startAccessingSecurityScopedResource() else { return nil }
    defer { url.stopAccessingSecurityScopedResource() }
    return try body()
}

func readFile(at: URL) throws -> String {
    return try String(contentsOf: at, encoding: String.Encoding.utf8)
}

func folderContainsFile(withExtension ext: String, at url: URL) -> Bool {
    let f = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
    let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

    guard let enumerator = f.enumerator(at: url, includingPropertiesForKeys: keys, options: options) else {
        return false
    }

    for case let fileURL as URL in enumerator {
        if fileURL.pathExtension.caseInsensitiveCompare(ext) == .orderedSame {
            return true
        }
    }
    return false
}
