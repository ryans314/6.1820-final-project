//
//  ContentView.swift
//  GameApp
//
//  Created by MSC on 4/20/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var networkManager = NetworkManager()
    
    var body: some View {
        VStack(spacing: 20) {
            
            if !networkManager.isConnected {
                // --- Connection Screen ---
                ConnectView(networkManager: networkManager)
            } else if !networkManager.gameStarted {
                // --- Lobby Screen ---
                LobbyView(networkManager: networkManager)
            } else {
                // --- Game Screen ---
                GameView(networkManager: networkManager)
            }
//            if networkManager.connectionFailed {
//                Text("Connection failed, please try again")
//                    .foregroundColor(.red)
//                    .font(.subheadline)
//            }
//            
//            if !networkManager.isConnected {
//                Button(networkManager.connectionFailed ? "Reconnect" : "Connect") {
//                    networkManager.connect()
//                }
//                .buttonStyle(.borderedProminent)
//            }
//            
//            if networkManager.isConnected {
//                Text("Game Status: \(networkManager.gameStatus)")
//                    .foregroundColor(.green)
//                
//                if networkManager.isImposter {
//                    Text("Role: IMPOSTER")
//                        .foregroundColor(.red)
//                        .bold()
//                } else {
//                    Text("Role: Healthy")
//                        .foregroundColor(.green)
//                        .bold()
//                }
//                
//                Text("Current Task: \(networkManager.currentTask ?? "Waiting...")")
//                
//                Button("Simulate NFC Tap" ) {
//                    networkManager.sendTap(puckId: "puck_A1")
//                }.buttonStyle(.borderedProminent)
//            }
//            
            
            
            
        }
        .padding()
    }
}

struct ConnectView: View {
    @ObservedObject var networkManager: NetworkManager
    @State private var username: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("GAME NAME")
                .font(.largeTitle).bold()
        }
        
        TextField("Enter username", text: $username)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 20)
        
        
        if networkManager.connectionFailed {
            Text("Connection failed, please try again")
                .foregroundColor(.red)
                .font(.subheadline)
        }
        Button(networkManager.connectionFailed ? "Reconnect" : "Join Game") {
            networkManager.connect(username: username)
        }
        .buttonStyle(.borderedProminent)

    }
}

struct LobbyView: View {
    @ObservedObject var networkManager: NetworkManager
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Lobby")
                .font(.largeTitle).bold()
            
            Text("\(networkManager.lobbyPlayers.count) player(s) connected")
            
            List(networkManager.lobbyPlayers) { player in
                HStack {
                    Image(systemName: "person.fill")
                    Text(player.username)
                    Spacer()
                    Text(player.id)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            
            if let error = networkManager.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            
            Button("Start Game") {
                networkManager.sendStartGame()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            
            Button("Disconnect") {
                networkManager.disconnect()
            }
            .foregroundColor(.red)
        }
    }
}

struct GameView: View {
    @ObservedObject var networkManager: NetworkManager
    var body: some View {
        VStack(spacing: 20) {
            Text("Role: You Are \(networkManager.isImposter ? "The Imposter" : "Safe")")
                .bold().font(.title)
            
            Text("Current Task: \(networkManager.currentTask ?? "Waiting...")")
            
            Button("Simulate NFC Tap") {
                networkManager.sendTap(puckId: "puck_A1")
            }
            .buttonStyle(.borderedProminent)
                 
                 
        }
        
    }
}
#Preview {
        ContentView()
}
