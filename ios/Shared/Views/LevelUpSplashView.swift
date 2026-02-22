import SwiftUI
import ConfettiSwiftUI

struct LevelUpSplashView: View {
    let level: Int
    let onDismiss: () -> Void

    @State private var confettiCounter = 0
    @State private var appeared = false
    @Environment(\.vayMotion) private var motion

    var body: some View {
        ZStack {
            // Background
            Color.vayBackground
                .ignoresSafeArea()

            VStack(spacing: VaySpacing.xxl) {
                Spacer()

                // Icon / Graphic
                ZStack {
                    Circle()
                        .fill(Color.vayPrimary.opacity(0.1))
                        .frame(width: 160, height: 160)

                    Image(systemName: "star.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(Color.vayPrimary)
                        .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
                }
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, VaySpacing.lg)

                // Text Content
                VStack(spacing: VaySpacing.md) {
                    Text("Новый уровень!")
                        .font(VayFont.heading(32))
                        .foregroundStyle(Color.primary)
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)

                    Text("Вы достигли уровня \(level)")
                        .font(VayFont.heading(24))
                        .foregroundStyle(Color.vayPrimary)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)

                    Text("Отличная работа! Продолжайте в том же духе, чтобы открывать новые достижения.")
                        .font(VayFont.body(16))
                        .foregroundStyle(Color.vaySecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, VaySpacing.xl)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                }

                Spacer()

                // Continue Button
                Button(action: onDismiss) {
                    Text("Отлично")
                        .vayPillButton()
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .padding(.horizontal, VaySpacing.xl)
                .padding(.bottom, VaySpacing.xl)
            }
            .confettiCannon(
                counter: $confettiCounter,
                num: 80,
                confettis: [
                    .text("⭐️"), .text("🌟"), .text("✨"), .text("🎉"),
                    .shape(.circle), .shape(.triangle)
                ],
                colors: [.vayPrimary, .vayAccent, .yellow, .orange, .cyan],
                confettiSize: 25,
                rainHeight: 800,
                openingAngle: Angle(degrees: 0),
                closingAngle: Angle(degrees: 360),
                radius: 400,
                repetitions: 2,
                repetitionInterval: 0.5
            )
        }
        .onAppear {
            withAnimation(motion.springSnappy.delay(0.1)) {
                appeared = true
            }
            
            // Fire Confetti with slight delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                confettiCounter += 1
            }
        }
    }
}

#Preview {
    LevelUpSplashView(level: 5) {}
}
