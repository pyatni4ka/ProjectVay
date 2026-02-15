import XCTest
import GRDB
@testable import InventoryCore

final class DatabaseMigrationTests: XCTestCase {
    func testMigrationsCreateExpectedTablesAndIndexes() throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()

        try dbQueue.read { db in
            let tableNames = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )

            XCTAssertTrue(tableNames.contains("products"))
            XCTAssertTrue(tableNames.contains("batches"))
            XCTAssertTrue(tableNames.contains("price_entries"))
            XCTAssertTrue(tableNames.contains("inventory_events"))
            XCTAssertTrue(tableNames.contains("app_settings"))
            XCTAssertTrue(tableNames.contains("internal_code_mappings"))

            let indexNames = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='index' ORDER BY name"
            )

            XCTAssertTrue(indexNames.contains("idx_products_barcode"))
            XCTAssertTrue(indexNames.contains("idx_batches_expiry_date"))
            XCTAssertTrue(indexNames.contains("idx_batches_location"))
            XCTAssertTrue(indexNames.contains("idx_price_entries_product_date"))
            XCTAssertTrue(indexNames.contains("idx_price_entries_date"))
            XCTAssertTrue(indexNames.contains("idx_events_product_timestamp"))
            XCTAssertTrue(indexNames.contains("idx_internal_code_mappings_product"))

            let appSettingsColumns = try String.fetchAll(
                db,
                sql: "SELECT name FROM pragma_table_info('app_settings')"
            )
            XCTAssertTrue(appSettingsColumns.contains("breakfast_minute"))
            XCTAssertTrue(appSettingsColumns.contains("lunch_minute"))
            XCTAssertTrue(appSettingsColumns.contains("dinner_minute"))
            XCTAssertTrue(appSettingsColumns.contains("strict_macro_tracking"))
            XCTAssertTrue(appSettingsColumns.contains("macro_tolerance_percent"))            XCTAssertTrue(appSettingsColumns.contains("body_metrics_range_mode"))
            XCTAssertTrue(appSettingsColumns.contains("body_metrics_range_months"))
            XCTAssertTrue(appSettingsColumns.contains("body_metrics_range_year"))
            XCTAssertTrue(appSettingsColumns.contains("ai_personalization_enabled"))
            XCTAssertTrue(appSettingsColumns.contains("ai_cloud_assist_enabled"))
            XCTAssertTrue(appSettingsColumns.contains("ai_ru_only_storage"))
            XCTAssertTrue(appSettingsColumns.contains("ai_data_consent_accepted_at"))
            XCTAssertTrue(appSettingsColumns.contains("ai_data_collection_mode"))

            let batchColumns = try String.fetchAll(
                db,
                sql: "SELECT name FROM pragma_table_info('batches')"
            )
            XCTAssertTrue(batchColumns.contains("purchase_price_minor"))

            let eventColumns = try String.fetchAll(
                db,
                sql: "SELECT name FROM pragma_table_info('inventory_events')"
            )
            XCTAssertTrue(eventColumns.contains("reason"))
            XCTAssertTrue(eventColumns.contains("estimated_value_minor"))
        }
    }

    func testDefaultSettingsSeeded() throws {
        let dbQueue = try AppDatabase.makeInMemoryQueue()
        let repository = SettingsRepository(dbQueue: dbQueue)

        let settings = try repository.loadSettings()
        XCTAssertEqual(settings.expiryAlertsDays, [5, 3, 1])
        XCTAssertEqual(settings.stores, [.pyaterochka, .yandexLavka, .chizhik, .auchan])
        XCTAssertEqual(settings.mealSchedule, .default)
        XCTAssertTrue(settings.strictMacroTracking)
        XCTAssertEqual(settings.macroTolerancePercent, 25)
        XCTAssertEqual(settings.bodyMetricsRangeMode, .lastMonths)
        XCTAssertEqual(settings.bodyMetricsRangeMonths, 12)
        XCTAssertTrue(settings.aiPersonalizationEnabled)
        XCTAssertTrue(settings.aiCloudAssistEnabled)
        XCTAssertTrue(settings.aiRuOnlyStorage)
        XCTAssertEqual(settings.aiDataCollectionMode, .maximal)
    }
}
