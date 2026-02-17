import Foundation
import GRDB

struct AppSettingsRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "app_settings"

    var id: Int64
    var quietStartMinute: Int
    var quietEndMinute: Int
    var expiryAlertsDaysJSON: String
    var budgetDayMinor: Int64
    var budgetWeekMinor: Int64?
    var storesJSON: String
    var dislikedListJSON: String
    var avoidBones: Bool
    var breakfastMinute: Int
    var lunchMinute: Int
    var dinnerMinute: Int
    var strictMacroTracking: Bool
    var macroTolerancePercent: Double
    var bodyMetricsRangeMode: String
    var bodyMetricsRangeMonths: Int
    var bodyMetricsRangeYear: Int
    var aiPersonalizationEnabled: Bool
    var aiCloudAssistEnabled: Bool
    var aiRuOnlyStorage: Bool
    var aiDataConsentAcceptedAt: Date?
    var aiDataCollectionMode: String
    var onboardingCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case quietStartMinute = "quiet_start_minute"
        case quietEndMinute = "quiet_end_minute"
        case expiryAlertsDaysJSON = "expiry_alerts_days_json"
        case budgetDayMinor = "budget_day_minor"
        case budgetWeekMinor = "budget_week_minor"
        case storesJSON = "stores_json"
        case dislikedListJSON = "disliked_list_json"
        case avoidBones = "avoid_bones"
        case breakfastMinute = "breakfast_minute"
        case lunchMinute = "lunch_minute"
        case dinnerMinute = "dinner_minute"
        case strictMacroTracking = "strict_macro_tracking"
        case macroTolerancePercent = "macro_tolerance_percent"
        case bodyMetricsRangeMode = "body_metrics_range_mode"
        case bodyMetricsRangeMonths = "body_metrics_range_months"
        case bodyMetricsRangeYear = "body_metrics_range_year"
        case aiPersonalizationEnabled = "ai_personalization_enabled"
        case aiCloudAssistEnabled = "ai_cloud_assist_enabled"
        case aiRuOnlyStorage = "ai_ru_only_storage"
        case aiDataConsentAcceptedAt = "ai_data_consent_accepted_at"
        case aiDataCollectionMode = "ai_data_collection_mode"
        case onboardingCompleted = "onboarding_completed"
    }
}

extension AppSettingsRecord {
    static let singletonID: Int64 = 1

    init(settings: AppSettings, onboardingCompleted: Bool) throws {
        let normalized = settings.normalized()
        id = Self.singletonID
        quietStartMinute = normalized.quietStartMinute
        quietEndMinute = normalized.quietEndMinute
        expiryAlertsDaysJSON = try Self.encodeJSON(normalized.expiryAlertsDays)
        budgetDayMinor = normalized.budgetDay.asMinorUnits
        budgetWeekMinor = normalized.budgetWeek?.asMinorUnits
        storesJSON = try Self.encodeJSON(normalized.stores.map(\.rawValue))
        dislikedListJSON = try Self.encodeJSON(normalized.dislikedList)
        avoidBones = normalized.avoidBones
        breakfastMinute = normalized.mealSchedule.breakfastMinute
        lunchMinute = normalized.mealSchedule.lunchMinute
        dinnerMinute = normalized.mealSchedule.dinnerMinute
        strictMacroTracking = normalized.strictMacroTracking
        macroTolerancePercent = normalized.macroTolerancePercent
        bodyMetricsRangeMode = normalized.bodyMetricsRangeMode.rawValue
        bodyMetricsRangeMonths = normalized.bodyMetricsRangeMonths
        bodyMetricsRangeYear = normalized.bodyMetricsRangeYear
        aiPersonalizationEnabled = normalized.aiPersonalizationEnabled
        aiCloudAssistEnabled = normalized.aiCloudAssistEnabled
        aiRuOnlyStorage = normalized.aiRuOnlyStorage
        aiDataConsentAcceptedAt = normalized.aiDataConsentAcceptedAt
        aiDataCollectionMode = normalized.aiDataCollectionMode.rawValue
        self.onboardingCompleted = onboardingCompleted
    }

    func asDomainSettings() -> AppSettings {
        let parsedDays = (try? Self.decodeJSON([Int].self, from: expiryAlertsDaysJSON)) ?? AppSettings.default.expiryAlertsDays
        let parsedStoresRaw = (try? Self.decodeJSON([String].self, from: storesJSON)) ?? AppSettings.default.stores.map(\.rawValue)
        let parsedStores = parsedStoresRaw.compactMap(Store.init(rawValue:))
        let parsedDisliked = (try? Self.decodeJSON([String].self, from: dislikedListJSON)) ?? AppSettings.default.dislikedList
        let parsedRangeMode = AppSettings.BodyMetricsRangeMode(rawValue: bodyMetricsRangeMode) ?? .lastMonths
        let parsedDataCollectionMode = AppSettings.AIDataCollectionMode(rawValue: aiDataCollectionMode) ?? .maximal

        return AppSettings(
            quietStartMinute: quietStartMinute,
            quietEndMinute: quietEndMinute,
            expiryAlertsDays: parsedDays,
            budgetDay: Decimal.fromMinorUnits(budgetDayMinor),
            budgetWeek: budgetWeekMinor.map(Decimal.fromMinorUnits),
            stores: parsedStores,
            dislikedList: parsedDisliked,
            avoidBones: avoidBones,
            mealSchedule: .init(
                breakfastMinute: breakfastMinute,
                lunchMinute: lunchMinute,
                dinnerMinute: dinnerMinute
            ),
            strictMacroTracking: strictMacroTracking,
            macroTolerancePercent: macroTolerancePercent,
            bodyMetricsRangeMode: parsedRangeMode,
            bodyMetricsRangeMonths: bodyMetricsRangeMonths,
            bodyMetricsRangeYear: bodyMetricsRangeYear,
            aiPersonalizationEnabled: aiPersonalizationEnabled,
            aiCloudAssistEnabled: aiCloudAssistEnabled,
            aiRuOnlyStorage: aiRuOnlyStorage,
            aiDataConsentAcceptedAt: aiDataConsentAcceptedAt,
            aiDataCollectionMode: parsedDataCollectionMode
        ).normalized()
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from value: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(value.utf8))
    }
}
