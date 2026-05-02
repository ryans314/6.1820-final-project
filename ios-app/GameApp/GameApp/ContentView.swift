//
//  ContentView.swift
//  GameApp
//
//  Created by MSC on 4/20/26.
//

import SwiftUI
import CoreNFC
import Combine
import NearbyInteraction

extension NetworkManager {
    
    static var demo: NetworkManager {
        let view_type = "agent_task_infected" // options: (entry, lobby, imposter_no_task, agent_no_task, imposter_task, agent_task, agent_task_infected, imposter_task_error, agent_task_error, imposter_task_complete, agent_task_complete, voting, imposter_reveal)
        
        let nm = NetworkManager()
        nm.isConnected      = true
        nm.connectionFailed = false
        nm.gameStarted = true
        nm.gameStatus = "in_progress"
        nm.isImposter = false
        nm.taskError = false
        nm.currentTask = "OneTap"
        nm.taskDescription = "Tap the red puck"
        nm.currentRound     = "2"
        nm.imposter = nil
        nm.isInfected = false
        nm.lobbyPlayers     = [
            LobbyPlayer(id: "uuid-001", username: "alice"),
            LobbyPlayer(id: "uuid-002", username: "bob"),
            LobbyPlayer(id: "uuid-003", username: "carol"),
        ]
        
        if (view_type == "entry") {
            nm.gameStarted = false
            nm.isConnected = false
        } else if (view_type == "lobby") {
            nm.gameStarted = false
            nm.gameStatus = "Lobby"
        }
        
        if (view_type == "imposter_no_task" || view_type == "imposter_task" || view_type == "imposter_task_error" || view_type == "imposter_task_complete" ) {
            nm.isImposter = true
        }
        
        if (view_type == "imposter_no_task" || view_type == "agent_no_task") {
            nm.currentTask = nil
            nm.taskDescription = nil
        }
        
        if (view_type == "imposter_task_error" || view_type == "agent_task_error") {
            nm.taskError = true
        }
        
        if (view_type == "imposter_task_complete" || view_type == "agent_task_complete") {
            nm.currentTask = "Completed"
        }
        
        if (view_type == "voting") {
            nm.gameStatus = "voting"
        }
        
        if (view_type == "imposter_reveal") {
            nm.gameStatus = "imposter_revealed"
            nm.imposter = "Belle"
        }
        
        if (view_type == "agent_task_infected") {
            nm.isInfected = true
        }
    
        return nm
    }
}

struct ContentView: View {
    @ObservedObject var networkManager: NetworkManager
    
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
                if (networkManager.gameStatus == "in_progress") {
                    GameView(networkManager: networkManager)
                } else if (networkManager.gameStatus == "voting") {
                    VotingView(networkManager: networkManager)
                } else if (networkManager.gameStatus == "imposter_revealed") {
                    ImposterRevealView(networkManager: networkManager)
                }
            }
            if networkManager.connectionFailed {
                Text("Connection failed, please try again")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
        }
        .padding()
    }
}

struct ConnectView: View {
    @ObservedObject var networkManager: NetworkManager
    @State private var username: String = ""
    
    private var supportsUWB: Bool {
            NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("GAME NAME")
                .font(.largeTitle).bold()
        }
        
        if !supportsUWB {
                HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Some game features may not work as your device does not support UWB")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
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
    @StateObject private var uwbManager = UWBManager()
    @State private var showInfectedAlert = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Role: You Are \(networkManager.isImposter ? "The Imposter" : "Safe")")
                .bold().font(.title)
            if (networkManager.isInfected) {
                Text("You're infected")
            }
            Text("Current Round: \(networkManager.currentRound ?? "...")/3")
            
            if (networkManager.currentTask == "Completed") {
                Text("Task completed!")
            } else {
                Text("Your Task: \(networkManager.currentTask ?? "Waiting...")")
                Text(networkManager.taskDescription ?? "")
                
                if (networkManager.taskError) {
                    Text("You tapped the wrong puck!")
                }
            }
            
            
            
            // Only show UWB section for imposter
            if networkManager.isImposter {
                Divider()
                
                if uwbManager.hasNearbyPlayer {
                    Text("⚠️ Player within range!")
                        .foregroundColor(.red)
                        .bold()
                    
                    Button("🦠 Infect") {
                        // Send infect action to server
                        // Find the closest player
                        if let closest = uwbManager.nearbyPlayers.min(by: { $0.value < $1.value }) {
                            networkManager.sendInfect(targetId: closest.key)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Text("No players within 5m")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                
                // Debug: show all nearby distances
                ForEach(Array(uwbManager.nearbyPlayers.keys), id: \.self) { id in
                    Text("\(id): \(String(format: "%.1f", uwbManager.nearbyPlayers[id] ?? 0))m")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            uwbManager.isImposter = networkManager.isImposter
            uwbManager.start(clientId: networkManager.uuid)
            if networkManager.isInfected { showInfectedAlert = true }
        }
        .onDisappear {
            uwbManager.stop()
        }
        .onChange(of: networkManager.isInfected) { _, infected in
            if infected { showInfectedAlert = true }
        }
        .alert("You've Been Infected!", isPresented: $showInfectedAlert) {
            Button("OK") { }
        } message: {
            Text("The imposter got you. You are now infected.")
        }
    }
}


struct VotingView: View {
    @ObservedObject var networkManager: NetworkManager
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Time to vote!")
                .font(.largeTitle).bold()
            
            Button("Done voting!") {
                networkManager.imposterReveal()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            
        }
    }
}

struct ImposterRevealView: View {
    @ObservedObject var networkManager: NetworkManager
    
    var body: some View {
        VStack(spacing: 16) {
            Text("The imposter is \(networkManager.imposter ?? "")")
                .font(.largeTitle).bold()
            
        }
    }
}
