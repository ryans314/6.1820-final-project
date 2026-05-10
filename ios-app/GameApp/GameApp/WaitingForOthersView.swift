//
//  WaitingForOthersView.swift
//  GameApp
//

import SwiftUI

struct WaitingForOthersView: View {
    @ObservedObject var networkManager: NetworkManager
    var isDemoMode: Bool = false

    private let blue = Color(red: 0.28, green: 0.68, blue: 0.97)

    var body: some View {
        ZStack {
            blue.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                // Small label
                Text("YOU'RE DONE!")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)

                // Large title
                VStack(alignment: .leading, spacing: 0) {
                    Text("WAITING")
                    Text("ON THE")
                    Text("OTHERS.")
                }
                .font(.system(size: 76, weight: .black))
                .foregroundColor(.black)
                .padding(.horizontal, 24)

                Spacer()
            }

            // DEMO MODE: advance to voting without a server
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
