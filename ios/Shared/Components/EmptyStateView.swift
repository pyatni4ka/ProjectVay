import SwiftUI
import Lottie

struct EmptyStateView: View {
    let icon: String // Fallback if no Lottie
    let lottieName: String?
    let title: String
    let subtitle: String
    let actionTitle: String?
    let action: (() -> Void)?

    @Environment(\.vayMotion) private var motion
    @State private var appeared = false

    init(
        icon: String,
        lottieName: String? = nil,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.lottieName = lottieName
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: VaySpacing.xl) {
            if let lottieName {
                LottieView(animation: .named(lottieName))
                    .playing(loopMode: .loop)
                    .frame(width: 120, height: 120)
                    .padding(.top, VaySpacing.md)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Color.vayPrimary.opacity(0.75))
                    .symbolEffect(.pulse.byLayer, options: motion.reduceMotion ? .nonRepeating : .repeating)
                    .padding(.top, VaySpacing.md)
            }

            VStack(spacing: VaySpacing.sm) {
                Text(title)
                    .font(VayFont.heading(18))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "barcode.viewfinder")
                        .vayPillButton(color: .vayPrimary)
                }
                .buttonStyle(.plain)
                .vayAccessibilityLabel(actionTitle, hint: "Открывает быстрый переход")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(VaySpacing.xxl)
        .vayCard()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(motion.springSmooth) {
                appeared = true
            }
        }
        .vayAccessibilityLabel("\(title). \(subtitle)")
    }
}
