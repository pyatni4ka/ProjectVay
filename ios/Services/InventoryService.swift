import Foundation

enum InventoryServiceError: Error {
    case productNotFound
}

protocol InventoryServiceProtocol {
    func findProduct(by barcode: String) async throws -> Product?
    func findProduct(byInternalCode code: String) async throws -> Product?
    func createProduct(_ product: Product) async throws -> Product
    func updateProduct(_ product: Product) async throws -> Product
    func deleteProduct(id: UUID) async throws

    func addBatch(_ batch: Batch) async throws -> Batch
    func updateBatch(_ batch: Batch) async throws -> Batch
    func removeBatch(id: UUID, quantity: Double?, intent: InventoryRemovalIntent, note: String?) async throws

    func listProducts(location: InventoryLocation?, search: String?) async throws -> [Product]
    func listBatches(productId: UUID?) async throws -> [Batch]

    func savePriceEntry(_ entry: PriceEntry) async throws
    func listPriceHistory(productId: UUID) async throws -> [PriceEntry]
    func listPriceHistory(productId: UUID?) async throws -> [PriceEntry]

    func recordEvent(_ event: InventoryEvent) async throws
    func listEvents(productId: UUID?) async throws -> [InventoryEvent]
    func expiringBatches(horizonDays: Int) async throws -> [Batch]
    func bindInternalCode(_ code: String, productId: UUID, parsedWeightGrams: Double?) async throws
    func internalCodeMapping(for code: String) async throws -> InternalCodeMapping?
}

extension InventoryServiceProtocol {
    func listPriceHistory(productId: UUID?) async throws -> [PriceEntry] {
        guard let productId else { return [] }
        return try await listPriceHistory(productId: productId)
    }
}

final class InventoryService: InventoryServiceProtocol {
    private let repository: InventoryRepositoryProtocol
    private let settingsRepository: SettingsRepositoryProtocol
    private let notificationScheduler: any NotificationScheduling

    init(
        repository: InventoryRepositoryProtocol,
        settingsRepository: SettingsRepositoryProtocol,
        notificationScheduler: any NotificationScheduling
    ) {
        self.repository = repository
        self.settingsRepository = settingsRepository
        self.notificationScheduler = notificationScheduler
    }

    func findProduct(by barcode: String) async throws -> Product? {
        try repository.findProduct(byBarcode: barcode)
    }

    func findProduct(byInternalCode code: String) async throws -> Product? {
        try repository.findProduct(byInternalCode: code)
    }

    func createProduct(_ product: Product) async throws -> Product {
        if let barcode = product.barcode, let existing = try repository.findProduct(byBarcode: barcode) {
            return existing
        }

        let now = Date()
        var stored = product
        stored.createdAt = now
        stored.updatedAt = now
        try repository.upsertProduct(stored)
        notifyInventoryChanged()
        return stored
    }

    func updateProduct(_ product: Product) async throws -> Product {
        var stored = product
        stored.updatedAt = Date()
        try repository.upsertProduct(stored)
        notifyInventoryChanged()
        return stored
    }

    func deleteProduct(id: UUID) async throws {
        let batches = try repository.listBatches(productId: id)
        for batch in batches {
            try await notificationScheduler.cancelExpiryNotifications(batchId: batch.id)
        }
        try repository.deleteProduct(id: id)
        notifyInventoryChanged()
    }

    func addBatch(_ batch: Batch) async throws -> Batch {
        guard let product = try repository.fetchProduct(id: batch.productId) else {
            throw InventoryServiceError.productNotFound
        }

        let now = Date()
        var stored = batch
        stored.createdAt = now
        stored.updatedAt = now

        try repository.addBatch(stored)

        let event = InventoryEvent(
            type: .add,
            productId: stored.productId,
            batchId: stored.id,
            quantityDelta: stored.quantity,
            reason: .unknown,
            note: "Добавление партии"
        )
        try repository.saveInventoryEvent(event)

        let settings = try settingsRepository.loadSettings()
        try await notificationScheduler.scheduleExpiryNotifications(for: stored, product: product, settings: settings)
        notifyInventoryChanged()
        return stored
    }

    func updateBatch(_ batch: Batch) async throws -> Batch {
        guard let product = try repository.fetchProduct(id: batch.productId) else {
            throw InventoryServiceError.productNotFound
        }

        var stored = batch
        stored.updatedAt = Date()

        try repository.updateBatch(stored)

        let event = InventoryEvent(
            type: .adjust,
            productId: stored.productId,
            batchId: stored.id,
            quantityDelta: stored.quantity,
            reason: .unknown,
            note: "Изменение партии"
        )
        try repository.saveInventoryEvent(event)

        let settings = try settingsRepository.loadSettings()
        try await notificationScheduler.rescheduleExpiryNotifications(for: stored, product: product, settings: settings)

        notifyInventoryChanged()
        return stored
    }

