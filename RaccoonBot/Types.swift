//
//  Types.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 19/02/2026.
//

import Foundation
import Combine

typealias DropdownOptions = [(id: String, label: String)]

let cxGraphicsBackend: DropdownOptions = [
    (id: "dxmt", label: "DXMT"),
    (id: "d3dmetal3", label: "D3Dmetal3"),
    (id: "d3dmetal4", label: "D3Dmetal4"),
    (id: "wined3d", label: "Wine"),
    (id: "dxvk", label: "DXVK"),
    (id: "auto", label: "Auto")
]

let cxVulkanBackend: DropdownOptions = [
    (id: "", label: "Standard"),
    (id: "latest", label: "Latest"),
    (id: "experimental", label: "Experimental"),
    (id: "dbh", label: "Detroit Become Human"),
//    (id: "kosmickrisp", label: "KosmicKrisp")
]

enum OnOff: String {
    case off = "0"
    case on = "1"
}

typealias CXDrives = [String: URL]

/// How much of the Metal HUD to show.
///
/// The HUD takes a comma-separated list of the rows to draw, in
/// MTL_HUD_ELEMENTS. These names are Apple's, from "Customizing the Metal
/// Performance HUD" -- not from any tool that wraps it. That distinction cost
/// something: a third-party menu bar app lists `gamemode`, `refreshrate` and
/// `client`, which Apple documents nowhere, and omits two it does. A name the
/// HUD does not know could take the whole list down with it, so the ones
/// shipped here are only the documented twenty.
enum MetalHudDetail: String, CaseIterable {
    case fpsOnly = "fps"
    case normal = "normal"
    case extended = "extended"

    /// Every metric Apple documents.
    static let allElements = [
        "device", "rosetta", "layersize", "layerscale", "memory", "fps",
        "frameinterval", "gputime", "thermal", "frameintervalgraph",
        "presentdelay", "frameintervalhistogram", "metalcpu", "gputimeline",
        "shaders", "framenumber", "disk", "fpsgraph",
        "toplabeledcommandbuffers", "toplabeledencoders",
    ]

    /// The rows this level draws.
    var elements: [String] {
        switch self {
        case .fpsOnly:
            return ["fps"]
        case .normal:
            return ["device", "rosetta", "layersize", "memory", "fps",
                    "gputime", "frameinterval", "frameintervalgraph", "thermal"]
        case .extended:
            return Self.allElements
        }
    }

    var label: String {
        switch self {
        case .fpsOnly: return "Frame rate only"
        case .normal: return "Normal"
        case .extended: return "Extended"
        }
    }

    var explanation: String {
        switch self {
        case .fpsOnly: return "One line, and nothing in the way of the game."
        case .normal: return "Memory, GPU time, frame intervals and thermal state."
        case .extended: return "Every metric Apple documents, plus the toolkit's own counters."
        }
    }
}

/// Where the Metal HUD sits on screen.
///
/// Apple's names, from the same page as the metrics. Worth spelling out because
/// the menu bar app that wraps the HUD sets this to numbers -- "10", "12", "20"
/// -- and Apple documents words. Whichever that app is talking to, it is not
/// what is written here.
enum MetalHudAlignment: String, CaseIterable {
    case topLeft = "topleft"
    case topCenter = "topcenter"
    case topRight = "topright"
    case centerLeft = "centerleft"
    case centered = "centered"
    case centerRight = "centerright"
    case bottomLeft = "bottomleft"
    case bottomCenter = "bottomcenter"
    case bottomRight = "bottomright"

    /// What the HUD does when nobody has said.
    static let byDefault = MetalHudAlignment.topRight

    var label: String {
        switch self {
        case .topLeft: return "Top left"
        case .topCenter: return "Top centre"
        case .topRight: return "Top right"
        case .centerLeft: return "Left"
        case .centered: return "Centre"
        case .centerRight: return "Right"
        case .bottomLeft: return "Bottom left"
        case .bottomCenter: return "Bottom centre"
        case .bottomRight: return "Bottom right"
        }
    }
}

struct GameOptionsData: Codable { // this is used for reading saved properties
    var cxGraphicsBackend: String?
    var wineMSync: Bool?
    var mtlHudEnabled: Bool?
    /// How much the Metal HUD should show: "fps", "normal" or "extended".
    var mtlHudDetail: String?
    /// How solid the Metal HUD is drawn, from 0 to 1.
    var mtlHudOpacity: Double?
    /// Where the Metal HUD sits on screen.
    var mtlHudAlignment: String?
    var d3dMtl4Enabled: Bool?
    var x87PatchEnabled: Bool?
    /// Run this title in the ARM bottle instead of the default one.
    var useArmBottle: Bool?
    var dx9PatchEnabled: Bool?
    var gameArguments: String?
    var dxmtPreferredMaxFrameRate: Double?
    var dxmtMetalFXSpatial: Bool?
    var dxmtMetalSpatialUpscaleFactor: Double?
    var advertiseAVX: Bool?
    var envVariables: String?
    var enableSDL: Bool?
    var disableHidraw: Bool?
    var ue4Hack: Bool?
    var mvkArgBuff: Bool?
    var vulkanLib: String?
    var dxvk: String?
    var wineEsync: String?
    var d3dMEnableMetalFX: String?
    var d3dSupportDXR: String?
    var d3dMaxFPS: Double?
    
