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
        let view_type = "imposter_no_task" // options: (entry, lobby, imposter_no_task, agent_no_task, imposter_task, agent_task, agent_task_infected, imposter_task_error, agent_task_error, imposter_task_complete, agent_task_complete, voting, imposter_reveal, game_complete) — task_complete and poisoned are driven by currentTask/isInfected flags above
        
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

        if (view_type == "game_complete") {
            nm.gameStatus = "game_complete"
        }

        return nm
    }
}

struct ContentView: View {
    @ObservedObject var networkManager: NetworkManager
    @State private var hasSeenRoleReveal = false
    @State private var showGameComplete = false
    @State private var acknowledgedTaskComplete = false
    @State private var acknowledgedPoisoned = false
    // ── DEMO MODE ── set to true to run a local 3-player simulation on one device
    // ── set back to false for production builds
    private let isDemoMode = false

    var body: some View {
        VStack(spacing: 20) {
            if !networkManager.isConnected {
                // --- Connection Screen ---
                ConnectView(
                    networkManager: networkManager,
                    onJoin: isDemoMode
                        ? { name in
                            // DEMO MODE: skip server, seed 3 mock players in the lobby
                            networkManager.username = name.isEmpty ? "Awa" : name
                            networkManager.lobbyPlayers = [
                                LobbyPlayer(id: "demo-001", username: networkManager.username),
                                LobbyPlayer(id: "demo-002", username: "Player 2"),
                                LobbyPlayer(id: "demo-003", username: "Player 3"),
                            ]
                            networkManager.isConnected = true
                          }
                        : { name in networkManager.connect(username: name) }
                )
            } else if !networkManager.gameStarted {
                // --- Lobby Screen ---
                LobbyView(
                    networkManager: networkManager,
                    onStartGame: isDemoMode
                        ? {
                            // DEMO MODE: assign role + first task locally, no server needed
                            networkManager.isImposter = true // change to true to test the Mole role
                            networkManager.playersInfected = ["demo-002": false, "demo-003": false]
                            networkManager.currentTask = "OneTap"
                            networkManager.taskDescription = "Tap the red puck"
                            networkManager.taskDirection = "Red: 1 puck"
                            networkManager.currentRound = "1"
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
                    if networkManager.isInfected && !acknowledgedPoisoned {
                        PoisonedView(onBoohoo: { acknowledgedPoisoned = true })
                    } else if networkManager.currentTask == "Completed" && !acknowledgedTaskComplete {
                        TaskCompleteView(onContinue: { acknowledgedTaskComplete = true })
                    } else if networkManager.currentTask == "Completed" {
                        // Task done + acknowledged → show waiting screen until server moves to voting
                        WaitingForOthersView(networkManager: networkManager, isDemoMode: isDemoMode)
                    } else {
                        GameView(networkManager: networkManager, isDemoMode: isDemoMode)
                    }
                } else if networkManager.gameStatus == "voting" {
                    VotingView(networkManager: networkManager, isDemoMode: isDemoMode)
                } else if networkManager.gameStatus == "imposter_revealed" && !showGameComplete {
                    MoleRevealView(networkManager: networkManager, onContinue: { showGameComplete = true })
                } else if networkManager.gameStatus == "game_complete" || showGameComplete {
                    GameCompleteView(networkManager: networkManager, isDemoMode: isDemoMode)
                }
            }
        }
        .onChange(of: networkManager.gameStarted) { _, started in
            if !started {
                hasSeenRoleReveal = false
                showGameComplete = false
                acknowledgedTaskComplete = false
                acknowledgedPoisoned = false
            }
        }
        .onChange(of: networkManager.currentTask) { _, task in
            if task != "Completed" { acknowledgedTaskComplete = false }
        }
        .onAppear {
            if networkManager.gameStatus != "Lobby" {
                networkManager.connect(username: networkManager.username)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if networkManager.gameStatus != "Lobby" && !networkManager.isConnected {
                networkManager.connect(username: networkManager.username)
            }
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
                Text("\(networkManager.lobbyPlayers.count) / 4 joined · While waiting, set up your 3 game pucks by placing one on a table in the current room, one on the floor in a nearby room, and one on the other side of this room. Make sure that the pucks are far away from each other.")
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
                .font(.system(size: 17, weight: .bold))
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
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isReady ? lime : Color.white.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
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
                
                if (role == "MOLE") {
                    Text("Try and get 2 meters within other players to infect them, but don't get caught! You can only infect one player per round, and they won't show up if you've already infected them. Use your phone to complete your tasks so you can blend in.")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.7))
                        .padding(.horizontal, 24)
                } else {
                    Text("Use your phone to complete your tasks. Find the imposter, and stay away from them. They can infect you if you're within 2 meters of each other. Good luck!")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.7))
                        .padding(.horizontal, 24)
                }

                

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
    var isDemoMode: Bool = false
    @StateObject private var uwbManager = UWBManager()
    @State private var poisonDeliveredTo: String? = nil
    @State private var showFakePoisoned = false
    @State private var passedOnPoison = false
    @State private var awaitingInfectionResult = false
    @State private var showInfectionFailureAlert = false
    @State private var showIncognitoMenu = false      // incognito mode action sheet
    @State private var showManualPoisonAction = false  // PASS/POISON overlay (no UWB required)
    @State private var showFakePoisonOverlay = false   // fake poison display — no game state change


