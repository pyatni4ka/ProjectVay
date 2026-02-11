import Foundation
import GRDB

protocol InventoryRepositoryProtocol: Sendable {
    func findProduct(byBarcode barcode: String) throws -> Product?
    func findProduct(byInternalCode code: String) throws -> Product?
    func fetchProduct(id: UUID) throws -> Product?
    func upsertProduct(_ product: Product) throws
    func deleteProduct(id: UUID) throws
    func listProducts(location: InventoryLocation?, search: String?) throws -> [Product]

    func addBatch(_ batch: Batch) throws
    func updateBatch(_ batch: Batch) throws
    func removeBatch(id: UUID) throws
    func listBatches(productId: UUID?) throws -> [Batch]
    func expiringBatches(until date: Date) throws -> [Batch]

    func savePriceEntry(_ entry: PriceEntry) throws
    func listPriceHistory(productId: UUID) throws -> [PriceEntry]

    func saveInventoryEvent(_ event: InventoryEvent) throws
    func upsertInternalCodeMapping(_ mapping: InternalCodeMapping) throws
    func fetchInternalCodeMapping(code: String) throws -> InternalCodeMapping?
}

final class InventoryRepository: InventoryRepositoryProtocol {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func findProduct(byBarcode barcode: String) throws -> Product? {
        try dbQueue.read { db in
            guard let record = try ProductRecord
                .filter(sql: "barcode = ?", arguments: [barcode])
                .fetchOne(db)
            else {
                return nil
            }
            return try record.asDomain()
        }
    }

    func findProduct(byInternalCode code: String) throws -> Product? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT p.*
                FROM products p
                JOIN internal_code_mappings m ON m.product_id = p.id
                WHERE m.code = ?
                LIMIT 1
                """,
                arguments: [code]
            ) else {
                return nil
            }

            let record = try ProductRecord(row: row)
            return try record.asDomain()
        }
    }

    func fetchProduct(id: UUID) throws -> Product? {
        try dbQueue.read { db in
            guard let record = try ProductRecord.fetchOne(db, key: id.uuidString) else {
                return nil
            }
            return try record.asDomain()
        }
    }

    func upsertProduct(_ product: Product) throws {
        try dbQueue.write { db in
            var record = try ProductRecord(product: product)
            try record.save(db)
        }
    }

    func deleteProduct(id: UUID) throws {
        try dbQueue.write { db in
            _ = try ProductRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func listProducts(location: InventoryLocation?, search: String?) throws -> [Product] {
        try dbQueue.read { db in
            let productRecords = try ProductRecord.fetchAll(db)
            let batchRecords = try BatchRecord.fetchAll(db)

            let locationProductIDs: Set<String>
            if let location {
                locationProductIDs = Set(batchRecords.filter { $0.location == location.rawValue }.map(\.productID))
            } else {
                locationProductIDs = Set(productRecords.map(\.id))
            }

            let normalizedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasSearch = !normalizedSearch.isEmpty

            let filtered = productRecords.filter { record in
                guard locationProductIDs.contains(record.id) else { return false }
                guard hasSearch else { return true }

                return [
                    record.name,
                    record.brand ?? "",
                    record.barcode ?? ""
                ].contains { value in
                    value.localizedCaseInsensitiveContains(normalizedSearch)
                }
            }

            return try filtered
                .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                .map { try $0.asDomain() }
        }
    }

    func addBatch(_ batch: Batch) throws {
        try dbQueue.write { db in
            var record = BatchRecord(batch: batch)
            try record.insert(db)
        }
    }

    func updateBatch(_ batch: Batch) throws {
        try dbQueue.write { db in
            let record = BatchRecord(batch: batch)
            try record.update(db)
        }
    }

    func removeBatch(id: UUID) throws {
        try dbQueue.write { db in
            _ = try BatchRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func listBatches(productId: UUID?) throws -> [Batch] {
        try dbQueue.read { db in
            let records: [BatchRecord]
            if let productId {
                records = try BatchRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM batches WHERE product_id = ? ORDER BY expiry_date IS NULL, expiry_date ASC, created_at DESC",
                    arguments: [productId.uuidString]
                )
            } else {
                records = try BatchRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM batches ORDER BY expiry_date IS NULL, expiry_date ASC, created_at DESC"
                )
            }
            return records.map { $0.asDomain() }
        }
    }

    func expiringBatches(until date: Date) throws -> [Batch] {
        try dbQueue.read { db in
            let records = try BatchRecord.fetchAll(
                db,
                sql: "SELECT * FROM batches WHERE expiry_date IS NOT NULL AND expiry_date <= ? ORDER BY expiry_date ASC",
                arguments: [date]
            )
            return records.map { $0.asDomain() }
        }
    }

    func savePriceEntry(_ entry: PriceEntry) throws {
        try dbQueue.write { db in
            var record = PriceEntryRecord(priceEntry: entry)
            try record.save(db)
        }
    }

    func listPriceHistory(productId: UUID) throws -> [PriceEntry] {
        try dbQueue.read { db in
            let records = try PriceEntryRecord.fetchAll(
                db,
                sql: "SELECT * FROM price_entries WHERE product_id = ? ORDER BY date DESC",
                arguments: [productId.uuidString]
            )
            return records.map { $0.asDomain() }
        }
    }

    func saveInventoryEvent(_ event: InventoryEvent) throws {
        try dbQueue.write { db in
            var record = InventoryEventRecord(event: event)
            try record.save(db)
        }
    }

    func upsertInternalCodeMapping(_ mapping: InternalCodeMapping) throws {
        try dbQueue.write { db in
            var record = InternalCodeMappingRecord(mapping: mapping)
            try record.save(db)
        }
    }

    func fetchInternalCodeMapping(code: String) throws -> InternalCodeMapping? {
        try dbQueue.read { db in
            try InternalCodeMappingRecord.fetchOne(db, key: code)?.asDomain()
        }
    }
}