    init(data: GameOptions) {
        self.cxGraphicsBackend = data.cxGraphicsBackend
        self.wineMSync = data.wineMSync
        self.mtlHudEnabled = data.mtlHudEnabled
        // Declared, read by set(data:) and by importAutoConfig, and until
        // now never written back here -- so the detail level, the opacity
        // and the alignment were dropped by every save and came back as
        // defaults on every load. A round trip that silently loses a field
        // is worse than one that refuses it.
        self.mtlHudDetail = data.mtlHudDetail
        self.mtlHudOpacity = data.mtlHudOpacity
        self.mtlHudAlignment = data.mtlHudAlignment
        self.x87PatchEnabled = data.x87PatchEnabled
        self.useArmBottle = data.useArmBottle
        self.dx9PatchEnabled = data.dx9PatchEnabled
        self.gameArguments = data.gameArguments
        self.dxmtPreferredMaxFrameRate = data.dxmtPreferredMaxFrameRate
        self.dxmtMetalFXSpatial = data.dxmtMetalFXSpatial
        self.dxmtMetalSpatialUpscaleFactor = data.dxmtMetalSpatialUpscaleFactor
        self.advertiseAVX = data.advertiseAVX
        self.envVariables = data.envVariables
        self.enableSDL = data.enableSDL
        self.disableHidraw = data.disableHidraw
        self.ue4Hack = data.ue4Hack
        self.mvkArgBuff = data.mvkArgBuff
        self.vulkanLib = data.vulkanLib
        self.dxvk = data.dxvk
        self.wineEsync = data.wineEsync
        self.d3dMEnableMetalFX = data.d3dMEnableMetalFX
        self.d3dSupportDXR = data.d3dSupportDXR
        self.d3dMtl4Enabled = data.d3dMtl4Enabled
        self.d3dMaxFPS = data.d3dMaxFPS
    }
}

class GameOptions: ObservableObject { // this is used as form state
    @Published var cxGraphicsBackend: String
    @Published var wineMSync: Bool
    @Published var mtlHudEnabled: Bool
    /// How much the Metal HUD should show.
    ///
    /// Not in the initialiser on purpose: every existing call site keeps
    /// working, and a title that has never been told otherwise shows the
    /// least -- which is what somebody who turns a HUD on while playing
    /// usually wants.
    @Published var mtlHudDetail: String = MetalHudDetail.fpsOnly.rawValue
    /// How solid the HUD is drawn. Fully opaque unless somebody says otherwise.
    @Published var mtlHudOpacity: Double = 1.0
    /// Where the HUD sits. Top right unless somebody moves it, which is where
    /// the HUD puts itself anyway.
    @Published var mtlHudAlignment: String = MetalHudAlignment.byDefault.rawValue
    @Published var x87PatchEnabled: Bool
    /// Defaults to false and is not in the initialiser on purpose: every
    /// existing call site keeps working, and a title only moves bottles when
    /// somebody asks it to.
    @Published var useArmBottle: Bool = false
    @Published var dx9PatchEnabled: Bool
    @Published var gameArguments: String
    @Published var dxmtPreferredMaxFrameRate: Double
    @Published var dxmtMetalFXSpatial: Bool
    @Published var dxmtMetalSpatialUpscaleFactor: Double
    @Published var advertiseAVX: Bool
    @Published var envVariables: String
    @Published var enableSDL: Bool
    @Published var disableHidraw: Bool
    @Published var ue4Hack: Bool
    @Published var mvkArgBuff: Bool
    @Published var vulkanLib: String
    @Published var dxvk: String?
    @Published var wineEsync: String?
    @Published var d3dMEnableMetalFX: String?
    @Published var d3dSupportDXR: String?
    @Published var d3dMtl4Enabled: Bool
    @Published var d3dMaxFPS: Double
    