    func removeBatch(id: UUID, quantity: Double?, intent: InventoryRemovalIntent, note: String?) async throws {
        let allBatches = try repository.listBatches(productId: nil)
        guard var batch = allBatches.first(where: { $0.id == id }) else { return }

        let quantityToRemove = resolvedRemovalQuantity(requestedQuantity: quantity, availableQuantity: batch.quantity)
        guard quantityToRemove > 0 else { return }

        let reason = eventReason(for: batch, intent: intent)
        let estimatedValueMinor = try estimateRemovedValueMinor(batch: batch, quantityToRemove: quantityToRemove)
        let event = InventoryEvent(
            type: .remove,
            productId: batch.productId,
            batchId: batch.id,
            quantityDelta: -quantityToRemove,
            reason: reason,
            estimatedValueMinor: estimatedValueMinor,
            note: note ?? defaultNote(for: reason)
        )
        try repository.saveInventoryEvent(event)

        if quantityToRemove >= batch.quantity - 0.000_001 {
            try await notificationScheduler.cancelExpiryNotifications(batchId: id)
            try repository.removeBatch(id: id)
            notifyInventoryChanged()
            return
        }

        let originalQuantity = batch.quantity
        batch.quantity = max(0, originalQuantity - quantityToRemove)
        batch.purchasePriceMinor = updatedPurchasePriceMinor(
            currentMinor: batch.purchasePriceMinor,
            originalQuantity: originalQuantity,
            newQuantity: batch.quantity
        )
        batch.updatedAt = Date()
        try repository.updateBatch(batch)

        if let product = try repository.fetchProduct(id: batch.productId), batch.expiryDate != nil {
            let settings = try settingsRepository.loadSettings()
            try await notificationScheduler.rescheduleExpiryNotifications(for: batch, product: product, settings: settings)
        }
        notifyInventoryChanged()
    }

    func listProducts(location: InventoryLocation?, search: String?) async throws -> [Product] {
        try repository.listProducts(location: location, search: search)
    }

    func listBatches(productId: UUID?) async throws -> [Batch] {
        try repository.listBatches(productId: productId)
    }

    func savePriceEntry(_ entry: PriceEntry) async throws {
        try repository.savePriceEntry(entry)
        notifyInventoryChanged()
        await MainActor.run {
            GamificationService.shared.trackPriceEntrySaved()
        }
    }

    func listPriceHistory(productId: UUID) async throws -> [PriceEntry] {
        try repository.listPriceHistory(productId: productId)
    }

    func listPriceHistory(productId: UUID?) async throws -> [PriceEntry] {
        try repository.listPriceHistory(productId: productId)
    }

    func recordEvent(_ event: InventoryEvent) async throws {
        try repository.saveInventoryEvent(event)
        notifyInventoryChanged()
    }

    func listEvents(productId: UUID?) async throws -> [InventoryEvent] {
        try repository.listInventoryEvents(productId: productId)
    }

    func expiringBatches(horizonDays: Int) async throws -> [Batch] {
        let safeDays = max(1, min(horizonDays, 90))
        let horizonDate = Calendar.current.date(byAdding: .day, value: safeDays, to: Date()) ?? Date()
        return try repository.expiringBatches(until: horizonDate)
    }

    func bindInternalCode(_ code: String, productId: UUID, parsedWeightGrams: Double?) async throws {
        let mapping = InternalCodeMapping(
            code: code,
            productId: productId,
            parsedWeightGrams: parsedWeightGrams,
            createdAt: Date()
        )
        try repository.upsertInternalCodeMapping(mapping)
    }

    func internalCodeMapping(for code: String) async throws -> InternalCodeMapping? {
        try repository.fetchInternalCodeMapping(code: code)
    }

    private func resolvedRemovalQuantity(requestedQuantity: Double?, availableQuantity: Double) -> Double {
        guard let requestedQuantity else { return max(0, availableQuantity) }
        return min(max(0, requestedQuantity), max(0, availableQuantity))
    }

    private func eventReason(for batch: Batch, intent: InventoryRemovalIntent) -> InventoryEventReason {
        if intent == .consumed {
            return .consumed
        }

        if let expiryDate = batch.expiryDate, expiryDate < Date() {
            return .expired
        }

        return .writeOff
    }

    private func defaultNote(for reason: InventoryEventReason) -> String {
        switch reason {
        case .consumed:
            return "Съедено"
        case .expired:
            return "Просрочено"
        case .writeOff:
            return "Списано"
        case .unknown:
            return "Удаление партии"
        }
    }

    private func estimateRemovedValueMinor(batch: Batch, quantityToRemove: Double) throws -> Int64? {
        let baseQuantity = max(0.000_001, batch.quantity)

        if let purchasePriceMinor = batch.purchasePriceMinor, purchasePriceMinor > 0 {
            let ratio = min(1, max(0, quantityToRemove / baseQuantity))
            return proportionalMinor(totalMinor: purchasePriceMinor, ratio: ratio)
        }

        let history = try repository.listPriceHistory(productId: batch.productId)
        guard let latestMinor = history.first?.price.asMinorUnits, latestMinor > 0 else {
            return nil
        }

        if batch.unit == .pcs {
            return Int64((Double(latestMinor) * quantityToRemove).rounded())
        }

        let ratio = min(1, max(0, quantityToRemove / baseQuantity))
        return proportionalMinor(totalMinor: latestMinor, ratio: ratio)
    }

    private func updatedPurchasePriceMinor(currentMinor: Int64?, originalQuantity: Double, newQuantity: Double) -> Int64? {
        guard let currentMinor, currentMinor > 0, originalQuantity > 0 else {
            return currentMinor
        }

        let ratio = min(1, max(0, newQuantity / originalQuantity))
        let updated = proportionalMinor(totalMinor: currentMinor, ratio: ratio)
        return updated > 0 ? updated : nil
    }

    private func notifyInventoryChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .inventoryDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .inventoryDidChange, object: nil)
            }
        }
    }

    private func proportionalMinor(totalMinor: Int64, ratio: Double) -> Int64 {
        Int64((Double(totalMinor) * ratio).rounded())
    }
}
