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
        let view_type = "entry" // options: (entry, lobby, imposter_no_task, agent_no_task, imposter_task, agent_task, agent_task_infected, imposter_task_error, agent_task_error, imposter_task_complete, agent_task_complete, voting, imposter_reveal)
        
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
    @State private var hasSeenRoleReveal = false
    private let isDemoMode = false

    var body: some View {
        VStack(spacing: 20) {
            if !networkManager.isConnected {
                // --- Connection Screen ---
                ConnectView(
                    networkManager: networkManager,
                    onJoin: isDemoMode
                        ? { _ in networkManager.isConnected = true }
                        : { name in networkManager.connect(username: name) }
                )
            } else if !networkManager.gameStarted {
                // --- Lobby Screen ---
                LobbyView(
                    networkManager: networkManager,
                    onStartGame: isDemoMode
                        ? {
                            networkManager.gameStarted = true
                            networkManager.gameStatus = "in_progress"
                          }
                        : { networkManager.sendStartGame() }
                )
            } else {
                // --- Game Screen ---
                if !hasSeenRoleReveal {
                    RoleRevealView(networkManager: networkManager, hasSeenRoleReveal: $hasSeenRoleReveal)
                } else if networkManager.gameStatus == "in_progress" {
                    GameView(networkManager: networkManager)
                } else if networkManager.gameStatus == "voting" {
                    VotingView(networkManager: networkManager)
                } else if networkManager.gameStatus == "imposter_revealed" {
                    ImposterRevealView(networkManager: networkManager)
                }
            }
        }
        .onChange(of: networkManager.gameStarted) { _, started in
            if !started { hasSeenRoleReveal = false }
        }
    }
}

struct ConnectView: View {
    @ObservedObject var networkManager: NetworkManager
    var onJoin: (String) -> Void
    @State private var username: String = ""

    private var supportsUWB: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    private let yellow = Color(red: 1.0, green: 0.87, blue: 0.0)
    private let dark   = Color(red: 0.14, green: 0.13, blue: 0.14)

    var body: some View {
        ZStack {
            yellow.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Mascot ──────────────────────────────────────
                MascotView()
                    .frame(width: 270, height: 270)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 44)
                    .padding(.bottom, 22)

                // ── Title ───────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    Text("SNIFF")
                    Text("OUT THE")
                    Text("MOLE")
                }
                .font(.system(size: 64, weight: .black))
                .padding(.horizontal, 24)

                // ── Subtitle ────────────────────────────────────
                Text("A real-world social deduction game. Find pucks. Trust no one. Vote with your gut.")
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.7))
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                Spacer()

                // ── Inputs ──────────────────────────────────────
                VStack(spacing: 14) {
                    if !supportsUWB {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Some features may not work — device doesn't support UWB")
                                .font(.caption)
                                .foregroundColor(.black.opacity(0.65))
                        }
                    }

                    // Name input pill
                    VStack(spacing: 4) {
                        Text("YOUR NAME")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.45))
                        ZStack {
                            if username.isEmpty {
                                Text("tap to type")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white.opacity(0.25))
                            }
                            TextField("", text: $username)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .tint(.white)
                                .multilineTextAlignment(.center)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(dark)
                    .clipShape(Capsule())

                    if networkManager.connectionFailed {
                        Text("Connection failed, please try again")
                            .foregroundColor(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    // Join button
                    Button(action: { onJoin(username) }) {
                        Text(networkManager.connectionFailed ? "RECONNECT" : "JOIN THE GAME")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(yellow)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                    }
                    .background(Color.black)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
    }
}

private struct MascotView: View {
    private let pink   = Color(red: 0.97, green: 0.22, blue: 0.60)
    private let stripe = Color(white: 0.76)

    var body: some View {
        ZStack {
            // Pink base
            Circle().fill(pink)
            // Gray horizontal stripe — clipped to circle by clipShape below
            Rectangle()
                .fill(stripe)
                .frame(height: 52)
                .offset(y: 66)
            // Eyes
            HStack(spacing: 36) {
                eyeView
                eyeView
            }
            .offset(y: -22)
            // Mouth
            Ellipse()
                .fill(Color.black)
                .frame(width: 18, height: 13)
                .offset(y: 24)
        }
        .clipShape(Circle())
    }

