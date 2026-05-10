//
//  WaitingForOthersView.swift
//  GameApp
//

import SwiftUI

struct WaitingForOthersView: View {
    @ObservedObject var networkManager: NetworkManager
    var isDemoMode: Bool = false

    // ── ADJUST PLACEHOLDER PLAYERS HERE ──────────────────────────────
    // In production this data would come from a server "task_status" message.
    // For now, edit names and done-status here to test different states.
    private let demoPlayers: [(name: String, done: Bool)] = [
        ("NATHAN", true),
        ("AWA",    true),
        ("BELLE",  false),
    ]
    // ─────────────────────────────────────────────────────────────────

    private let blue = Color(red: 0.28, green: 0.68, blue: 0.97)

    var body: some View {
        ZStack {
            blue.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Small label ──────────────────────────────────────
                Text("YOU'RE DONE!")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.top, 56)

                // ── Large title ──────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    Text("WAITING")
                    Text("ON THE")
                    Text("OTHERS.")
                }
                .font(.system(size: 68, weight: .black))
                .foregroundColor(.black)
                .padding(.horizontal, 24)
                .padding(.top, 4)

                Spacer()

                // ── Section header ───────────────────────────────────
                Text("TASKS IN PROGRESS")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.black.opacity(0.65))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                // ── Player rows ──────────────────────────────────────
                VStack(spacing: 10) {
                    ForEach(demoPlayers, id: \.name) { player in
                        WaitingPlayerRow(name: player.name, done: player.done)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }

            // DEMO MODE: floating button to advance to voting
            if isDemoMode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button("DEMO ▶ VOTING") {
                            networkManager.gameStatus = "voting"
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
    }
}

private struct WaitingPlayerRow: View {
    let name: String
    let done: Bool

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
        .background(Color.white.opacity(0.30))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
