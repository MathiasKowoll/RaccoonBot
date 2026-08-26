//
//  Meta.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 24/02/2026.
//

import Foundation

func getGamesMeta(from: URL) throws -> [GamesMeta] {
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
            meta.isNative = meta.isDownloaded() ? getIsNative(fromURL: meta.gameURL!) : false
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
    return gameMetaArray.first(where: { $0.id == byID })
}

func mapDictToGamesMeta(from: [String:Any]) -> GamesMeta {
    /**
     Incomplete it only maps appid and installdir
     */
    return GamesMeta(appid: from["appid"] as? String ?? "unknown", installdir: from["installdir"] as? String ?? "unknown", bytesDownloaded: from["BytesDownloaded"] as? String ?? "0", BytesTodownload: from["BytesToDownload"] as? String ?? "0")
}
