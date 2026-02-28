//
//  API.swift
//  Procyon
//
//  Created by Italo Mandara on 29/01/2026.
//

internal import Foundation
import Alamofire

let apiKey = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as! String
let pr = Bundle.main.object(forInfoDictionaryKey: "API_PROTOCOL") as! String
let host = Bundle.main.object(forInfoDictionaryKey: "API_HOST") as! String
let path = Bundle.main.object(forInfoDictionaryKey: "API_PATH") as! String
let pathm = Bundle.main.object(forInfoDictionaryKey: "API_PATH_M") as! String

let baseAPIURL = "\(pr)://\(host)\(path)"
let baseAPIMURL = "\(pr)://\(host)\(pathm)"

struct SteamGameResponse: Codable, Sendable {
    let data: [SteamGame]
}

struct SteamOwnedGamesResponse: Codable, Sendable {
    let response: SteamOwnedGames
}

struct SteamOwnedGamesResponseData: Codable, Sendable {
    let data: SteamOwnedGamesResponse
}

struct SteamGameResponseArray: Codable, Sendable {
    let data: [SteamGame]
}

enum APIError: Error {
    case badURL
    case invalidResponse
}

final class SteamAPI {
    var progress: Double = 0
    private var cacheBlacklist: [String] = blacklist
    private var cache: [String: SteamGame] = [:]
    private var cacheOwnedGamesIDs: [String] = []
    private var cacheIDS: [String] {
        if cache.count < 1 {
            return []
        }
        return cache.map { String($0.key) }
    }
    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ProcyonSteamCache.plist")
    }
    private var cacheOwnedGamesIDsURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ProcyonSteamOwnedGamesIDsCache.plist")
    }

    private func loadCache() {
        console.log("Loading caches...")
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoded = try JSONDecoder().decode([String: SteamGame].self, from: data)
            self.cache = decoded
            console.warn("Cache loaded")
        } catch {
            console.error("Cache is empty, coulnd't read the file")
        }
        do {
            let data = try Data(contentsOf: cacheOwnedGamesIDsURL)
            let decoded = try JSONDecoder().decode([String].self, from: data)
            self.cacheOwnedGamesIDs = decoded
            console.warn("ID Cache loaded")
        } catch {
            console.error("ID Cache is empty, coulnd't read the file")
        }
    }
    
    init() {
        self.loadCache()
        if(self.cache.isEmpty){
            console.warn("Cache is empty")
        }
        if(self.cacheOwnedGamesIDs.isEmpty){
            console.warn("ID Cache is empty")
        }
    }
    
    private func saveCache() {
        do {
            let encoded = try JSONEncoder().encode(self.cache)
            try encoded.write(to: self.cacheURL, options: [.atomic])
            console.warn("Cache saved")
        } catch {
            console.error(error.localizedDescription)
        }
    }
    private func saveOwnedGamesIDsCache() {
        do {
            let encoded = try JSONEncoder().encode(self.cacheOwnedGamesIDs)
            try encoded.write(to: self.cacheOwnedGamesIDsURL, options: [.atomic])
            console.warn("IDs Cache saved")
        } catch {
            console.error(error.localizedDescription)
        }
    }
    func deleteCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        self.cache.removeAll()
        console.warn("Cache deleted")
    }
    func deleteOwnedGamesIDsCache() {
        try? FileManager.default.removeItem(at: cacheOwnedGamesIDsURL)
        self.cache.removeAll()
        console.warn("IDs Cache deleted")
    }
    func fetchGameInfo(appID: String) async throws -> SteamGame? {
        if self.cacheBlacklist.contains(appID) {
            return nil
        }
        if let cached = self.cache[appID] {
            console.cache(appID)
            return cached
        }
        
        let urlString = "\(baseAPIURL)?appid=\(appID)"
        let headers: HTTPHeaders = ["x-api-key": apiKey]

        do {
            let data = try await AF.request(urlString, method: .get, headers: headers)
                .validate(statusCode: 200..<300)
                .serializingData()
                .value
            
            let root = try JSONDecoder().decode(SteamGameResponse.self, from: data)
            
            cache[appID] = root.data[0]
            saveCache()
            return root.data[0]
        }
    }
    func fetchGamesInfo(meta: [GamesMeta], setProgress: @escaping (Double) -> Void = { _ in }) async throws -> [Game] {
        var items: [Game] = []
        let total = meta.count
        // Reset progress at start
        self.progress = 0
        setProgress(self.progress)
        
        for (index, meta) in meta.enumerated() {
            let bDownloaded = Double(meta.BytesDownloaded ?? "0")!
            let bToDownload = Double(meta.BytesToDownload ?? "0")!
            let downloadProgress: Double = meta.isDownloaded() ? 100 : (bDownloaded / bToDownload) * 100
            do {
                if let gameInfo = try await self.fetchGameInfo(appID: meta.appid) {
                    items.append(Game(from: gameInfo, id: meta.id, isNative: meta.isNative, downloadProgress: Double(downloadProgress), isInstalled: meta.installdir.isEmpty == false))
                }
            } catch {
                console.error(error.localizedDescription)
            }
            // Update progress as percentage of total processed
            if total > 0 {
                let processed = index + 1
                let percent = (Double(processed) / Double(total)) * 100.0
                self.progress = percent
                setProgress(self.progress)
            }
        }
        // Ensure progress is 100% at completion when there were items to process
        if total > 0 {
            self.progress = 100
            setProgress(self.progress)
        }
        console.cacheRelease("The following game's data was cached:")
        return items
    }
    func fetchOwnedGamesIDs(userID: String) async throws -> [String] {
        if(self.cacheOwnedGamesIDs.count > 0) {
            console.log("Using cached user data")
            return self.cacheOwnedGamesIDs
        }
        let urlString = "\(baseAPIURL)/ownedGames/?userid=\(userID)"
        let headers: HTTPHeaders = ["x-api-key": apiKey]

        do {
            let data = try await AF.request(urlString, method: .get, headers: headers)
                .validate(statusCode: 200..<300)
                .serializingData()
                .value
            
            let root = try JSONDecoder().decode(SteamOwnedGamesResponseData.self, from: data)
            let ids = root.data.response.games.map { String($0.appID) }
            self.cacheOwnedGamesIDs = ids
            self.saveOwnedGamesIDsCache()
            return ids
        }
    }
}

