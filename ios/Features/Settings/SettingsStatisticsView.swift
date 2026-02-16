import SwiftUI

struct SettingsStatisticsView: View {
    let inventoryService: any InventoryServiceProtocol

    @State private var products: [Product] = []
    @State private var batches: [Batch] = []
    @State private var events: [InventoryEvent] = []
    @State private var isLoading = true
    @State private var hasFallbackData = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack(spacing: VaySpacing.sm) {
                        ProgressView()
                        Text("Считаем статистику...")
                            .font(VayFont.body(14))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                statRow(icon: "cube.box.fill", color: .vayPrimary, title: "Продукты", value: "\(products.count)")
                statRow(icon: "shippingbox.fill", color: .vayInfo, title: "Партии", value: "\(batches.count)")
                statRow(icon: "snowflake", color: .vaySecondary, title: "Морозилка", value: "\(freezerBatchesCount)")
                statRow(icon: "clock.badge.exclamationmark", color: .vayWarning, title: "Истекает (3 дня)", value: "\(expiringSoonCount)")
            } header: {
                sectionHeader(icon: "square.stack.3d.up.fill", title: "Запасы")
            }

            Section {
                statRow(icon: "fork.knife.circle.fill", color: .vaySuccess, title: "Съедено", value: "\(weeklyConsumedCount)")
                statRow(icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", color: .vayDanger, title: "Просрочено", value: "\(weeklyExpiredCount)")
                statRow(icon: "minus.circle.fill", color: .vayWarning, title: "Списано", value: "\(weeklyWriteOffCount)")
            } header: {
                sectionHeader(icon: "calendar", title: "Операции за 7 дней")
            }

            if hasFallbackData {
                Section {
                    Text("Часть данных недоступна. Показаны безопасные значения по умолчанию.")
                        .font(VayFont.caption(12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: VayLayout.tabBarOverlayInset)
        }
        .navigationTitle("Статистика")
        .task {
            await loadStatistics()
        }
        .refreshable {
            await loadStatistics()
        }
    }

    private var freezerBatchesCount: Int {
        batches.filter { $0.location == .freezer }.count
    }

    private var expiringSoonCount: Int {
        batches.filter { batch in
            guard let expiry = batch.expiryDate else { return false }
            return expiry.daysUntilExpiry <= 3
        }.count
    }

    private var weeklyEvents: [InventoryEvent] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        return events.filter { $0.type == .remove && $0.timestamp >= weekAgo }
    }

    private var weeklyConsumedCount: Int {
        weeklyEvents.filter { $0.reason == .consumed }.count
    }

    private var weeklyExpiredCount: Int {
        weeklyEvents.filter { $0.reason == .expired }.count
    }

    private var weeklyWriteOffCount: Int {
        weeklyEvents.filter { $0.reason == .writeOff }.count
    }

    private func statRow(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(title)
                .font(VayFont.body(15))

            Spacer()

            Text(value)
                .font(VayFont.label(14))
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(title)
        }
        .font(VayFont.caption(12))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    private func loadStatistics() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let loadedProducts = inventoryService.listProducts(location: nil, search: nil)
            async let loadedBatches = inventoryService.listBatches(productId: nil)
            async let loadedEvents = inventoryService.listEvents(productId: nil)

            products = try await loadedProducts
            batches = try await loadedBatches
            events = try await loadedEvents
            hasFallbackData = false
        } catch {
            products = []
            batches = []
            events = []
            hasFallbackData = true
        }
    }
}
