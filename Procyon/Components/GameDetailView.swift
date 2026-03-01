//
//  GameView.swift
//  Procyon
//
//  Created by Italo Mandara on 31/01/2026.
//

import SwiftUI
import Kingfisher
import Flow
import AVKit

struct GameDetailView: View {
    @Binding var game: Game?
    @State private var player = AVPlayer()
    @State private var isMuted: Bool = true
    @EnvironmentObject var libraryPageGlobals: LibraryPageGlobals
    @StateObject var gameOptions = GameOptions()
    var gameFolder: String {
        let meta = getMeta(libraryPageGlobals.gamesMeta, byID: String(game!.id))!
        return meta.libraryFolder.appendingPathComponent(meta.installdir).path(percentEncoded: false)
    }
    
    var body: some View {
        if (game != nil) {
            VStack (alignment: .leading) {
                ZStack(alignment: .bottom ) {
                    if (game!.movies != nil) {
                        PlayerLayerView(player: player)
                            .ignoresSafeArea()
                            .frame(height: 540)
                            .position(x: 460, y: 260)
                            .onAppear {
                                let url = URL(string: game!.movies![0].hlsH264!)!
                                player = AVPlayer(url: url)
                                player.isMuted = true
                                player.play()
                            }
                            .onDisappear {
                                player.pause()
                            }
                    } else {
                        KFImage(URL(string: game!.headerImage))
                            .placeholder {
                                ProgressView()
                            }
                            .resizable()
                            .scaledToFit()
                    }
                    GameHeader(game: $game, showDetailView: $libraryPageGlobals.showDetailView)
                        .padding(30)
                        .padding(.top, 40)
                        .background(
                            LinearGradient(
                                colors: [
                                    .black.opacity(0),
                                    .black.opacity(0.8),
                                    .black.opacity(1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(.bottom, game!.movies != nil ? 20 : 0)
                }
                VStack (alignment: .leading) {
                    HStack (alignment: .top){
                        VStack(alignment: .leading) {
                            if(game!.legalNotice != nil){
                                Text(game!.legalNotice!).font(.footnote).padding(.bottom)
                            }
                            HStack{
                                if (game!.isFree == true){
                                    AccentTag("Free to Play").padding(.bottom)
                                }
                                if (game!.requiredAge != "0"){
                                    AccentTag("Age: \(game!.requiredAge)+").padding(.bottom)
                                }
                            }
                            if(game!.contentDescriptors?.notes != nil){
                                Text(game!.contentDescriptors!.notes!).padding(.bottom)
                            }
                            Text(game!.detailedDescription).padding(.bottom)
                            // TO DO: add the following data
                            //                            "ratings": {
                            //                                "dejus": {
                            //                                    "rating": "14",
                            //                                    "descriptors": "Violência",
                            //                                    "use_age_gate": "true",
                            //                                    "required_age": "14"
                            //                                },
                            //                                "steam_germany": {
                            //                                    "rating_generated": "1",
                            //                                    "rating": "18",
                            //                                    "required_age": "18",
                            //                                    "banned": "0",
                            //                                    "use_age_gate": "0",
                            //                                    "descriptors": "Gewalt"
                            //                                }
                            //                            }
                            //                            "dlc": [
                            //                                1366500,
                            //                                1612680,
                            //                                1612700,
                            //                                1612710,
                            //                                1612720,
                            //                                1621630,
                            //                                1621631,
                            //                                1621650,
                            //                                1621651,
                            //                                1621660,
                            //                                1621661,
                            //                                1621670
                            //                            ],
                            
//                            "price_overview": {
//                                "currency": "USD",
//                                "initial": 1999,
//                                "final": 399,
//                                "discount_percent": 80,
//                                "initial_formatted": "$19.99",
//                                "final_formatted": "$3.99"
//                            },
                            
//                            "recommendations": {
//                                "total": 439
//                            },
                            
//                            "release_date": {
//                                "coming_soon": false,
//                                "date": "Dec 5, 2019"
//                            },
//                            "support_info": {
//                                "url": "www.rawfury.com",
//                                "email": "support@rawfury.com"
//                            },
                            if(game!.pcRequirements != nil){
                                VStack(alignment: .leading) {
                                    Text("PC Requirements:").font(.title3).padding(.bottom, 5)
                                    RequirementsWidget(requirements: game!.pcRequirements)
                                }.padding(.bottom)
                            }
                            if(game!.macRequirements != nil){
                                VStack(alignment: .leading) {
                                    Text("Mac Requirements:").font(.title3).padding(.bottom, 5)
                                    RequirementsWidget(requirements:game!.macRequirements)
                                }.padding(.bottom)
                            }
                            if(game!.linuxRequirements != nil){
                                VStack(alignment: .leading) {
                                    Text("Linux Requirements:").font(.title3).padding(.bottom, 5)
                                    RequirementsWidget(requirements:game!.linuxRequirements)
                                }.padding(.bottom)
                            }
                        }.padding(.bottom).padding(.trailing, 20)
                        Spacer()
                        VStack(alignment: .leading) {
                            if (game!.genres != nil && game!.genres!.count > 0){
                                Text("Genre:")
                                HFlow(alignment: .center) {
                                    ForEach(game!.genres!, id: \.id) { genre in
                                        Tag(genre.description)
                                            .padding(.vertical, 0.5)
                                    }
                                }
                                .padding(.bottom)
                            }
                            
                            if (game!.categories.count > 0){
                                Text("Category:")
                                HFlow(alignment: .center) {
                                    ForEach(game!.categories, id: \.id) { category in
                                        Tag(category.description)
                                            .padding(.vertical, 0.5)
                                    }
                                }
                                .padding(.bottom)
                            }
                            
                            let languages: [String] = (game!.supportedLanguages ?? "")
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }

                            if !languages.isEmpty {
                                Text("Supported languages:")
                                HFlow(alignment: .center) {
                                    ForEach(Array(languages.enumerated()), id: \.offset) { pair in
                                        AccentTag(pair.element)
                                            .padding(.vertical, 0.5)
                                    }
                                }.padding(.bottom)
                            }
                        }.frame(width: 200)
                    }
                    
                    VStack (alignment: .leading) {
                        if(game!.screenshots != nil && game!.screenshots!.count > 0) {
                            Text("Screenshots:").font(.title2).padding(.top)
                            LazyVGrid(columns: [
                                GridItem(.flexible(maximum: .infinity)),
                                GridItem(.flexible(maximum: .infinity)),
                                GridItem(.flexible(maximum: .infinity))
                            ]) {
                                ForEach(game!.screenshots!, id: \.id) { screenshot in
                                    KFImage(URL(string: screenshot.pathThumbnail))
                                        .placeholder {
                                            ProgressView()
                                        }
                                        .resizable()
                                        .scaledToFit()
                                    //                                    .frame(width: 180, height: 100)
                                }
                            }
                        }
                        
                        if (game!.movies != nil) {
                            Text("Videos:").font(.title2).padding(.top)
                            LazyVGrid(columns: [
                                GridItem(.flexible(maximum: .infinity)),
                                GridItem(.flexible(maximum: .infinity)),
                                GridItem(.flexible(maximum: .infinity))
                            ]) {
                                ForEach(game!.movies!, id: \.id) { movie in
                                    KFImage(URL(string: movie.thumbnail))
                                        .placeholder {
                                            ProgressView()
                                        }
                                        .resizable()
                                        .scaledToFit()
                                    //                                    .frame(width: 180, height: 100)
                                }
                            }
                            
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, game!.movies == nil ? 30: -5)
                .padding(.bottom, 30)
            }
            .background(.accent.mix(with: .black, by: 0.6).opacity(0.9))
            .frame(width: windowWidth - 100)
            .environmentObject(gameOptions)
        }
    }
}

#Preview {
    @State @Previewable var game: Game? = .mock
    @State @Previewable var showDetailView: Bool = true
    
    ZStack (alignment: .topTrailing) {
        ScrollView {
            GameDetailView(game: $game)
        }
    }
}
    
