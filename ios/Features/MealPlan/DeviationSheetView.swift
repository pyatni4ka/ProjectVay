import SwiftUI

/// Sheet shown when user taps "Съел другое / поел вне дома".
/// Collects event type + impact estimate, then triggers plan adaptation.
struct DeviationSheetView: View {
    let context: DeviationContext
    let onConfirm: (String, String) -> Void
    let onDismiss: () -> Void

    @State private var selectedEventType = "ate_out"
    @State private var selectedImpact = "medium"

    private let eventTypes: [(String, String, String)] = [
        ("ate_out", "Поел вне дома", "fork.knife"),
        ("cheat", "Чит-день / срыв", "birthday.cake"),
        ("different_meal", "Съел другое", "cart"),
    ]

    private let impactSizes: [(String, String, String)] = [
        ("small", "Немного", "~300–400 ккал"),
        ("medium", "Среднее", "~600–800 ккал"),
        ("large", "Много", "~1000+ ккал"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VaySpacing.xl) {
                    // Gentle header
                    VStack(alignment: .leading, spacing: VaySpacing.sm) {
                        Text("Всё в порядке")
                            .font(VayFont.heading(18))
                        Text("Скажите, что случилось, и план автоматически подстроится под остаток дня. Без осуждения.")
                            .font(VayFont.body(14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, VaySpacing.lg)

                    // Event type picker
                    VStack(alignment: .leading, spacing: VaySpacing.sm) {
                        Text("Что произошло?")
                            .font(VayFont.label(14))
                            .padding(.horizontal, VaySpacing.lg)

                        VStack(spacing: VaySpacing.sm) {
                            ForEach(eventTypes, id: \.0) { event in
                                eventTypeRow(
                                    id: event.0,
                                    label: event.1,
                                    icon: event.2
                                )
                            }
                        }
                        .padding(.horizontal, VaySpacing.lg)
                    }

                    // Impact size picker
                    VStack(alignment: .leading, spacing: VaySpacing.sm) {
                        Text("Примерно сколько?")
                            .font(VayFont.label(14))
                            .padding(.horizontal, VaySpacing.lg)

                        VStack(spacing: VaySpacing.sm) {
                            ForEach(impactSizes, id: \.0) { impact in
                                impactRow(
                                    id: impact.0,
                                    label: impact.1,
                                    description: impact.2
                                )
                            }
                        }
                        .padding(.horizontal, VaySpacing.lg)
                    }

                    // Confirm button
                    Button {
                        onConfirm(selectedEventType, selectedImpact)
                    } label: {
                        Text("Пересчитать план")
                            .font(VayFont.label(15))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, VaySpacing.md)
                            .background(Color.vayPrimary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
                    }
                    .padding(.horizontal, VaySpacing.lg)

                    // Reassurance note
                    Text("Прошлые дни не изменятся. Перерасчёт только на остаток сегодняшнего дня.")
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, VaySpacing.lg)

                    Color.clear.frame(height: VaySpacing.xl)
                }
                .padding(.top, VaySpacing.md)
            }
            .background(Color.vayBackground)
            .navigationTitle("Съел не по плану")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена", action: onDismiss)
                }
            }
        }
    }

    private func eventTypeRow(id: String, label: String, icon: String) -> some View {
        Button {
            selectedEventType = id
        } label: {
            HStack(spacing: VaySpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(selectedEventType == id ? Color.vayPrimary : .secondary)
                    .frame(width: 28)

                Text(label)
                    .font(VayFont.body(15))
                    .foregroundStyle(.primary)

                Spacer()

                if selectedEventType == id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.vayPrimary)
                }
            }
            .padding(VaySpacing.md)
            .background(selectedEventType == id ? Color.vayPrimaryLight : Color.vayCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous)
                    .stroke(selectedEventType == id ? Color.vayPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func impactRow(id: String, label: String, description: String) -> some View {
        Button {
            selectedImpact = id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(VayFont.label(14))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedImpact == id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.vayPrimary)
                }
            }
            .padding(VaySpacing.md)
            .background(selectedImpact == id ? Color.vayPrimaryLight : Color.vayCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous)
                    .stroke(selectedImpact == id ? Color.vayPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