    private var eyeView: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 54, height: 54)
            Circle().fill(Color.black).frame(width: 24, height: 24)
        }
    }
}

struct LobbyView: View {
    @ObservedObject var networkManager: NetworkManager
    var onStartGame: () -> Void

    private let blue = Color(red: 0.28, green: 0.68, blue: 0.97)
    private let lime = Color(red: 0.75, green: 1.0, blue: 0.10)

    var body: some View {
        ZStack {
            blue.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Title ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    Text("WAITING")
                    Text("ROOM.")
                }
                .font(.system(size: 64, weight: .black))
                .padding(.horizontal, 24)
                .padding(.top, 52)

                // ── Subtitle ─────────────────────────────────────
                Text("\(networkManager.lobbyPlayers.count) / 4 joined · keep your phone with you but don't show others")
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.75))
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                // ── Player list ──────────────────────────────────
                VStack(spacing: 12) {
                    ForEach(networkManager.lobbyPlayers) { player in
                        LobbyPlayerRow(name: player.username, isReady: true, lime: lime)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)

                Spacer()

                // ── Start button ─────────────────────────────────
                Button(action: onStartGame) {
                    Text("START THE GAME")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(blue.opacity(networkManager.lobbyPlayers.count < 3 ? 0.4 : 1.0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                }
                .background(networkManager.lobbyPlayers.count < 3 ? Color.gray : Color.black)
                .clipShape(Capsule())
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
                .disabled(networkManager.lobbyPlayers.count < 3)
            }
        }
    }
}

private struct LobbyPlayerRow: View {
    let name: String
    let isReady: Bool
    let lime: Color

    var body: some View {
        HStack {
            Text(name.uppercased())
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text("READY")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundColor(isReady ? Color(white: 0.1) : Color.white.opacity(0.3))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isReady ? lime : Color.white.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct RoleRevealView: View {
    @ObservedObject var networkManager: NetworkManager
    @Binding var hasSeenRoleReveal: Bool

    private let agentBg = Color(red: 0.75, green: 1.0, blue: 0.10)
    private let moleBg  = Color(red: 0.97, green: 0.22, blue: 0.60)

    private var bg:   Color  { networkManager.isImposter ? moleBg : agentBg }
    private var role: String { networkManager.isImposter ? "MOLE" : "AGENT" }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Mascot ──────────────────────────────────────
                Group {
                    if networkManager.isImposter {
                        MoleMascotView()
                    } else {
                        AgentMascotView()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 44)

                Spacer()

                // ── Role label ──────────────────────────────────
                Text("YOU ARE THE —")
                    .font(.system(size: 17, weight: .bold))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)

                Text(role)
                    .font(.system(size: 88, weight: .black))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                Text("Complete your tasks. Spot the imposter. Survive the vote.")
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.7))
                    .padding(.horizontal, 24)

                Spacer()

                // ── Button ──────────────────────────────────────
                Button(action: { hasSeenRoleReveal = true }) {
                    Text("LET'S BEGIN")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                }
                .background(Color.black)
                .clipShape(Capsule())
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
    }
}

private func roleMascotEye(size: CGFloat, pupil: CGFloat) -> some View {
    ZStack {
        Circle().fill(Color.white).frame(width: size, height: size)
        Circle().fill(Color.black).frame(width: pupil, height: pupil)
    }
}

private struct AgentMascotView: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            HStack(spacing: 32) {
                roleMascotEye(size: 52, pupil: 23)
                roleMascotEye(size: 52, pupil: 23)
            }
            .offset(y: -15)
        }
        .frame(width: 260, height: 260)
    }
}

