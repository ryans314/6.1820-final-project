//
//  GameAppApp.swift
//  GameApp
//
//  Created by MSC on 4/20/26.
//

import SwiftUI

// Top-level navigation: Intro → Rules → Game
// The Demo Mode flag that bypasses the server lives in ContentView.swift (isDemoMode).
enum AppScreen { case intro, rules, game }

@main
struct GameAppApp: App {
    @State private var screen: AppScreen = .intro
    @StateObject private var networkManager = NetworkManager()

    var body: some Scene {
        WindowGroup {
            if screen == .intro {
                IntroView(onFinish: { screen = .rules })
            } else if screen == .rules {
                GameRulesView(onReady: { screen = .game })
            } else {
                ContentView(networkManager: networkManager)
                    .onOpenURL { handleUniversalLink($0) }
            }
        }
    }

    func handleUniversalLink(_ url: URL) {
        guard url.host == "scan" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        guard let puckId = components?.queryItems?.first(where: { $0.name == "puckId" })?.value else {
            print("no puckId found")
            return
        }
        networkManager.sendTap(puckId: puckId)
    }
}
