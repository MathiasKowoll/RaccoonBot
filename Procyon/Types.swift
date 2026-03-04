//
//  Types.swift
//  Procyon
//
//  Created by Italo Mandara on 19/02/2026.
//

internal import Foundation
import Combine

enum CXGraphicsBackend: String {
    case dxmt = "dxmt"
    case d3dmetal = "d3dmetal"
    case wine = "wine"
    case dxvk = "dxvk"
}

enum OnOff: String {
    case off = "0"
    case on = "1"
}

typealias CXDrives = [String: URL]

struct GameOptionsData: Codable {
    var cxGraphicsBackend: String
    var wineMSync: Bool
    var mtlHudEnabled: Bool
    var gameArguments: String
    var dxmtPreferredMaxFrameRate: Double
    var dxmtMetalFXSpatial: Bool
    var dxmtMetalSpatialUpscaleFactor: Double
    var advertiseAVX: Bool
    var envVariables: String
    var sdlEnabled: Bool
    var hidrawDisabled: Bool
    
    init(data: GameOptions) {
        self.cxGraphicsBackend = data.cxGraphicsBackend
        self.wineMSync = data.wineMSync
        self.mtlHudEnabled = data.mtlHudEnabled
        self.gameArguments = data.gameArguments
        self.dxmtPreferredMaxFrameRate = data.dxmtPreferredMaxFrameRate
        self.dxmtMetalFXSpatial = data.dxmtMetalFXSpatial
        self.dxmtMetalSpatialUpscaleFactor = data.dxmtMetalSpatialUpscaleFactor
        self.advertiseAVX = data.advertiseAVX
        self.envVariables = data.envVariables
        self.sdlEnabled = data.sdlEnabled
        self.hidrawDisabled = data.hidrawDisabled
    }
}

class GameOptions: ObservableObject {
    @Published var cxGraphicsBackend: String
    @Published var wineMSync: Bool
    @Published var mtlHudEnabled: Bool
    @Published var dxvk: String?
    @Published var wineEsync: String?
    @Published var d3dMEnableMetalFX: String?
    @Published var d3dSupportDXR: String?
    @Published var gameArguments: String
    @Published var dxmtPreferredMaxFrameRate: Double
    @Published var dxmtMetalFXSpatial: Bool
    @Published var dxmtMetalSpatialUpscaleFactor: Double
    @Published var advertiseAVX: Bool
    @Published var envVariables: String
    @Published var sdlEnabled: Bool
    @Published var hidrawDisabled: Bool
    
    init(cxGraphicsBackend: String = "d3dmetal", wineMSync: Bool = true, mtlHudEnabled: Bool = false, dxvk: String? = nil, wineEsync: String? = nil, d3dMEnableMetalFX: String? = nil, d3dSupportDXR: String? = nil, gameArguments: String = "", dxmtPreferredMaxFrameRate: Double = 0, dxmtMetalFXSpatial: Bool = false, dxmtMetalSpatialUpscaleFactor: Double = 1.0, advertiseAVX: Bool = true, envVariables: String = "", sdlEnabled: Bool = true, hidrawDisabled: Bool = false) {
        self.cxGraphicsBackend = cxGraphicsBackend
        self.wineMSync = wineMSync
        self.mtlHudEnabled = mtlHudEnabled
        self.dxvk = dxvk
        self.wineEsync = wineEsync
        self.d3dMEnableMetalFX = d3dMEnableMetalFX
        self.d3dSupportDXR = d3dSupportDXR
        self.gameArguments = gameArguments
        self.dxmtMetalFXSpatial = dxmtMetalFXSpatial
        self.dxmtMetalSpatialUpscaleFactor = dxmtMetalSpatialUpscaleFactor
        self.dxmtPreferredMaxFrameRate = dxmtPreferredMaxFrameRate
        self.advertiseAVX = advertiseAVX
        self.envVariables = envVariables
        self.sdlEnabled = sdlEnabled
        self.hidrawDisabled = hidrawDisabled
    }
    func set(data: GameOptionsData) {
        self.cxGraphicsBackend = data.cxGraphicsBackend
        self.wineMSync = data.wineMSync
        self.mtlHudEnabled = data.mtlHudEnabled
        self.gameArguments = data.gameArguments
        self.dxmtMetalFXSpatial = data.dxmtMetalFXSpatial
        self.dxmtMetalSpatialUpscaleFactor = data.dxmtMetalSpatialUpscaleFactor
        self.dxmtPreferredMaxFrameRate = data.dxmtPreferredMaxFrameRate
        self.advertiseAVX = data.advertiseAVX
        self.envVariables = data.envVariables
        self.sdlEnabled = data.sdlEnabled
        self.hidrawDisabled = data.hidrawDisabled
    }
}

