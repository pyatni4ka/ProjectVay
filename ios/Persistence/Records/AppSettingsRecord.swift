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
    var budgetMonthMinor: Int64?
    var budgetInputPeriod: String
    var storesJSON: String
    var dislikedListJSON: String
    var avoidBones: Bool
    var breakfastMinute: Int
    var lunchMinute: Int
    var dinnerMinute: Int
    var strictMacroTracking: Bool
    var macroTolerancePercent: Double
    var macroGoalSource: String
    var kcalGoal: Double?
    var proteinGoalGrams: Double?
    var fatGoalGrams: Double?
    var carbsGoalGrams: Double?
    var weightGoalKg: Double?
    var preferredColorScheme: Int?
    var healthKitReadEnabled: Bool
    var healthKitWriteEnabled: Bool
    var enableAnimations: Bool
    var hapticsEnabled: Bool
    var showHealthCardOnHome: Bool
    var dietProfile: String
    var recipeServiceBaseURL: String?
    var onboardingCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case quietStartMinute = "quiet_start_minute"
        case quietEndMinute = "quiet_end_minute"
        case expiryAlertsDaysJSON = "expiry_alerts_days_json"
        case budgetDayMinor = "budget_day_minor"
        case budgetWeekMinor = "budget_week_minor"
        case budgetMonthMinor = "budget_month_minor"
        case budgetInputPeriod = "budget_input_period"
        case storesJSON = "stores_json"
        case dislikedListJSON = "disliked_list_json"
        case avoidBones = "avoid_bones"
        case breakfastMinute = "breakfast_minute"
        case lunchMinute = "lunch_minute"
        case dinnerMinute = "dinner_minute"
        case strictMacroTracking = "strict_macro_tracking"
        case macroTolerancePercent = "macro_tolerance_percent"
        case macroGoalSource = "macro_goal_source"
        case kcalGoal = "kcal_goal"
        case proteinGoalGrams = "protein_goal_grams"
        case fatGoalGrams = "fat_goal_grams"
        case carbsGoalGrams = "carbs_goal_grams"
        case weightGoalKg = "weight_goal_kg"
        case preferredColorScheme = "preferred_color_scheme"
        case healthKitReadEnabled = "healthkit_read_enabled"
        case healthKitWriteEnabled = "healthkit_write_enabled"
        case enableAnimations = "enable_animations"
        case hapticsEnabled = "haptics_enabled"
        case showHealthCardOnHome = "show_health_card_on_home"
        case dietProfile = "diet_profile"
        case recipeServiceBaseURL = "recipe_service_base_url"
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
        budgetMonthMinor = normalized.budgetMonth?.asMinorUnits
        budgetInputPeriod = normalized.budgetInputPeriod.rawValue
        storesJSON = try Self.encodeJSON(normalized.stores.map(\.rawValue))
        dislikedListJSON = try Self.encodeJSON(normalized.dislikedList)
        avoidBones = normalized.avoidBones
        breakfastMinute = normalized.mealSchedule.breakfastMinute
        lunchMinute = normalized.mealSchedule.lunchMinute
        dinnerMinute = normalized.mealSchedule.dinnerMinute
        strictMacroTracking = normalized.strictMacroTracking
        macroTolerancePercent = normalized.macroTolerancePercent
        macroGoalSource = normalized.macroGoalSource.rawValue
        kcalGoal = normalized.kcalGoal
        proteinGoalGrams = normalized.proteinGoalGrams
        fatGoalGrams = normalized.fatGoalGrams
        carbsGoalGrams = normalized.carbsGoalGrams
        weightGoalKg = normalized.weightGoalKg
        preferredColorScheme = normalized.preferredColorScheme
        healthKitReadEnabled = normalized.healthKitReadEnabled
        healthKitWriteEnabled = normalized.healthKitWriteEnabled
        enableAnimations = normalized.enableAnimations
        hapticsEnabled = normalized.hapticsEnabled
        showHealthCardOnHome = normalized.showHealthCardOnHome
        dietProfile = normalized.dietProfile.rawValue
        recipeServiceBaseURL = normalized.recipeServiceBaseURLOverride
        self.onboardingCompleted = onboardingCompleted
    }

    func asDomainSettings() -> AppSettings {
        let parsedDays = (try? Self.decodeJSON([Int].self, from: expiryAlertsDaysJSON)) ?? AppSettings.default.expiryAlertsDays
        let parsedStoresRaw = (try? Self.decodeJSON([String].self, from: storesJSON)) ?? AppSettings.default.stores.map(\.rawValue)
        let parsedStores = parsedStoresRaw.compactMap(Store.init(rawValue:))
        let parsedDisliked = (try? Self.decodeJSON([String].self, from: dislikedListJSON)) ?? AppSettings.default.dislikedList
        let parsedMacroGoalSource = AppSettings.MacroGoalSource(rawValue: macroGoalSource) ?? .automatic
        let parsedBudgetInputPeriod = AppSettings.BudgetInputPeriod(rawValue: budgetInputPeriod) ?? .week
        let parsedDietProfile = AppSettings.DietProfile(rawValue: dietProfile) ?? .medium

        return AppSettings(
            quietStartMinute: quietStartMinute,
            quietEndMinute: quietEndMinute,
            expiryAlertsDays: parsedDays,
            budgetDay: Decimal.fromMinorUnits(budgetDayMinor),
            budgetWeek: budgetWeekMinor.map(Decimal.fromMinorUnits),
            budgetMonth: budgetMonthMinor.map(Decimal.fromMinorUnits),
            budgetInputPeriod: parsedBudgetInputPeriod,
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
            macroGoalSource: parsedMacroGoalSource,
            kcalGoal: kcalGoal,
            proteinGoalGrams: proteinGoalGrams,
            fatGoalGrams: fatGoalGrams,
            carbsGoalGrams: carbsGoalGrams,
            weightGoalKg: weightGoalKg,
            preferredColorScheme: preferredColorScheme,
            healthKitReadEnabled: healthKitReadEnabled,
            healthKitWriteEnabled: healthKitWriteEnabled,
            enableAnimations: enableAnimations,
            hapticsEnabled: hapticsEnabled,
            showHealthCardOnHome: showHealthCardOnHome,
            dietProfile: parsedDietProfile,
            recipeServiceBaseURLOverride: recipeServiceBaseURL
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
