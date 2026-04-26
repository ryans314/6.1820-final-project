//
//  ContentView.swift
//  GameApp
//
//  Created by MSC on 4/20/26.
//

import SwiftUI
import CoreNFC
import Combine

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

class NFCReader: ObservableObject {
    var objectWillChange = PassthroughSubject<Void, Never>()
    
    @Published var lastScannedId: String? = nil
    @Published var errorMessage: String? = nil
    
    private var session: NFCNDEFReaderSession? = nil
    private var onScan: ((String) -> Void)? = nil
    private let delegate = NFCDelegate() // separate NSObject delegate

    func beginScanning(onScan: @escaping (String) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            errorMessage = "NFC not available on this device"
            return
        }
        self.onScan = onScan
        errorMessage = nil
        delegate.onScan = { [weak self] puckId in
            self?.lastScannedId = puckId
            self?.onScan?(puckId)
        }
        delegate.onError = { [weak self] message in
            self?.errorMessage = message
        }
        session = NFCNDEFReaderSession(delegate: delegate, queue: .main, invalidateAfterFirstRead: true)
        session?.alertMessage = "Hold your iPhone near the puck to scan."
        session?.begin()
    }
}

// MARK: - NFC Delegate (NSObject required by CoreNFC)
class NFCDelegate: NSObject, NFCNDEFReaderSessionDelegate {
    var onScan: ((String) -> Void)? = nil
    var onError: ((String) -> Void)? = nil

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let record = messages.first?.records.first else {
            onError?("Could not read tag data")
            return
        }
        let (text, _) = record.wellKnownTypeTextPayload()
        if let text = text {
            onScan?(text)
        } else if let payload = String(data: record.payload, encoding: .utf8) {
            let puckId = payload.count > 3 ? String(payload.dropFirst(3)) : payload
            onScan?(puckId)
        } else {
            onError?("Could not parse tag payload")
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        if nfcError?.code != .readerSessionInvalidationErrorUserCanceled {
            onError?(error.localizedDescription)
        }
    }
}

struct GameView: View {
    @ObservedObject var networkManager: NetworkManager
    @StateObject private var nfcReader = NFCReader()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Role: You Are \(networkManager.isImposter ? "The Imposter" : "Safe")")
                .bold().font(.title)
            
            Text("Current Task: \(networkManager.currentTask ?? "Waiting...")")
            
            Button("Scan NFC Tag") {
            nfcReader.beginScanning { puckId in
                networkManager.sendTap(puckId: puckId)
            }
        }
        .buttonStyle(.borderedProminent)
        
        if let lastScanned = nfcReader.lastScannedId {
            Text("Last Scanned: \(lastScanned)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        
        if let error = nfcReader.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
        }

                 
        }
        
    }
}
#Preview {
        ContentView()
}