    init(cxGraphicsBackend: String = "d3dmetal4", wineMSync: Bool = true, mtlHudEnabled: Bool = false, d3dMtl4Enabled: Bool = false, x87PatchEnabled: Bool = false, dx9PatchEnabled: Bool = false, gameArguments: String = "", dxmtPreferredMaxFrameRate: Double = 0, dxmtMetalFXSpatial: Bool = false, dxmtMetalSpatialUpscaleFactor: Double = 1.0, advertiseAVX: Bool = true, envVariables: String = "", sdlEnabled: Bool = true, hidrawDisabled: Bool = false, ue4Hack: Bool = true, mvkArgBuff: Bool = true, vulkanLib: String = "latest", dxvk: String? = nil, wineEsync: String? = nil, d3dMEnableMetalFX: String? = nil, d3dMaxFPS: Double = 0, d3dSupportDXR: String? = nil) {
        self.cxGraphicsBackend = cxGraphicsBackend
        self.wineMSync = wineMSync
        self.mtlHudEnabled = mtlHudEnabled
        self.x87PatchEnabled = x87PatchEnabled
        self.dx9PatchEnabled = dx9PatchEnabled
        self.gameArguments = gameArguments
        self.dxmtMetalFXSpatial = dxmtMetalFXSpatial
        self.dxmtMetalSpatialUpscaleFactor = dxmtMetalSpatialUpscaleFactor
        self.dxmtPreferredMaxFrameRate = dxmtPreferredMaxFrameRate
        self.advertiseAVX = advertiseAVX
        self.envVariables = envVariables
        self.enableSDL = sdlEnabled
        self.disableHidraw = hidrawDisabled
        self.ue4Hack = ue4Hack
        self.mvkArgBuff = mvkArgBuff
        self.vulkanLib = vulkanLib
        self.dxvk = dxvk
        self.wineEsync = wineEsync
        self.d3dMEnableMetalFX = d3dMEnableMetalFX
        self.d3dSupportDXR = d3dSupportDXR
        self.d3dMtl4Enabled = d3dMtl4Enabled
        self.d3dMaxFPS = d3dMaxFPS
    }
    
    func set(data: GameOptionsData) {
        self.cxGraphicsBackend = data.cxGraphicsBackend ?? "auto"
        self.wineMSync = data.wineMSync ?? true
        self.mtlHudEnabled = data.mtlHudEnabled ?? false
        self.mtlHudDetail = data.mtlHudDetail ?? MetalHudDetail.fpsOnly.rawValue
        self.mtlHudOpacity = data.mtlHudOpacity ?? 1.0
        self.mtlHudAlignment = data.mtlHudAlignment ?? MetalHudAlignment.byDefault.rawValue
        self.x87PatchEnabled = data.x87PatchEnabled ?? false
        self.useArmBottle = data.useArmBottle ?? false
        self.dx9PatchEnabled = data.dx9PatchEnabled ?? false
        self.gameArguments = data.gameArguments ?? ""
        self.dxmtMetalFXSpatial = data.dxmtMetalFXSpatial ?? false
        self.dxmtMetalSpatialUpscaleFactor = data.dxmtMetalSpatialUpscaleFactor ?? 1.0
        self.dxmtPreferredMaxFrameRate = data.dxmtPreferredMaxFrameRate ?? 0
        self.advertiseAVX = data.advertiseAVX ?? true
        self.envVariables = data.envVariables ?? ""
        self.enableSDL = data.enableSDL ?? true
        self.disableHidraw = data.disableHidraw ?? false
        self.ue4Hack = data.ue4Hack ?? true
        self.mvkArgBuff = data.mvkArgBuff ?? true
        self.vulkanLib = data.vulkanLib ?? "standard"
        self.dxvk = data.dxvk ?? ""
        self.wineEsync = data.wineEsync ?? ""
        self.d3dMEnableMetalFX = data.d3dMEnableMetalFX ?? ""
        self.d3dSupportDXR = data.d3dSupportDXR ?? ""
        // Unset means on when the backend is the Metal 4 one. Choosing a
        // backend called Metal 4 and running it with Metal 4 turned off is
        // not a default anybody would ask for, and it was the default: the
        // picker falls back to d3dmetal4 for a game with no valid saved
        // backend, so most games were getting D3DM_MTL4=0.
        self.d3dMtl4Enabled = data.d3dMtl4Enabled ?? (data.cxGraphicsBackend == "d3dmetal4" && OSVersion >= 27)
        self.d3dMaxFPS = data.d3dMaxFPS ?? 0
    }
    func importAutoConfig(data: GameOptionsData) {
        if let v = data.cxGraphicsBackend { self.cxGraphicsBackend = v }
        if let v = data.wineMSync { self.wineMSync = v }
        if let v = data.mtlHudEnabled { self.mtlHudEnabled = v }
        if let v = data.mtlHudDetail { self.mtlHudDetail = v }
        if let v = data.mtlHudOpacity { self.mtlHudOpacity = v }
        if let v = data.mtlHudAlignment { self.mtlHudAlignment = v }
        if let v = data.x87PatchEnabled { self.x87PatchEnabled = v }
        if let v = data.useArmBottle { self.useArmBottle = v }
        if let v = data.dx9PatchEnabled { self.dx9PatchEnabled = v }
        if let v = data.gameArguments { self.gameArguments = v }
        if let v = data.dxmtMetalFXSpatial { self.dxmtMetalFXSpatial = v }
        if let v = data.dxmtMetalSpatialUpscaleFactor { self.dxmtMetalSpatialUpscaleFactor = v }
        if let v = data.dxmtPreferredMaxFrameRate { self.dxmtPreferredMaxFrameRate = v }
        if let v = data.advertiseAVX { self.advertiseAVX = v }
        if let v = data.envVariables { self.envVariables = v }
        if let v = data.enableSDL { self.enableSDL = v }
        if let v = data.disableHidraw { self.disableHidraw = v }
        if let v = data.ue4Hack { self.ue4Hack = v }
        if let v = data.mvkArgBuff { self.mvkArgBuff = v }
        if let v = data.vulkanLib { self.vulkanLib = v }
        if let v = data.dxvk { self.dxvk = v }
        if let v = data.wineEsync { self.wineEsync = v }
        if let v = data.d3dMEnableMetalFX { self.d3dMEnableMetalFX = v }
        if let v = data.d3dSupportDXR { self.d3dSupportDXR = v }
        if let v = data.d3dMtl4Enabled { self.d3dMtl4Enabled = v }
        if let v = data.d3dMaxFPS { self.d3dMaxFPS = v }
    }
}

