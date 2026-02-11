import Foundation
import GRDB

enum AppMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "products") { table in
                table.column("id", .text).primaryKey()
                table.column("barcode", .text).unique()
                table.column("name", .text).notNull()
                table.column("brand", .text)
                table.column("category", .text).notNull()
                table.column("image_url", .text)
                table.column("local_image_path", .text)
                table.column("default_unit", .text).notNull()
                table.column("nutrition_json", .text).notNull()
                table.column("disliked", .boolean).notNull().defaults(to: false)
                table.column("may_contain_bones", .boolean).notNull().defaults(to: false)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(index: "idx_products_barcode", on: "products", columns: ["barcode"])

            try db.create(table: "batches") { table in
                table.column("id", .text).primaryKey()
                table.column("product_id", .text).notNull()
                    .references("products", onDelete: .cascade, onUpdate: .cascade)
                table.column("location", .text).notNull()
                table.column("quantity", .double).notNull()
                table.column("unit", .text).notNull()
                table.column("expiry_date", .datetime)
                table.column("is_opened", .boolean).notNull().defaults(to: false)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(index: "idx_batches_expiry_date", on: "batches", columns: ["expiry_date"])
            try db.create(index: "idx_batches_location", on: "batches", columns: ["location"])

            try db.create(table: "price_entries") { table in
                table.column("id", .text).primaryKey()
                table.column("product_id", .text).notNull()
                    .references("products", onDelete: .cascade, onUpdate: .cascade)
                table.column("store", .text).notNull()
                table.column("price_minor", .integer).notNull()
                table.column("currency", .text).notNull()
                table.column("date", .datetime).notNull()
            }

            try db.create(index: "idx_price_entries_product_date", on: "price_entries", columns: ["product_id", "date"])

            try db.create(table: "inventory_events") { table in
                table.column("id", .text).primaryKey()
                table.column("type", .text).notNull()
                table.column("product_id", .text).notNull()
                    .references("products", onDelete: .cascade, onUpdate: .cascade)
                table.column("batch_id", .text)
                    .references("batches", onDelete: .setNull, onUpdate: .cascade)
                table.column("quantity_delta", .double).notNull()
                table.column("timestamp", .datetime).notNull()
                table.column("note", .text)
            }

            try db.create(index: "idx_events_product_timestamp", on: "inventory_events", columns: ["product_id", "timestamp"])

            try db.create(table: "app_settings") { table in
                table.column("id", .integer).primaryKey()
                table.column("quiet_start_minute", .integer).notNull()
                table.column("quiet_end_minute", .integer).notNull()
                table.column("expiry_alerts_days_json", .text).notNull()
                table.column("budget_day_minor", .integer).notNull()
                table.column("budget_week_minor", .integer)
                table.column("stores_json", .text).notNull()
                table.column("disliked_list_json", .text).notNull()
                table.column("avoid_bones", .boolean).notNull().defaults(to: true)
                table.column("onboarding_completed", .boolean).notNull().defaults(to: false)
            }

            try db.execute(sql: "INSERT INTO app_settings (id, quiet_start_minute, quiet_end_minute, expiry_alerts_days_json, budget_day_minor, budget_week_minor, stores_json, disliked_list_json, avoid_bones, onboarding_completed) VALUES (1, 60, 360, '[5,3,1]', 80000, NULL, '[\"pyaterochka\",\"yandexLavka\",\"chizhik\",\"auchan\"]', '[\"кускус\"]', 1, 0)")
        }

        migrator.registerMigration("v2_internal_code_mappings") { db in
            try db.create(table: "internal_code_mappings") { table in
                table.column("code", .text).primaryKey()
                table.column("product_id", .text).notNull()
                    .references("products", onDelete: .cascade, onUpdate: .cascade)
                table.column("parsed_weight_grams", .double)
                table.column("created_at", .datetime).notNull()
            }

            try db.create(index: "idx_internal_code_mappings_product", on: "internal_code_mappings", columns: ["product_id"])
        }

        return migrator
    }
}
