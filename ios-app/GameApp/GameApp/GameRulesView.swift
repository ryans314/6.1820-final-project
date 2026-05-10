//
//  GameRulesView.swift
//  GameApp
//

import SwiftUI

struct GameRulesView: View {
    let onReady: () -> Void

    private let yellow = Color(red: 1.0, green: 0.87, blue: 0.0)

    var body: some View {
        ZStack {
            yellow.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // ── Title ────────────────────────────────────────────
                Text("GAME RULES.")
                    .font(.system(size: 64, weight: .black))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.top, 52)
                    .padding(.bottom, 20)

                // ── Rule cards ───────────────────────────────────────
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        RuleCard(
                            number: "01",
                            title:  "SET UP THE PUCKS",
                            description:   "Place the 3 pucks far away from each other. At least in 2 different rooms."
                        )
                        RuleCard(
                            number: "02",
                            title:  "WORK TOGETHER",
                            description:   "Everyone must finish their tasks to move onto the next round."
                        )
                        RuleCard(
                            number: "03",
                            title:  "THE MOLE POISONS",
                            description:   "One imposter walks among you. Every round, they can poison one agent by getting closer than 1.5m."
                        )
                        RuleCard(
                            number: "04",
                            title:  "GATHER & VOTE.",
                            description:   "If the imposter poisons everyone, and doesn't get voted out. They win. Otherwise, you win."
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

                // ── I'M READY button ─────────────────────────────────
                Button(action: onReady) {
                    Text("I'M READY")
                        .font(.system(size: 18, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(yellow)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                }
                .background(Color.black)
                .clipShape(Capsule())
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 52)
            }
        }
    }
}

private struct RuleCard: View {
    let number: String
    let title: String
    let description: String

    private let yellow = Color(red: 1.0, green: 0.87, blue: 0.0)

    var body: some View {
        HStack(alignment: .top, spacing: 20) {

            Text(number)
                .font(.system(size: 38, weight: .black))
                .foregroundColor(yellow)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(yellow)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