class GamesMeta: SteamACFMeta {
    var gameURL: URL?
    var libraryFolder: URL
    var isNative: Bool
    var id: String { libraryFolder.relativeString + appid }
    func isDownloaded() -> Bool {
        return (self.BytesToDownload == "0" || self.BytesToDownload == self.BytesDownloaded)
    }
    
    init(appid: String, installdir: String, gameURL: URL? = nil, isNative: Bool = false, libraryFolder: URL = URL(string: "/")!, bytesDownloaded: String, BytesTodownload: String) {
        self.gameURL = gameURL
        self.isNative = isNative
        self.libraryFolder = libraryFolder
        super.init()
        self.appid = appid
        self.installdir = installdir
        self.BytesDownloaded = bytesDownloaded
        self.BytesToDownload = BytesTodownload
    }
}

struct Game: Identifiable {
    var id: String
    var isNative: Bool
    var downloadProgress: Double
    var isInstalled: Bool
    
    // taken from SteamGame
    let type: String
    let name: String
    let steamAppID: Int
    let requiredAge: String
    let isFree: Bool
    let controllerSupport: String?
    let dlc: [Int]?

    let detailedDescription: String
    let aboutTheGame: String
    let shortDescription: String
    let supportedLanguages: String?

    let headerImage: String
    let capsuleImage: String
    let capsuleImageV5: String?
    let website: String?

    let pcRequirements: Requirements?
    let macRequirements: Requirements?
    let linuxRequirements: Requirements?

    let legalNotice: String?
    let developers: [String]
    let publishers: [String]

    let priceOverview: PriceOverview?
    let packages: [Int]?
    let packageGroups: [PackageGroup]?

    let platforms: Platforms
    let metacritic: Metacritic?

    let categories: [Category]
    let genres: [Genre]?

    let screenshots: [Screenshot]?
    let movies: [Movie]?

    let recommendations: Recommendations?
    let achievements: Achievements?
    let releaseDate: ReleaseDate
    let supportInfo: SupportInfo?

    let background: String?
    let backgroundRaw: String?

    let contentDescriptors: ContentDescriptors?
    let ratings: Ratings?
    
    init(from: SteamGame, id: String, isNative: Bool, downloadProgress: Double, isInstalled: Bool) {
        self.id = id
        self.isNative = isNative
        self.downloadProgress = downloadProgress
        self.isInstalled = isInstalled
        
        // SteamGame property
        self.type = from.type
        self.name = from.name
        self.steamAppID = from.steamAppID
        self.requiredAge = from.requiredAge
        self.isFree = from.isFree
        self.controllerSupport = from.controllerSupport
        self.dlc = from.dlc
        
        self.detailedDescription = from.detailedDescription
        self.aboutTheGame = from.aboutTheGame
        self.shortDescription = from.shortDescription
        self.supportedLanguages = from.supportedLanguages
        
        self.headerImage = from.headerImage
        self.capsuleImage = from.capsuleImage
        self.capsuleImageV5 = from.capsuleImageV5
        self.website = from.website
        
        self.pcRequirements = from.pcRequirements
        self.macRequirements = from.macRequirements
        self.linuxRequirements = from.linuxRequirements
        
        self.legalNotice = from.legalNotice
        self.developers = from.developers ?? []
        self.publishers = from.publishers ?? []
        
        self.priceOverview = from.priceOverview
        self.packages = from.packages
        self.packageGroups = from.packageGroups
        
        self.platforms = from.platforms
        self.metacritic = from.metacritic
        
        self.categories = from.categories ?? []
        self.genres = from.genres
        
        self.screenshots = from.screenshots
        self.movies = from.movies
        
        self.recommendations = from.recommendations
        self.achievements = from.achievements
        self.releaseDate = from.releaseDate
        self.supportInfo = from.supportInfo
        
        self.background = from.background
        self.backgroundRaw = from.backgroundRaw
        
        self.contentDescriptors = from.contentDescriptors
        self.ratings = from.ratings
    }
}

