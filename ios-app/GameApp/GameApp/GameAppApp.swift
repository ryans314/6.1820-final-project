//
//  GameAppApp.swift
//  GameApp
//
//  Created by MSC on 4/20/26.
//

import SwiftUI

@main
struct GameAppApp: App {
    @StateObject private var networkManager = NetworkManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView(networkManager: networkManager)
                .onOpenURL { url in
                    handleUniversalLink(url)
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
