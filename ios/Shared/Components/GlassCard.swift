import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(VaySpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .vayShadow(.card)
    }
}

// MARK: - Colored Glass Variant

struct ColoredGlassCard<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color = .vayPrimary, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(VaySpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous)
                    .stroke(tint.opacity(0.2), lineWidth: 0.5)
            )
            .vayShadow(.subtle)
    }
}
