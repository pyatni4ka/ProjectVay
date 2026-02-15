import SwiftUI

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?
    let color: Color

    @State private var appeared = false

    init(
        icon: String,
        title: String,
        value: String,
        subtitle: String? = nil,
        color: Color = .vayPrimary
    ) {
        self.icon = icon
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: VayRadius.sm, style: .continuous))

                Text(title)
                    .font(VayFont.caption())
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(VayFont.title(22))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            if let subtitle {
                Text(subtitle)
                    .font(VayFont.caption(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VaySpacing.lg)
        .background(Color.vayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
        .vayShadow(.subtle)
        .scaleEffect(appeared ? 1 : 0.95)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(VayAnimation.springBounce.delay(0.1)) {
                appeared = true
            }
        }
        .vayAccessibilityLabel("\(title): \(value)\(subtitle.map { ", \($0)" } ?? "")")
    }
}

// MARK: - Compact Stat Row

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    init(icon: String, label: String, value: String, color: Color = .vayPrimary) {
        self.icon = icon
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(label)
                .font(VayFont.body(15))
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(VayFont.label(15))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, VaySpacing.xs)
    }
}
