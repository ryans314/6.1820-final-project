//
//  IntroView.swift
//  GameApp
//

import SwiftUI

struct IntroView: View {
    let onFinish: () -> Void

    private let lime = Color(red: 0.75, green: 1.0, blue: 0.10)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Mascot with lime ring
                ZStack {
                    Circle().fill(lime).frame(width: 272, height: 272)        // outer lime ring
                    Circle().fill(Color.black).frame(width: 224, height: 224) // black gap
                    IntroMascotFace().frame(width: 210, height: 210)          // pink face
                }
                .padding(.bottom, 36)

                // Title — centered under the mascot
                VStack(alignment: .center, spacing: 0) {
                    Text("SNIFF")
                    Text("OUT THE")
                    Text("MOLE")
                }
                .font(.system(size: 64, weight: .black))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        // Auto-advance to next screen after 3 seconds
        .task {
            try? await Task.sleep(for: .seconds(3))
            onFinish()
        }
    }
}

// Scaled-down version of the mascot face (210pt, proportional to the 270pt ConnectView mascot)
private struct IntroMascotFace: View {
    private let pink   = Color(red: 0.97, green: 0.22, blue: 0.60)
    private let stripe = Color(white: 0.76)

    var body: some View {
        ZStack {
            Circle().fill(pink)
            Rectangle()
                .fill(stripe)
                .frame(height: 40)
                .offset(y: 52)
            HStack(spacing: 28) { eyeView; eyeView }
                .offset(y: -17)
            Ellipse()
                .fill(Color.black)
                .frame(width: 14, height: 10)
                .offset(y: 19)
        }
        .clipShape(Circle())
    }

    private var eyeView: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 42, height: 42)
            Circle().fill(Color.black).frame(width: 19, height: 19)
        }
    }
}