    private var nearestPlayerId: String? {
        uwbManager.nearbyPlayers
            .filter { networkManager.playersInfected[$0.key] == false }
            .min(by: { $0.value < $1.value })?.key
    }

    private var nearestPlayerName: String {
        guard let id = nearestPlayerId else { return "Agent" }
        return networkManager.lobbyPlayers.first { $0.id == id }?.username ?? "Agent"
    }

    private var showPoisonAction: Bool {
        networkManager.isImposter && !networkManager.infectedSomeoneThisRound && (nearestPlayerId != nil) && !passedOnPoison && poisonDeliveredTo == nil && !showFakePoisoned
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Incognito pill — part of layout flow, sits above the task card
                if networkManager.isImposter || isDemoMode {
                    HStack {
                        Spacer()
                        Button(action: { showIncognitoMenu = true }) {
                            Text("INCOGNITO MODE")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color(white: 0.18))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 56)
                    .padding(.bottom, 12)
                }

                GameTaskCard(
                    round: networkManager.currentRound ?? "?",
                    title: networkManager.taskDescription?.uppercased() ?? "STANDBY.",
                    description: networkManager.taskDirection,
                    hasError: networkManager.taskError,
                    progressBar: networkManager.taskProgress
                )
                .padding(.horizontal, 20)
                .padding(.top, (networkManager.isImposter || isDemoMode) ? 0 : 56)

                Spacer()

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

            if showPoisonAction {
                PoisonActionView(
                    onPass: { passedOnPoison = true },
                    onPoison: {
                        let name = nearestPlayerName
                        if let targetId = nearestPlayerId {
                            networkManager.sendInfect(targetId: targetId)
                            awaitingInfectionResult = true
                        }
                        poisonDeliveredTo = name
                    }
                )
            }
            
            if (!awaitingInfectionResult && (networkManager.infectionFailure == nil) && networkManager.infectedSomeoneThisRound) {
                if let deliveredTo = poisonDeliveredTo {
                    PoisonDeliveredView(playerName: deliveredTo, onContinue: {
                        poisonDeliveredTo = nil
                        showFakePoisoned = true
                    })
                }
            }
            
            if showFakePoisoned {
                FakePoisonedView(onBoohoo: { showFakePoisoned = false })
            }

            // INCOGNITO → PASS / POISON: real poison flow, no UWB proximity required
            if showManualPoisonAction {
                PoisonActionView(
                    onPass: { showManualPoisonAction = false },
                    onPoison: {
                        showManualPoisonAction = false
                        if let targetId = nearestPlayerId {
                            // Real game: infect the nearest UWB player as normal
                            networkManager.sendInfect(targetId: targetId)
                            awaitingInfectionResult = true
                            poisonDeliveredTo = nearestPlayerName
                        } else if isDemoMode,
                                  let target = networkManager.playersInfected.first(where: { !$0.value }) {
                            // Demo mode: no UWB — infect the first available mock player
                            networkManager.sendInfect(targetId: target.key)
                            awaitingInfectionResult = true
                            poisonDeliveredTo = networkManager.lobbyPlayers
                                .first { $0.id == target.key }?.username ?? "Agent"
                        }
                    }
                )
            }

            // INCOGNITO → FAKE POISON SCREEN: visual decoy only — no networking, no game state change
            if showFakePoisonOverlay {
                FakePoisonedView(onBoohoo: { showFakePoisonOverlay = false })
            }

            // DEMO MODE: floating buttons to skip ahead
            if isDemoMode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            // Mark task complete → shows TaskCompleteView then WaitingForOthersView
                            Button("DEMO ▶ TASK DONE") {
                                networkManager.currentTask = "Completed"
                                networkManager.taskProgress = 1.0
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.85))
                            .clipShape(Capsule())

