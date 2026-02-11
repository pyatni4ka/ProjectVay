import Foundation

protocol InventoryServiceProtocol {
    func findProduct(by barcode: String) async -> Product?
    func upsertProduct(_ product: Product) async
    func addBatch(_ batch: Batch) async
    func productsExpiringSoon(within days: Int) async -> [Batch]
}

actor InventoryService: InventoryServiceProtocol {
    private var productsByBarcode: [String: Product] = [:]
    private var batches: [Batch] = []

    func findProduct(by barcode: String) async -> Product? {
        productsByBarcode[barcode]
    }

    func upsertProduct(_ product: Product) async {
        guard let barcode = product.barcode else { return }
        productsByBarcode[barcode] = product
    }

    func addBatch(_ batch: Batch) async {
        batches.append(batch)
    }

    func productsExpiringSoon(within days: Int = 5) async -> [Batch] {
        let horizon = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return batches.filter { batch in
            guard let expiry = batch.expiryDate else { return false }
            return expiry <= horizon
        }
    }
}
