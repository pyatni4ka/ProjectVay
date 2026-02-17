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

        migrator.registerMigration("v3_meal_schedule") { db in
            try db.alter(table: "app_settings") { table in
                table.add(column: "breakfast_minute", .integer).notNull().defaults(to: 8 * 60)
                table.add(column: "lunch_minute", .integer).notNull().defaults(to: 13 * 60)
                table.add(column: "dinner_minute", .integer).notNull().defaults(to: 19 * 60)
            }
        }

        migrator.registerMigration("v4_macro_tracking_preferences") { db in
            try db.alter(table: "app_settings") { table in
                table.add(column: "strict_macro_tracking", .boolean).notNull().defaults(to: true)
                table.add(column: "macro_tolerance_percent", .double).notNull().defaults(to: 25.0)
            }
        }

        migrator.registerMigration("v5_body_metrics_range") { db in
            let currentYear = Calendar.current.component(.year, from: Date())
            try db.alter(table: "app_settings") { table in
                table.add(column: "body_metrics_range_mode", .text).notNull().defaults(to: "lastMonths")
                table.add(column: "body_metrics_range_months", .integer).notNull().defaults(to: 12)
                table.add(column: "body_metrics_range_year", .integer).notNull().defaults(to: currentYear)
            }
        }

        migrator.registerMigration("v6_ai_settings_and_price_index") { db in
            try db.alter(table: "app_settings") { table in
                table.add(column: "ai_personalization_enabled", .boolean).notNull().defaults(to: true)
                table.add(column: "ai_cloud_assist_enabled", .boolean).notNull().defaults(to: true)
                table.add(column: "ai_ru_only_storage", .boolean).notNull().defaults(to: true)
                table.add(column: "ai_data_consent_accepted_at", .datetime)
                table.add(column: "ai_data_collection_mode", .text).notNull().defaults(to: "maximal")
            }

            try db.create(index: "idx_price_entries_date", on: "price_entries", columns: ["date"])
        migrator.registerMigration("v5_batch_purchase_price") { db in
            try db.alter(table: "batches") { table in
                table.add(column: "purchase_price_minor", .integer)
            }
        }

        migrator.registerMigration("v6_event_reason_and_value") { db in
            try db.alter(table: "inventory_events") { table in
                table.add(column: "reason", .text).notNull().defaults(to: "unknown")
                table.add(column: "estimated_value_minor", .integer)
            }
        }

        migrator.registerMigration("v7_settings_extended") { db in
            try db.alter(table: "app_settings") { table in
                table.add(column: "kcal_goal", .double)
                table.add(column: "protein_goal_grams", .double)
                table.add(column: "fat_goal_grams", .double)
                table.add(column: "carbs_goal_grams", .double)
                table.add(column: "weight_goal_kg", .double)
                table.add(column: "preferred_color_scheme", .integer)
                table.add(column: "healthkit_read_enabled", .boolean).notNull().defaults(to: true)
                table.add(column: "healthkit_write_enabled", .boolean).notNull().defaults(to: false)
                table.add(column: "enable_animations", .boolean).notNull().defaults(to: true)
                table.add(column: "macro_goal_source", .text).notNull().defaults(to: "automatic")
                table.add(column: "recipe_service_base_url", .text)
            }
        }

        migrator.registerMigration("v8_budget_month_and_period") { db in
            try db.alter(table: "app_settings") { table in
                table.add(column: "budget_month_minor", .integer)
                table.add(column: "budget_input_period", .text).notNull().defaults(to: "week")
            }

            try db.execute(sql: """
                UPDATE app_settings
                SET
                    budget_week_minor = COALESCE(budget_week_minor, budget_day_minor * 7),
                    budget_month_minor = CAST(
                        ROUND(COALESCE(budget_week_minor, budget_day_minor * 7) * 365.0 / 84.0)
                        AS INTEGER
                    )
                """)
        }

        migrator.registerMigration("v9_diet_and_ui_preferences") { db in
            try db.alter(table: "app_settings") { table in
                table.add(column: "diet_profile", .text).notNull().defaults(to: "medium")
                table.add(column: "haptics_enabled", .boolean).notNull().defaults(to: true)
                table.add(column: "show_health_card_on_home", .boolean).notNull().defaults(to: true)
            }
        }

        migrator.registerMigration("v10_motion_and_goal_mode") { db in
            try db.alter(table: "app_settings") { table in
                table.add(column: "motion_level", .text).notNull().defaults(to: "full")
                table.add(column: "diet_goal_mode", .text).notNull().defaults(to: "lose")
            }

            try db.execute(sql: """
                UPDATE app_settings
                SET motion_level = CASE
                    WHEN enable_animations = 0 THEN 'off'
                    ELSE 'full'
                END
                WHERE motion_level IS NULL OR TRIM(motion_level) = ''
                """)
        }

        return migrator
    }
}
