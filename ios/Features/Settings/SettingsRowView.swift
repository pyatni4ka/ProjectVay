import SwiftUI

/// Reusable settings-list row: coloured SF Symbol icon + title + optional subtitle + trailing content.
struct SettingsRowView<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(VayFont.label(13))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VayFont.body(15))

                if let subtitle {
                    Text(subtitle)
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            trailing()
        }
    }
}

extension SettingsRowView where Trailing == EmptyView {
    init(icon: String, color: Color, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.color = color
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}