class GamesMeta: SteamACFMeta {
    var gameURL: URL?
    var libraryFolder: URL
    var isNative: Bool
    var appNames: [String]
    var id: String { libraryFolder.relativeString + appid }
    func isDownloaded() -> Bool {
        return (self.BytesToDownload == "0" || self.BytesToDownload == self.BytesDownloaded)
    }
    
    init(appid: String, installdir: String, gameURL: URL? = nil, isNative: Bool = false, libraryFolder: URL = URL(string: "/")!, bytesDownloaded: String, BytesTodownload: String, appNames: [String] = []) {
        self.gameURL = gameURL
        self.isNative = isNative
        self.libraryFolder = libraryFolder
        self.appNames = appNames
        super.init()
        self.appid = appid
        self.installdir = installdir
        self.BytesDownloaded = bytesDownloaded
        self.BytesToDownload = BytesTodownload
        self.appNames = appNames
    }
}

struct Game: Identifiable, Codable {
    var id: String
    var isNative: Bool
    var downloadProgress: Double
    var isInstalled: Bool
    var appNames: [String] = []
    var appExeURL: URL?
    var isCustom: Bool?
    
    // taken from SteamGame
    let type: String
    var name: String
    let steamAppID: Int
    let requiredAge: String
    let isFree: Bool
    let controllerSupport: String?
    let dlc: [Int]?
    
    var detailedDescription: String
    var aboutTheGame: String
    var shortDescription: String
    let supportedLanguages: String?
    
    var headerImage: String
    let capsuleImage: String
    let capsuleImageV5: String?
    let website: String?
    
    let pcRequirements: Requirements?
    let macRequirements: Requirements?
    let linuxRequirements: Requirements?
    
    let legalNotice: String?
    var developers: [String]
    var publishers: [String]
    
    let priceOverview: PriceOverview?
    let packages: [Int]?
    let packageGroups: [PackageGroup]?
    
    var platforms: Platforms
    let metacritic: Metacritic?
    
    var categories: [Category]
    var genres: [Genre]?
    
    let screenshots: [Screenshot]?
    let movies: [Movie]?
    
    let recommendations: Recommendations?
    let achievements: Achievements?
    let releaseDate: ReleaseDate
    let supportInfo: SupportInfo?
    
    let background: String?
    let backgroundRaw: String?
    
    let contentDescriptors: ContentDescriptors?
    let ratings: [String: RatingBody]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case isNative = "is_native"
        case downloadProgress = "download_progress"
        case isInstalled = "is_installed"
        case appNames = "app_names"
        case appExeURL = "app_exe_url"
        case isCustom = "is_custom"
        
        case type
        case name
        case steamAppID = "steam_app_id"
        case requiredAge = "required_age"
        case isFree = "is_free"
        case controllerSupport = "controller_support"
        case dlc
        
        case detailedDescription = "detailed_description"
        case aboutTheGame = "about_the_game"
        case shortDescription = "short_description"
        case supportedLanguages = "supported_languages"
        
        case headerImage = "header_image"
        case capsuleImage = "capsule_image"
        case capsuleImageV5 = "capsule_image_v5"
        case website
        
        case pcRequirements = "pc_requirements"
        case macRequirements = "mac_requirements"
        case linuxRequirements = "linux_requirements"
        
