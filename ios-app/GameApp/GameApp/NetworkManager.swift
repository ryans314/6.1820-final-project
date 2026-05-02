//
//  NetworkManager.swift
//  GameApp
//
//  Created by MSC on 4/20/26.
//
//

import Foundation
import Combine
import UIKit

struct LobbyPlayer: Identifiable {
    let id: String // player_id
    let username: String
}
class NetworkManager: ObservableObject {
    private var webSocketTask: URLSessionWebSocketTask?
    
    //Published variables - visible to SwiftUI views
    @Published var isConnected = false
    @Published var connectionFailed = false
    @Published var lobbyPlayers: [LobbyPlayer] = []
    @Published var gameStarted = false
    @Published var currentTask: String?
    @Published var gameStatus: String = "Lobby"
    @Published var isImposter: Bool = false
    @Published var errorMessage: String?
    @Published var currentRound: String?
    @Published var taskError: Bool = false
    @Published var taskDescription: String?
    @Published var uuid = UIDevice.current.identifierForVendor!.uuidString
    @Published var imposter: String?
    @Published var isInfected: Bool = false
    
    private let urlBaseStr = "wss://recollect-conjure-thesis.ngrok-free.dev/ws/phone" // change depending on where server is
    private var username: String = ""
    
    func connect(username: String) {
        self.username = username
        DispatchQueue.main.async {
            self.connectionFailed = false
            self.errorMessage = nil
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        let serverURL = URL(string: "\(urlBaseStr)/\(uuid)")!
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        sendIdentify()
        receiveMessage()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionFailed = false
            self.lobbyPlayers = []
            self.gameStarted = false
        }
    }
    
    private func sendIdentify() {
        
        let payload: [String: Any] = [
            "type": "identify",
            "player_id": uuid,
            "username": username 
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let string = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(string)) { error in
                if let error = error { print("Identify send error: \(error)") }
            }
        }
    }
    
    func sendStartGame() {
        let payload: [String: Any] = ["type": "start_game"]
        if let data =  try? JSONSerialization.data(withJSONObject: payload),
           let string = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(string)) {error in
                if let error = error { print("Start game send error: \(error)")}
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("WebSocket error: \(error)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.connectionFailed = true
                }
                
            case .success(let message):
                DispatchQueue.main.async {
                    if !self.isConnected { self.isConnected = true }
                }
                switch message {
                case .string(let text):
                    self.handleIncomingJSON(text)
                default:
                    break
                }
                self.receiveMessage() //keep listening after current message is received
            }
        }
    }
    
    private func handleIncomingJSON(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else {return}
        
        DispatchQueue.main.async {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                switch json["type"] as? String {
                case "connection_ack":
                    self.isConnected = true
                    print("Handshake confirmed \(json["player_id"] ?? "")")
                    
                case "player_list":
                    if let players = json["players"] as? [[String: Any]] {
                        self.lobbyPlayers = players.compactMap { dict in
                            guard let id = dict["player_id"] as? String,
                                  let username = dict["username"] as? String
                            else { return nil }
                            return LobbyPlayer(id: id, username: username)
                        }
                    }
                case "game_start":
                    self.gameStarted = true
                    self.gameStatus = "in_progress"
                    self.isImposter = json["is_imposter"] as! Bool
                    
                case "error":
                    self.errorMessage = json["message"] as? String
                    
                case "new_task":
                    self.currentTask = json["task_type"] as? String
                    self.currentRound = json["round"] as? String
                    self.taskDescription = json["task_description"] as? String
                    
                case "game_status":
                    self.gameStatus = json["status"] as? String ?? self.gameStatus
                
                case "task_complete":
                    self.currentTask = "Completed"

                case "incorrect_puck":
                    self.taskError = true
                
                case "imposter_revealed":
                    self.imposter = json["imposter"] as? String
                    
                case "infected":
                    self.isInfected = true
                    
                default:
                    print("Unknown message type: \(json["type"] ?? "nil")")
                }
            }
        }
    }
    
    func sendTap(puckId: String) {
        print("sendTap called with puckId: \(puckId)")
        
        let json: [String: Any] = [
            "type": "nfc_tap",
            "puck_id": puckId
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: json),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("Error sending tap: \(error)")
                }
            }
        }
    }
    
    func sendInfect(targetId: String) {
        print("sendInfect called infect: \(targetId)")
        let message: [String: Any] = [
            "type": "infect",
            "target_id": targetId
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("Error sending tap: \(error)")
                }
            }
        }
    }
    
    func imposterReveal() {
        
        let json: [String: Any] = [
            "type": "imposter_reveal"
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: json),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("Error sending tap: \(error)")
                }
            }
        }
    }
}
