import SwiftUI

struct PredictionsCard: View {
    let predictions: [ProductPrediction]
    let onAddToShoppingList: (ProductPrediction) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Color.vayPrimary)
                Text("Умные предсказания")
                    .font(VayFont.heading(16))
                Spacer()
                Text("AI")
                    .font(VayFont.caption(10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.vayPrimary.opacity(0.15))
                    .clipShape(Capsule())
            }
            
            if predictions.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.vaySuccess)
                    Text("Всё в порядке! Запасов хватит надолго.")
                        .font(VayFont.body(14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, VaySpacing.sm)
            } else {
                ForEach(predictions.prefix(3)) { prediction in
                    predictionRow(prediction)
                }
                
                if predictions.count > 3 {
                    Text("+ ещё \(predictions.count - 3) товаров")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                        .padding(.top, VaySpacing.xs)
                }
            }
        }
        .padding(VaySpacing.lg)
        .background(Color.vayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous))
        .vayShadow(.card)
    }
    
    private func predictionRow(_ prediction: ProductPrediction) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: prediction.urgencyLevel.icon)
                .foregroundStyle(urgencyColor(prediction.urgencyLevel))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(prediction.productName)
                    .font(VayFont.label(14))
                
                Text("Закончится через \(prediction.estimatedDaysUntilEmpty) дн.")
                    .font(VayFont.caption(11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                onAddToShoppingList(prediction)
            } label: {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vayPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, VaySpacing.xs)
    }
    
    private func urgencyColor(_ level: ProductPrediction.UrgencyLevel) -> Color {
        switch level {
        case .critical: return .vayDanger
        case .high: return .vayWarning
        case .medium: return .vayAccent
        case .low: return .vaySuccess
        }
    }
}