                            // Skip straight to voting
                            Button("DEMO ▶ VOTING") {
                                networkManager.gameStatus = "voting"
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.85))
                            .clipShape(Capsule())
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 40)
                    }
                }
            }

            // Incognito Mode custom modal — on top of everything in the ZStack
            if showIncognitoMenu {
                IncognitoMenuView(
                    onPassPoison: { showIncognitoMenu = false; showManualPoisonAction = true },
                    onFakePoison: { showIncognitoMenu = false; showFakePoisonOverlay = true },
                    onDismiss:    { showIncognitoMenu = false }
                )
            }
        }
        .onAppear {
            uwbManager.isImposter = networkManager.isImposter
            uwbManager.start(clientId: networkManager.uuid)
        }
        .onDisappear {
            uwbManager.stop()
        }
        .onChange(of: uwbManager.hasNearbyPlayer) { _, hasPlayer in
            if !hasPlayer { passedOnPoison = false }
        }
        .onChange(of: networkManager.infectedSomeoneThisRound) { old, new in
            if new {
                awaitingInfectionResult = false
            }
        }
        .onChange(of: networkManager.infectionFailure) { old, new in
            if new != nil {
                awaitingInfectionResult = false
                poisonDeliveredTo = nil
                showInfectionFailureAlert = true
            }
        }
        .alert("Infection Failed", isPresented: $showInfectionFailureAlert) {
            Button("OK", role: .cancel) {
                networkManager.infectionFailure = nil
            }
        } message: {
            Text(networkManager.infectionFailure ?? "Something went wrong")
        }
    }
}

private struct PoisonActionView: View {
    let onPass: () -> Void
    let onPoison: () -> Void

    private let pink = Color(red: 0.97, green: 0.22, blue: 0.60)