        case legalNotice = "legal_notice"
        case developers
        case publishers
        
        case priceOverview = "price_overview"
        case packages
        case packageGroups = "package_groups"
        
        case platforms
        case metacritic
        
        case categories
        case genres
        
        case screenshots
        case movies
        
        case recommendations
        case achievements
        case releaseDate = "release_date"
        case supportInfo = "support_info"
        
        case background
        case backgroundRaw = "background_raw"
        
        case contentDescriptors = "content_descriptors"
        case ratings
    }
    
    init(from: SteamGame, id: String, isNative: Bool, downloadProgress: Double, isInstalled: Bool, appNames: [String], isCustom: Bool? = false) {
        self.id = id
        self.isNative = isNative
        self.downloadProgress = downloadProgress
        self.isInstalled = isInstalled
        self.appNames = appNames
        
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
                displayType: "0",
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
        ratings: [
            "esrb": RatingBody(rating: "T", requiredAge: "13", descriptors: "Violence"),
            "pegi": RatingBody(rating: "16", requiredAge: "16", descriptors: "Violence"),
            "usk": RatingBody(rating: "12", requiredAge: "12", descriptors: "Violence")
        ]
    )
    static let mock = Game(from: Game.steamMock, id: "example", isNative: true, downloadProgress: 100, isInstalled: true, appNames: ["test.exe"], isCustom: true)
    static let steamEmptyGame = SteamGame(
        type: "game",
        name: "Game Name here",
        steamAppID: 0,
        requiredAge: "18",
        isFree: false,
        controllerSupport: "full",
        dlc: [],
        detailedDescription: "Game description here",
        aboutTheGame: "Game description here",
        shortDescription: "Short game description here",
        supportedLanguages: "English",
        headerImage: "",
        capsuleImage: "",
        capsuleImageV5: nil,
        website: "",
        pcRequirements: Requirements(minimum: "Windows 10, 8GB RAM", recommended: "Windows 11, 16GB RAM"),
        macRequirements: nil,
        linuxRequirements: nil,
        legalNotice: "All trademarks are property of their respective owners.",
        developers: [""],
        publishers: [""],
        priceOverview: PriceOverview(
            currency: "USD",
            initial: 0,
            final: 0,
            discountPercent: 0,
            initialFormatted: "$0",
            finalFormatted: "$0"
        ),
        packages: [],
        packageGroups: [],
        platforms: Platforms(windows: true, mac: false, linux: false),
        metacritic: nil,
        categories: [],
        genres: [],
        screenshots: nil,
        movies: nil,
        recommendations: nil,
        achievements: nil,
        releaseDate: ReleaseDate(comingSoon: false, date: "Jan 01, 2026"),
        supportInfo: nil,
        background: nil,
        backgroundRaw: nil,
        contentDescriptors: nil,
        ratings: nil
    )
    static let emptyGame = Game(from: Game.steamEmptyGame, id: "example", isNative: true, downloadProgress: 100, isInstalled: true, appNames: ["test.exe"])
}

struct GameResponse: Codable, Sendable {
    let data: Game
}

enum SortingOptions {
    case name
    case releaseDate
    case publisher
    case developer
    case installed
}

/// Installed and owned-but-not-installed are kept apart on purpose.
///
/// One list of four hundred titles where fifty-seven are playable and the rest
/// are a shopping catalogue is not a library; it is a haystack. Two tabs means
/// the everyday view stays the size of what you can actually run.
enum LibraryTab: String, CaseIterable, Identifiable {
    case installed
    case notInstalled
    /// Both at once, for when you would rather scroll than choose.
    case all

    var id: String { rawValue }
    var label: String {
        switch self {
        case .installed: return "Installed"
        case .notInstalled: return "Not installed"
        case .all: return "All"
        }
    }

    /// Whether this tab needs the owned library read off the disk.
    var needsOwned: Bool { self != .installed }
}

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

/// The columns of the list view, which is also the sort order.
enum LibraryColumn: String, CaseIterable, Identifiable {
    case name
    /// What it is installed AS -- which is one platform, the one that will run.
    case installedOn
    /// What it is available FOR. A different question: a title can ship for
    /// three systems and be installed as one of them.
    case supported
    case size
    /// Hours, and when last, as separate columns: either can be the one you
    /// want to sort by, and a single column can only sort by one of them.
    case played
    case lastPlayed

    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: return "Name"
        case .installedOn: return "Installed"
        case .supported: return "Available"
        case .size: return "Size"
        case .played: return "Played"
        case .lastPlayed: return "Last"
        }
    }
}