extension Game {
    static let steamMock = SteamGame(
        type: "game",
        name: "Mock Game",
        steamAppID: 720,
        requiredAge: "18",
        isFree: false,
        controllerSupport: "full",
        dlc: [1111, 2222],
        detailedDescription: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua .\nUt enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. \nExcepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
        aboutTheGame: "About the mock game: fast-paced, fun, and engaging.",
        shortDescription: "A short description of the mock game.",
        supportedLanguages: "English, French, German",
        headerImage: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/440/header.jpg",
        capsuleImage: "https://placehold.co/600x400/orange/white",
        capsuleImageV5: "https://placehold.co/600x400/orange/white",
        website: "https://example.com",
        pcRequirements: Requirements(minimum: "Windows 10, 8GB RAM", recommended: "Windows 11, 16GB RAM"),
        macRequirements: Requirements(minimum: "macOS 13, 8GB RAM", recommended: "macOS 14, 16GB RAM"),
        linuxRequirements: Requirements(minimum: "Ubuntu 22.04, 8GB RAM", recommended: "Ubuntu 24.04, 16GB RAM"),
        legalNotice: "All trademarks are property of their respective owners.",
        developers: ["Mock Dev Studio"],
        publishers: ["Mock Publisher"],
        priceOverview: PriceOverview(
            currency: "USD",
            initial: 1999,
            final: 999,
            discountPercent: 50,
            initialFormatted: "$19.99",
            finalFormatted: "$9.99"
        ),
        packages: [3333, 4444],
        packageGroups: [
            PackageGroup(
                name: "default",
                title: "Standard Edition",
                description: "Base game package",
                selectionText: "Select a purchase option",
                displayType: 0,
                subs: [
                    PackageSub(
                        packageID: 3333,
                        optionText: "Base Game",
                        isFreeLicense: false,
                        priceInCentsWithDiscount: 999
                    )
                ]
            )
        ],
        platforms: Platforms(windows: true, mac: true, linux: true),
        metacritic: Metacritic(score: 85, url: "https://metacritic.example.com/mockgame"),
        categories: [
            Category(id: 1, description: "Single-player"),
            Category(id: 2, description: "Online Co-op")
        ],
        genres: [
            Genre(id: "1", description: "Action"),
            Genre(id: "2", description: "Adventure")
        ],
        screenshots: [
            Screenshot(id: 1, pathThumbnail: "https://placehold.co/600x400/orange/white", pathFull: "https://placehold.co/600x400/orange/white"),
            Screenshot(id: 2, pathThumbnail: "https://placehold.co/600x400/orange/white", pathFull: "https://placehold.co/600x400/orange/white")
        ],
        movies: [
            Movie(id: 10, name: "Trailer", thumbnail: "https://example.com/trailer_thumb.jpg", dashH264: "https://video.akamai.steamstatic.com/store_trailers/440/129304/a9d97ffaf28cac468369400c12abe442a7b688b2/1749861261/dash_h264.mpd", hlsH264: "https://video.akamai.steamstatic.com/store_trailers/440/129304/a9d97ffaf28cac468369400c12abe4427b688b2/1749861261/hls_264_master.m3u8", highlight: true)
        ],
        recommendations: Recommendations(total: 12345),
        achievements: Achievements(
            total: 100,
            highlighted: [Achievement(name: "First Steps", path: "https://placehold.co/600x400/orange/white")]
        ),
        releaseDate: ReleaseDate(comingSoon: false, date: "Jan 01, 2026"),
        supportInfo: SupportInfo(url: "https://support.example.com", email: "support@example.com"),
        background: "https://placehold.co/600x400/orange/white",
        backgroundRaw: "https://placehold.co/600x400",
        contentDescriptors: ContentDescriptors(ids: [1, 2, 3], notes: "Contains mild violence"),
        ratings: Ratings(
            esrb: RatingBody(rating: "T", requiredAge: "13", descriptors: "Violence"),
            pegi: RatingBody(rating: "16", requiredAge: "16", descriptors: "Violence"),
            usk: RatingBody(rating: "12", requiredAge: "12", descriptors: "Violence")
        )
    )
    static let mock = Game(from: Game.steamMock, id: "example", isNative: true, downloadProgress: 100, isInstalled: true)
}

enum SortingOptions {
    case name
    case releaseDate
    case publisher
    case developer
}

class LibraryPageGlobals: ObservableObject {
    @Published var gamesMeta: [GamesMeta] = []
    @Published var folders: [String] = []
    @Published var showOptions: Bool = false
    @Published var filter: String = ""
    @Published var showDetailView = false
    @Published var selectedGame: Game? = nil
    @Published var isLaunchingGame: Bool = false
    @Published var games: [Game] = []
    @Published var sortBy: SortingOptions = SortingOptions.name
    
    var filteredGames: [Game] {
        self.games.filter { item in
            self.filter.isEmpty ||
            item.name.lowercased().contains(self.filter.lowercased())
        }.sorted { lhs, rhs in
            switch self.sortBy {
            case SortingOptions.name:
                return lhs.name.lowercased() < rhs.name.lowercased()
            case SortingOptions.releaseDate:
                return lhs.releaseDate.date < rhs.releaseDate.date
            case SortingOptions.publisher:
                return lhs.publishers[0].lowercased() < rhs.publishers[0].lowercased()
            case SortingOptions.developer:
                return lhs.developers[0].lowercased() < rhs.developers[0].lowercased()
            }
        }
    }
    
    func setLoader(state: Bool) {
        isLaunchingGame = state
    }
}

final class AppGlobals: ObservableObject {
    @Published var selectedBottle: String = ""
    @Published var userID: String? = nil
    @Published var cxAppPath: String?
    
    init(selectedBottle: String? = "", cxAppPath: String? = nil) {
        self.selectedBottle = readUsrDefOptionString(key: "selectedBottle") ?? ""
        self.cxAppPath = readUsrDefOptionString(key: "cxAppPath")
    }
}

