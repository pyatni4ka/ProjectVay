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
    func removeBatch(id: UUID) async throws

    func listProducts(location: InventoryLocation?, search: String?) async throws -> [Product]
    func listBatches(productId: UUID?) async throws -> [Batch]

    func savePriceEntry(_ entry: PriceEntry) async throws
    func listPriceHistory(productId: UUID) async throws -> [PriceEntry]

    func recordEvent(_ event: InventoryEvent) async throws
    func expiringBatches(horizonDays: Int) async throws -> [Batch]
    func bindInternalCode(_ code: String, productId: UUID, parsedWeightGrams: Double?) async throws
    func internalCodeMapping(for code: String) async throws -> InternalCodeMapping?
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
        return stored
    }

    func updateProduct(_ product: Product) async throws -> Product {
        var stored = product
        stored.updatedAt = Date()
        try repository.upsertProduct(stored)
        return stored
    }

    func deleteProduct(id: UUID) async throws {
        let batches = try repository.listBatches(productId: id)
        for batch in batches {
            try await notificationScheduler.cancelExpiryNotifications(batchId: batch.id)
        }
        try repository.deleteProduct(id: id)
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
            note: "Добавление партии"
        )
        try repository.saveInventoryEvent(event)

        let settings = try settingsRepository.loadSettings()
        try await notificationScheduler.scheduleExpiryNotifications(for: stored, product: product, settings: settings)
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
            note: "Изменение партии"
        )
        try repository.saveInventoryEvent(event)

        let settings = try settingsRepository.loadSettings()
        try await notificationScheduler.rescheduleExpiryNotifications(for: stored, product: product, settings: settings)

        return stored
    }

    func removeBatch(id: UUID) async throws {
        let allBatches = try repository.listBatches(productId: nil)
        guard let batch = allBatches.first(where: { $0.id == id }) else { return }

        let event = InventoryEvent(
            type: .remove,
            productId: batch.productId,
            batchId: batch.id,
            quantityDelta: -batch.quantity,
            note: "Удаление партии"
        )
        try repository.saveInventoryEvent(event)

        try await notificationScheduler.cancelExpiryNotifications(batchId: id)
        try repository.removeBatch(id: id)
    }

    func listProducts(location: InventoryLocation?, search: String?) async throws -> [Product] {
        try repository.listProducts(location: location, search: search)
    }

    func listBatches(productId: UUID?) async throws -> [Batch] {
        try repository.listBatches(productId: productId)
    }

    func savePriceEntry(_ entry: PriceEntry) async throws {
        try repository.savePriceEntry(entry)
    }

    func listPriceHistory(productId: UUID) async throws -> [PriceEntry] {
        try repository.listPriceHistory(productId: productId)
    }

    func recordEvent(_ event: InventoryEvent) async throws {
        try repository.saveInventoryEvent(event)
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
}
