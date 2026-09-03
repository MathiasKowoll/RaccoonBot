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

/// Which of these extensions a game folder holds, looked for the way they are
/// actually laid out: near the top, and in breadth rather than in depth.
///
/// This used to be one `FileManager.enumerator` walk per extension, unbounded.
/// That enumerator is depth-first: it takes the top-level entries in directory
/// order and descends into the first folder it meets before looking at the
/// rest. A Windows game whose first subfolder is the big one -- which is most
/// of them -- had tens of thousands of files listed before the `.exe` sitting
/// beside it was ever reached, and a folder with no match at all was walked
/// whole, twice.
///
/// A refresh asks this of every installed game, on the main thread. The
/// window froze for forty-four minutes doing it, and the sample taken while
/// it was frozen showed exactly this call, inside `getattrlistbulk`, four
/// Steam games deep.
///
/// So: breadth-first, one `contentsOfDirectory` per folder, every entry of a
/// level seen before any of the next. The executable that sits at the top of
/// a game folder is found in the first call. Bounded twice over -- by depth,
/// and by how many folders it will open at all -- because the answer is not
/// down there and the time is.
nonisolated func folderContains(extensions wanted: Set<String>, at url: URL,
                                maxDepth: Int = 2, maxFolders: Int = 64,
                                fileManager f: FileManager = .default) -> Set<String> {
    let lowered = Set(wanted.map { $0.lowercased() })
    var found: Set<String> = []
    var level = [url]
    var opened = 0
    for _ in 0...max(0, maxDepth) {
        var next: [URL] = []
        for folder in level {
            guard opened < maxFolders else { return found }
            opened += 1
            guard let entries = try? f.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]) else { continue }
            for entry in entries {
                let ext = entry.pathExtension.lowercased()
                if lowered.contains(ext) {
                    found.insert(ext)
                    // Every question answered; nothing below can change it.
                    if found.count == lowered.count { return found }
                    // A bundle is a package: its insides are not this game's
                    // Windows executables, so they are never descended into.
                    continue
                }
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    next.append(entry)
                }
            }
        }
        if next.isEmpty { break }
        level = next
    }
    return found
}

func folderContainsFile(withExtension ext: String, at url: URL) -> Bool {
    !folderContains(extensions: [ext], at: url).isEmpty
}