    var body: some View {
        ZStack {
            pink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Text("INCOGNITO MODE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                MoleMascotView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                Spacer()

                VStack(alignment: .leading, spacing: 0) {
                    Text("STRIKE")
                    Text("NOW OR")
                    Text("STAY LOW")
                }
                .font(.system(size: 72, weight: .black))
                .foregroundColor(.black)
                .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: onPass) {
                        Text("PASS")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(Color(white: 0.3))
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                    }
                    .background(Color(white: 0.82).opacity(0.6))
                    .clipShape(Capsule())

                    Button(action: onPoison) {
                        Text("POISON")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.white)
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

private struct PoisonDeliveredView: View {
    let playerName: String
    let onContinue: () -> Void

    private let pink = Color(red: 0.97, green: 0.22, blue: 0.60)

    var body: some View {
        ZStack {
            pink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Text("INCOGNITO MODE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                MoleMascotView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                Spacer()

                Text("POISON DELIVERED TO")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(Color.black.opacity(0.6))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                Text("(\(playerName.uppercased()))")
                    .font(.system(size: 52, weight: .black))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)

                Spacer()

                Button(action: onContinue) {
                    Text("CONTINUE")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white)
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

private struct FakePoisonedView: View {
    let onBoohoo: () -> Void

    private let red = Color(red: 1.0, green: 0.13, blue: 0.14)

    var body: some View {
        ZStack {
            red.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Text("INCOGNITO MODE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)

                DeadFaceMascotView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                Spacer()

                Text("SYMPTOMS ARE SPREADING!")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 0) {
                    Text("YOU'VE")
                    Text("BEEN")
                    Text("POISONED")
                }
                .font(.system(size: 72, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 24)

                Spacer()

                Button(action: onBoohoo) {
                    Text("BOOHOO")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(red)
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

private struct IncognitoMenuView: View {
    let onPassPoison: () -> Void
    let onFakePoison: () -> Void
    let onDismiss:    () -> Void

    private let blue     = Color(red: 0.28, green: 0.62, blue: 0.97)
    private let pink     = Color(red: 0.97, green: 0.22, blue: 0.60)
    private let charcoal = Color(red: 0.12, green: 0.12, blue: 0.12)

    var body: some View {
        ZStack {
            // Dimmed backdrop — tap outside to dismiss
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Card
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ───────────────────────────────────
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("INCOGNITO MODE")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(blue)
                        Text("Choose your cover.")
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)

                // ── PASS / POISON ─────────────────────────────
                Button(action: onPassPoison) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PASS / POISON")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            Text("Real mole action")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.50))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .background(blue.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(blue, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)

                // ── FAKE POISON SCREEN ────────────────────────
                Button(action: onFakePoison) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FAKE POISON SCREEN")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            Text("Visual bluff only — no game effect")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.50))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(pink)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .background(pink.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(pink, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // ── Cancel ────────────────────────────────────
                Button(action: onDismiss) {
                    Text("CANCEL")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.38))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(charcoal)
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(blue.opacity(0.55), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 24)
        }
    }
}

private struct GameTaskCard: View {
    let round: String
    let title: String
    let description: String?
    let hasError: Bool?
    let progressBar: Float

    private let blue = Color(red: 0.28, green: 0.62, blue: 0.97)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Round / error label
            Text(hasError == nil ? "\(round)/3 TASK" : hasError == true ? "⚠ WRONG PUCK" : "✓ CORRECT PUCK")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.5)
                .foregroundColor(hasError == nil ? .black : hasError == true ? Color(red: 0.85, green: 0.1, blue: 0.1) : Color(red: 0.1, green: 0.7, blue: 0.1))
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


struct TaskCompleteView: View {
    let onContinue: () -> Void

    private let blue = Color(red: 0.36, green: 0.72, blue: 0.97)

    var body: some View {
        ZStack {
            blue.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Checkmark mascot ─────────────────────────────
                ZStack {
                    Circle().fill(Color.black)
                    Image(systemName: "checkmark")
                        .font(.system(size: 80, weight: .heavy))
                        .foregroundColor(blue)
                }
                .frame(width: 220, height: 220)
                .frame(maxWidth: .infinity)
                .padding(.top, 56)

                Spacer()

                // ── Title ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    Text("TASK")
                    Text("DONE!")
                }
                .font(.system(size: 80, weight: .black))
                .foregroundColor(.black)
                .padding(.horizontal, 24)

                Spacer()

                // ── Continue button ──────────────────────────────
                Button(action: onContinue) {
                    Text("CONTINUE")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white)
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

private struct DeadFaceMascotView: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            HStack(spacing: 30) {
                Image(systemName: "xmark")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundColor(.white)
                Image(systemName: "xmark")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundColor(.white)
            }
            .offset(y: -18)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .frame(width: 56, height: 8)
                .offset(y: 30)
        }
        .frame(width: 230, height: 230)
    }
}

struct PoisonedView: View {
    let onBoohoo: () -> Void

    private let red = Color(red: 1.0, green: 0.13, blue: 0.14)

    var body: some View {
        ZStack {
            red.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Dead face mascot ─────────────────────────────
                DeadFaceMascotView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 56)

                Spacer()

                // ── Label ────────────────────────────────────────
                Text("SYMPTOMS ARE SPREADING!")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                // ── Title ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    Text("YOU'VE")
                    Text("BEEN")
                    Text("POISONED")
                }
                .font(.system(size: 72, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 24)

                Spacer()

                // ── Boohoo button ────────────────────────────────
                Button(action: onBoohoo) {
                    Text("BOOHOO")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(red)
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

struct VotingView: View {
    @ObservedObject var networkManager: NetworkManager
    var isDemoMode: Bool = false

    private let orange = Color(red: 1.0, green: 0.47, blue: 0.0)

    var body: some View {
        ZStack {
            orange.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                Spacer()

                // ── Label pill ───────────────────────────────────
                Text("VOTING PERIOD")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.15))
                    .clipShape(Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                // ── Title ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    Text("GATHER")
                    Text("UP.")
                    Text("POINT")
                    Text("FINGERS!")
                }
                .font(.system(size: 72, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 24)

                Spacer()

                // ── Reveal button ────────────────────────────────
                Button(action: {
                    if isDemoMode {
                        // DEMO MODE: reveal locally instead of sending WebSocket message
                        networkManager.imposter = "Player 3"
                        networkManager.gameStatus = "imposter_revealed"
                    } else {
                        networkManager.imposterReveal()
                    }
                }) {
                    Text("REVEAL")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(orange)
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

struct MoleRevealView: View {
    @ObservedObject var networkManager: NetworkManager
    let onContinue: () -> Void

    private let pink = Color(red: 0.97, green: 0.22, blue: 0.60)

    var body: some View {
        ZStack {
            pink.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Mascot ───────────────────────────────────────
                MoleMascotView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 56)

                Spacer()

                // ── Name ─────────────────────────────────────────
                Text("(\((networkManager.imposter ?? "???").uppercased()))")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                // ── "WAS THE MOLE !" card ─────────────────────────
                VStack(spacing: 0) {
                    Text("WAS THE")
                    Text("MOLE !")
                }
                .font(.system(size: 52, weight: .black))
                .foregroundColor(pink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 24)

                Spacer()

                // ── Continue button ──────────────────────────────
                Button(action: onContinue) {
                    Text("CONTINUE")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white)
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

struct GameCompleteView: View {
    @ObservedObject var networkManager: NetworkManager
    var isDemoMode: Bool = false

    private let yellow = Color(red: 1.0, green: 0.87, blue: 0.0)

    var body: some View {
        ZStack {
            yellow.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Mascot ───────────────────────────────────────
                MascotView()
                    .frame(width: 270, height: 270)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 44)
                    .padding(.bottom, 22)

                // ── Title ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    Text("YOU'VE")
                    Text("COMPLETE")
                    Text("THE GAME!")
                }
                .font(.system(size: 64, weight: .black))
                .padding(.horizontal, 24)

                // ── Subtitle ─────────────────────────────────────
                Text("A real-world social deduction game")
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.7))
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                Spacer()

                // ── Play Again button ─────────────────────────────
                Button(action: {
                    if isDemoMode {
                        // DEMO MODE: reset state locally instead of sending WebSocket message
                        networkManager.disconnect()
                    } else {
                        networkManager.sendEndGame()
                    }
                }) {
                    Text("PLAY AGAIN")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(yellow)
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