/// One row of the list view, from either tab.
///
/// The two tabs hold different types -- Game for what is installed, OwnedGame
/// for what is not -- and the list has to render both. Rather than a table that
/// knows about both, both produce this.
struct LibraryRow: Identifiable {
    let id: String
    let appID: String
    let name: String
    /// Every platform the title ships for.
    let platforms: Set<String>
    /// The one it is installed as, if it is installed. Not derivable from the
    /// set above: a title available for three systems is installed as one.
    let installedOn: String?
    /// Minutes, from Steam's own per-account config. The store API has no idea
    /// how long anyone has played anything.
    let playtimeMinutes: Int?
    /// Only known for installed titles: nothing on disk records the size of
    /// something that is not there.
    let sizeBytes: Int64?
    let lastPlayed: Date?
    let coverURL: URL?
    let isInstalled: Bool
}

class LibraryPageGlobals: ObservableObject {
    // Remembered across launches. Choosing the list and being handed the grid
    // again next time is not a default, it is the application forgetting.
    @Published var tab: LibraryTab = LibraryPageGlobals.restored(.tab) {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Key.tab) }
    }
    @Published var viewMode: LibraryViewMode = LibraryPageGlobals.restored(.viewMode) {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: Key.viewMode) }
    }
    @Published var sortColumn: LibraryColumn = LibraryPageGlobals.restored(.sortColumn) {
        didSet { UserDefaults.standard.set(sortColumn.rawValue, forKey: Key.sortColumn) }
    }
    @Published var sortAscending: Bool = UserDefaults.standard.object(forKey: Key.sortAscending) as? Bool ?? true {
        didSet { UserDefaults.standard.set(sortAscending, forKey: Key.sortAscending) }
    }

    private enum Key {
        static let tab = "raccoonbot.library.tab"
        static let viewMode = "raccoonbot.library.viewMode"
        static let sortColumn = "raccoonbot.library.sortColumn"
        static let sortAscending = "raccoonbot.library.sortAscending"
    }

    private enum Restorable { case tab, viewMode, sortColumn }

    /// Falls back to the default for anything unreadable -- a value written by
    /// a version that had a column this one does not, for instance.
    private static func restored(_ what: Restorable) -> LibraryTab {
        LibraryTab(rawValue: UserDefaults.standard.string(forKey: Key.tab) ?? "") ?? .installed
    }
    private static func restored(_ what: Restorable) -> LibraryViewMode {
        LibraryViewMode(rawValue: UserDefaults.standard.string(forKey: Key.viewMode) ?? "") ?? .grid
    }
    private static func restored(_ what: Restorable) -> LibraryColumn {
        LibraryColumn(rawValue: UserDefaults.standard.string(forKey: Key.sortColumn) ?? "") ?? .name
    }
    /// Everything owned and not installed, read from the disk. Empty until the
    /// not-installed tab is opened: there is no reason to walk appinfo.vdf for
    /// somebody who never looks at it.
    @Published var ownedGames: [OwnedGame] = []
    @Published var ownedLoaded: Bool = false
    /// Empty means every platform; a non-empty set is a whitelist.
    @Published var platformFilter: Set<String> = []
    /// app id -> how long, and when last. Read from localconfig.vdf, which is
    /// where Steam keeps it; `appdetails` is a store record and knows nothing
    /// about any particular person's play time.
    @Published var playStats: [String: (lastPlayed: Date?, playtime: Int?)] = [:]
    /// Titles hidden from the not-installed tab, remembered across launches.
    ///
    /// localconfig.vdf lists what this Steam has heard of, not what the account
    /// owns -- free weekends, trials and family-shared titles are all in it, and
    /// installing one answers "No licenses". Steam encrypts licensecache, so
    /// there is no way to tell from disk which is which. The user can, once, by
    /// trying; this remembers the answer so nobody has to try twice.
    @Published var hiddenAppIDs: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "raccoonbot.hiddenAppIDs") ?? []
    )

    func hide(appID: String) {
        hiddenAppIDs.insert(appID)
        UserDefaults.standard.set(Array(hiddenAppIDs), forKey: "raccoonbot.hiddenAppIDs")
    }

    func unhideAll() {
        hiddenAppIDs.removeAll()
        UserDefaults.standard.removeObject(forKey: "raccoonbot.hiddenAppIDs")
    }
    @Published var gamesMeta: [GamesMeta] = []
    @Published var folders: [String] = []
    @Published var showOptions: Bool = false
    @Published var showTools: Bool = false
    @Published var filter: String = ""
    @Published var showDetailView = false
    @Published var selectedGame: Game? = nil
    @Published var isLaunchingGame: Bool = false
    @Published var customAddedGames: [Game] = []
    @Published var games: [Game] = []
    @Published var sortBy: SortingOptions = SortingOptions.name
    @Published var playingID: String?
    
    init() {
        self.loadCustomAddedGames()
    }
    
    var allGamesCount: Int {
        return self.games.count + self.customAddedGames.count
    }
    
    var allGames: [Game] {
        self.games + self.customAddedGames
    }
    
    var filteredGames: [Game] {
        var games: [Game] = self.allGames
        if !platformFilter.isEmpty {
            games = games.filter { game in
                (game.platforms.windows && platformFilter.contains("windows"))
                || (game.platforms.mac && platformFilter.contains("macos"))
                || (game.platforms.linux && platformFilter.contains("linux"))
            }
        }
        if self.filter.isEmpty || self.filter.count < 3 {
            games = self.allGames
        } else {
            games = allGames.filter { item in
                self.filter.isEmpty || item.name.lowercased().contains(self.filter.lowercased())
            }
        }
        return games.sorted { lhs, rhs in
            switch self.sortBy {
            case SortingOptions.name:
                return lhs.name.lowercased() < rhs.name.lowercased()
            case .releaseDate:
                return lhs.releaseDate.date < rhs.releaseDate.date
            case .publisher:
                if(lhs.publishers.isEmpty) && (!rhs.publishers.isEmpty) { return false }
                if(!lhs.publishers.isEmpty) && (rhs.publishers.isEmpty) { return true }
                return lhs.publishers[0].lowercased() < rhs.publishers[0].lowercased()
            case .developer:
                if(lhs.developers.isEmpty) && (!rhs.developers.isEmpty) { return false }
                if(!lhs.developers.isEmpty) && (rhs.developers.isEmpty) { return true }
                return lhs.developers[0].lowercased() < rhs.developers[0].lowercased()
            case .installed:
                return lhs.isInstalled && !rhs.isInstalled
            }
        }
    }
    
    /// The rows for whichever tab is showing, filtered and sorted.
    /// How many titles this tab holds before any filtering.
    var tabTotal: Int {
        switch tab {
        case .installed:    return allGamesCount
        case .notInstalled: return ownedGames.count
        case .all:          return allGamesCount + ownedGames.count
        }
    }

    var rows: [LibraryRow] {
        let rows: [LibraryRow]
        switch tab {
        case .installed:    rows = installedRows
        case .notInstalled: rows = ownedRows
        case .all:          rows = installedRows + ownedRows
        }
        var shown = rows
        if !platformFilter.isEmpty {
            shown = shown.filter { !$0.platforms.isDisjoint(with: platformFilter) }
        }
        if self.filter.count >= 3 {
            let needle = self.filter.lowercased()
            shown = shown.filter { $0.name.lowercased().contains(needle) || $0.appID.contains(needle) }
        }
        return shown.sorted { lhs, rhs in
            let ascending = self.sortAscending
            switch self.sortColumn {
            case .name:
                let result = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                return ascending ? result : !result
            case .installedOn:
                let result = (lhs.installedOn ?? "~") < (rhs.installedOn ?? "~")
                return ascending ? result : !result
            case .supported:
                let result = lhs.platforms.sorted().joined() < rhs.platforms.sorted().joined()
                return ascending ? result : !result
            case .size:
                // Unknown sorts last in both directions: it is an absence, not
                // a size of zero.
                switch (lhs.sizeBytes, rhs.sizeBytes) {
                case let (l?, r?): return ascending ? l > r : l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return lhs.name < rhs.name
                }
            case .played:
                switch (lhs.playtimeMinutes, rhs.playtimeMinutes) {
                case let (l?, r?): return ascending ? l > r : l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return lhs.name < rhs.name
                }
            case .lastPlayed:
                switch (lhs.lastPlayed, rhs.lastPlayed) {
                case let (l?, r?): return ascending ? l > r : l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return lhs.name < rhs.name
                }
            }
        }
    }

    private var installedRows: [LibraryRow] {
        let sizes = Dictionary(gamesMeta.map { ($0.id, $0.SizeOnDisk.flatMap(Int64.init)) },
                               uniquingKeysWith: { first, _ in first })
        return allGames.map { game in
            var platforms: Set<String> = []
            if game.platforms.windows { platforms.insert("windows") }
            if game.platforms.mac { platforms.insert("macos") }
            if game.platforms.linux { platforms.insert("linux") }
            let stats = playStats[String(game.steamAppID)]
            return LibraryRow(id: game.id,
                              appID: String(game.steamAppID),
                              name: game.name,
                              platforms: platforms,
                              // What it is installed AS: the scan knows, because
                              // a native title comes out of a different library
                              // folder than one that runs in the bottle.
                              installedOn: game.isNative ? "macos" : "windows",
                              playtimeMinutes: stats?.playtime,
                              sizeBytes: sizes[game.id] ?? nil,
                              lastPlayed: stats?.lastPlayed,
                              coverURL: game.headerImage.isEmpty ? nil : URL(string: game.headerImage),
                              isInstalled: true)
        }
    }

    private var ownedRows: [LibraryRow] {
        ownedGames.filter { !hiddenAppIDs.contains($0.appID) }.map {
            LibraryRow(id: $0.appID, appID: $0.appID, name: $0.displayName,
                       platforms: $0.platforms,
                       // Nothing is installed, so there is nothing it is
                       // installed as. A dash, not a guess.
                       installedOn: nil,
                       playtimeMinutes: $0.playtimeMinutes,
                       sizeBytes: nil, lastPlayed: $0.lastPlayed,
                       coverURL: $0.coverURL, isInstalled: false)
        }
    }

    var filteredOwnedGames: [OwnedGame] {
        var owned = self.ownedGames.filter { !hiddenAppIDs.contains($0.appID) }
        if !platformFilter.isEmpty {
            owned = owned.filter { !$0.platforms.isDisjoint(with: platformFilter) }
        }
        if self.filter.count >= 3 {
            let needle = self.filter.lowercased()
            owned = owned.filter {
                $0.displayName.lowercased().contains(needle) || $0.appID.contains(needle)
            }
        }
        return owned.sorted { lhs, rhs in
            let ascending = self.sortAscending
            switch self.sortColumn {
            case .name:
                let result = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                return ascending ? result : !result
            case .supported:
                let result = lhs.platforms.sorted().joined() < rhs.platforms.sorted().joined()
                return ascending ? result : !result
            case .installedOn, .size:
                // Neither applies to something that is not installed, so this
                // keeps the order stable rather than shuffling rows under the
                // pointer for a column with nothing in it.
                let result = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                return ascending ? result : !result
            case .played:
                switch (lhs.playtimeMinutes, rhs.playtimeMinutes) {
                case let (l?, r?): return ascending ? l > r : l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return lhs.displayName < rhs.displayName
                }
            case .lastPlayed:
                // Never played sorts last in both directions: it is an absence,
                // not a very old date.
                switch (lhs.lastPlayed, rhs.lastPlayed) {
                case let (l?, r?): return ascending ? l > r : l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return lhs.displayName < rhs.displayName
                }
            }
        }
    }

    func loadCustomAddedGames() {
        let groupDefaults = UserDefaults(suiteName: suiteName)!
        if let savedGamesData = groupDefaults.data(forKey: "customAddedGames") {
            let decoder = JSONDecoder()
            guard let savedGames = try? decoder.decode([Game].self, from: savedGamesData) else { return }
            self.customAddedGames = savedGames
        }
    }
    
    func getCustomAddedGame(id: String) -> Game? {
        return self.customAddedGames.first(where: { $0.id == id })
    }
    
    func saveCustomAddedGames() {
        let groupDefaults = UserDefaults(suiteName: suiteName)!
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self.customAddedGames) else { return }
        groupDefaults.set(data, forKey: "customAddedGames")
    }
    
    func updateCustomAddedGames(gameData: Game) {
        if let index = self.customAddedGames.firstIndex(where: { $0.id == gameData.id }) {
            console.log("game \(self.customAddedGames[index].name) is being updated")
            console.log(String(describing: gameData))
            self.customAddedGames[index] = gameData
        }
        let groupDefaults = UserDefaults(suiteName: suiteName)!
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self.customAddedGames) else { return }
        groupDefaults.set(data, forKey: "customAddedGames")
    }
    
    func deleteCustomAddedGame(game: Game) {
        self.customAddedGames.removeAll { $0.id == game.id }
        saveCustomAddedGames()
    }
    
    func setLoader(state: Bool) {
        isLaunchingGame = state
    }
    
    func setPlayingID( _ id: String?) {
        playingID = id
    }
}

final class AppGlobals: ObservableObject {
    @Published var selectedBottle: String = ""
    /// The bottle used by games marked to run on ARM. Empty means none chosen,
    /// which is a state the interface has to warn about rather than paper over:
    /// a bottle's architecture is fixed when it is created, so there is no way
    /// to promote the normal one.
    @Published var selectedArmBottle: String = ""
    @Published var userID: String? = nil
    @Published var cxAppPath: String?
    @Published var windowsSteamFolder: URL?
    
    /// The bottles this application is configured with -- the one set anything
    /// that writes into a bottle is allowed to touch. One question, one place
    /// that answers it; see `ConfiguredBottles`.
    var configuredBottles: [BottleReference] {
        ConfiguredBottles.configured(selected: selectedBottle, arm: selectedArmBottle)
    }

    init(selectedBottle: String? = "", cxAppPath: String? = nil) {
        self.selectedBottle = readUsrDefOptionString(key: "selectedBottle") ?? ""
        self.selectedArmBottle = readUsrDefOptionString(key: "selectedArmBottle") ?? ""
        self.cxAppPath = readUsrDefOptionString(key: "cxAppPath")
    }
}

