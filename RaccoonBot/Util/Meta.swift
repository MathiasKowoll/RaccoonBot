//
//  Meta.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 24/02/2026.
//

import Foundation

nonisolated func getGamesMeta(from: URL) throws -> [GamesMeta] {
    /**
     scans a folder and returns an array of steam games meta
     */
    var array: [GamesMeta] = []
    try withSecurityScope(for: from) {
        let f = FileManager.default
        let urls = try f.contentsOfDirectory(at: from, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]).filter { $0.pathExtension == "acf" }
        try urls.forEach { url in
            let file  = try readFile(at: url)
            let parsed = parseVDFToDict(from: file)
            let meta = mapDictToGamesMeta(from: parsed["AppState"] as! [String: Any])
            meta.gameURL = from.appendingPathComponent("common").appendingPathComponent(meta.installdir)
            // Through the cache: a refresh used to work this out again for
            // every installed game, and that is what froze the window.
            meta.isNative = meta.isDownloaded() ? NativeKind.isNative(folder: meta.gameURL!) : false
            meta.appNames = []
            meta.libraryFolder = from
            array.append(meta)
        }
    }
    return array
}

func getMeta(_ gameMetaArray: [GamesMeta], byID: String) -> GamesMeta? {
    /**
     find the corresponding meta by id where the id is the unique id and not the steam app id
     */
    if let exact = gameMetaArray.first(where: { $0.id == byID }) { return exact }
    // An Epic card carries the launcher's triple as its id, because that is
    // what starts the title; its meta carries the same triple in `appid`, and
    // `id` is the library folder plus that -- so the two never match and every
    // Epic title was invisible here. Which made the video-fix badge, the launch
    // gate and the fix panel dead for all of them, and put "Could not work out
    // where this game is installed" on every Epic options sheet.
    //
    // Narrowed to Epic ids on purpose: a Steam appid is digits and could
    // collide with something; a triple begins with "epic:" and cannot.
    guard byID.hasPrefix("epic:") else { return nil }
    return gameMetaArray.first(where: { $0.appid == byID })
}

func mapDictToGamesMeta(from: [String:Any]) -> GamesMeta {
    /**
     Maps the fields the application actually uses. `name` was in this
     dictionary all along and was being dropped -- which is why naming an
     installed game used to require a network call.
     */
    let meta = GamesMeta(appid: from["appid"] as? String ?? "unknown", installdir: from["installdir"] as? String ?? "unknown", bytesDownloaded: from["BytesDownloaded"] as? String ?? "0", BytesTodownload: from["BytesToDownload"] as? String ?? "0")
    meta.name = from["name"] as? String
    // Also in the dictionary all along, also being dropped. SizeOnDisk is the
    // only record of how big an installed game is: the store knows what it
    // ships, not what is on this disk after updates.
    meta.SizeOnDisk = from["SizeOnDisk"] as? String
    return meta
}
