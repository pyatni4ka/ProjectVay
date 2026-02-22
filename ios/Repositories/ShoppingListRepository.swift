import Foundation
import GRDB

protocol ShoppingListRepositoryProtocol: Sendable {
    func listItems() throws -> [ShoppingListItem]
    func addItem(_ item: ShoppingListItem) throws
    func updateItem(_ item: ShoppingListItem) throws
    func deleteItem(id: UUID) throws
    func clearCompletedItems() throws
    func deleteAllItems() throws
}

final class ShoppingListRepository: ShoppingListRepositoryProtocol {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func listItems() throws -> [ShoppingListItem] {
        try dbQueue.read { db in
            let records = try ShoppingListItemRecord.fetchAll(
                db,
                sql: "SELECT * FROM shopping_list_items ORDER BY is_completed ASC, created_at DESC"
            )
            return try records.map { try $0.asDomain() }
        }
    }

    func addItem(_ item: ShoppingListItem) throws {
        try dbQueue.write { db in
            var record = try ShoppingListItemRecord(item: item)
            try record.insert(db)
        }
    }

    func updateItem(_ item: ShoppingListItem) throws {
        try dbQueue.write { db in
            let record = try ShoppingListItemRecord(item: item)
            try record.update(db)
        }
    }

    func deleteItem(id: UUID) throws {
        try dbQueue.write { db in
            _ = try ShoppingListItemRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func clearCompletedItems() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM shopping_list_items WHERE is_completed = ?", arguments: [true])
        }
    }

    func deleteAllItems() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM shopping_list_items")
        }
    }
}