private struct RoleMascotTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MoleMascotView: View {
    var body: some View {
        ZStack(alignment: .top) {
            // Ears — sit above and overlap top of circle
            HStack(spacing: 80) {
                RoleMascotTriangle().fill(Color.black).frame(width: 36, height: 48)
                RoleMascotTriangle().fill(Color.black).frame(width: 36, height: 48)
            }
            // Circle body
            ZStack {
                Circle().fill(Color.black)
                // Asymmetric eyes: left larger, right smaller
                HStack(spacing: 22) {
                    roleMascotEye(size: 52, pupil: 23)
                    roleMascotEye(size: 38, pupil: 17)
                }
                .offset(y: -10)
                // Fangs
                HStack(spacing: 6) {
                    RoleMascotTriangle().fill(Color.white).frame(width: 9, height: 13)
                    RoleMascotTriangle().fill(Color.white).frame(width: 9, height: 13)
                }
                .offset(y: 44)
            }
            .frame(width: 260, height: 260)
            .offset(y: 26)
        }
        .frame(width: 260, height: 286)
    }
}

struct GameView: View {
    @ObservedObject var networkManager: NetworkManager
    @StateObject private var uwbManager = UWBManager()
    @State private var showInfectedAlert = false

    private var isCompleted: Bool { networkManager.currentTask == "Completed" }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                GameTaskCard(
                    round: networkManager.currentRound ?? "?",
                    title: isCompleted
                        ? "TASK\nCOMPLETE!"
                        : (networkManager.taskDescription?.uppercased() ?? "STANDBY."),
                    description: isCompleted ? "Nice work. Sit tight for the next round." : networkManager.taskDirection,
                    hasError: networkManager.taskError,
                    progressBar: networkManager.taskProgress
                )
                .padding(.horizontal, 20)
                .padding(.top, 56)

                Spacer()

                // Imposter infect button — only visible when a player is within UWB range
                if networkManager.isImposter && uwbManager.hasNearbyPlayer {
                    Button {
                        if let closest = uwbManager.nearbyPlayers.min(by: { $0.value < $1.value }) {
                            networkManager.sendInfect(targetId: closest.key)
                        }
                    } label: {
                        Text("INFECT")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                    }
                    .background(Color(red: 0.97, green: 0.22, blue: 0.60))
                    .clipShape(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }

                if !isCompleted {
                    GeometryReader { geo in
                        (Text("Hold\n near puck for 3 seconds\n")
                            .foregroundColor(Color(white: 0.38))
                        + Text("and tap the pop up")
                            .foregroundColor(.white))
                        .font(.system(size: geo.size.height * 0.1, weight: .black))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.bottom, 24)
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

private struct GameTaskCard: View {
    let round: String
    let title: String
    let description: String?
    let hasError: Bool
    let progressBar: Float

    private let blue = Color(red: 0.28, green: 0.62, blue: 0.97)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Round / error label
            Text(hasError ? "⚠ WRONG PUCK" : "\(round)/3 TASK")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.5)
                .foregroundColor(hasError ? Color(red: 0.85, green: 0.1, blue: 0.1) : .black)
                .padding(.top, 28)
                .padding(.horizontal, 28)

            // Large stacked title
            Text(title)
                .font(.system(size: 25, weight: .black))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, 28)

            // Puck illustration
            GamePuckView()
                .padding(.horizontal, 28)
                .padding(.top, 28)

            // Instruction / description text
            if let desc = description {
                Text(desc)
                    .font(.system(size: 18))
                    .foregroundColor(.black.opacity(0.65))
                    .padding(.top, 20)
                    .padding(.horizontal, 28)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            let _ = print("progressBar value: \(progressBar)")
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.15))
                    .frame(height: 8)
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .frame(height: 8)
                    .scaleEffect(x: CGFloat(progressBar), anchor: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)

            Spacer().frame(height: 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(blue)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

private struct GamePuckView: View {
    var body: some View {
        ZStack {
            // Drop shadow
            Ellipse()
                .fill(Color(white: 0.10))
                .frame(width: 112, height: 20)
                .offset(y: 12)
                .blur(radius: 6)
            // Cylinder side (darker)
            Ellipse()
                .fill(Color(white: 0.18))
                .frame(width: 112, height: 36)
            // Top face (slightly lighter)
            Ellipse()
                .fill(Color(white: 0.26))
                .frame(width: 112, height: 26)
                .offset(y: -5)
        }
        .frame(height: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
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
