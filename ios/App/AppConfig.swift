import Foundation

struct AppConfig {
    let enableEANDB: Bool
    let enableRFProvider: Bool
    let enableOpenFoodFacts: Bool
    let allowInsecureLookupEndpoints: Bool
    let eanDBApiKey: String?
    let rfLookupBaseURL: URL?
    let lookupPolicy: BarcodeLookupPolicy

    static func live(bundle: Bundle = .main, env: [String: String] = ProcessInfo.processInfo.environment) -> AppConfig {
        let info = bundle.infoDictionary ?? [:]

        let enableEANDB = boolValue(
            env["ENABLE_EANDB_LOOKUP"] ?? stringValue(info["EnableEANDBLookup"]),
            fallback: false
        )

        let enableRFProvider = boolValue(
            env["ENABLE_RF_LOOKUP"] ?? stringValue(info["EnableRFLookup"]),
            fallback: false
        )

        let enableOpenFoodFacts = boolValue(
            env["ENABLE_OPEN_FOOD_FACTS_LOOKUP"] ?? stringValue(info["EnableOpenFoodFactsLookup"]),
            fallback: true
        )

        let allowInsecureLookupEndpoints = boolValue(
            env["ALLOW_INSECURE_LOOKUP_ENDPOINTS"] ?? stringValue(info["AllowInsecureLookupEndpoints"]),
            fallback: false
        )

        let eanDBApiKey = nonEmpty(
            env["EAN_DB_API_KEY"] ?? stringValue(info["EANDBApiKey"])
        )

        let rfLookupBaseURL = sanitizeLookupBaseURL(
            env["RF_LOOKUP_BASE_URL"] ?? stringValue(info["BarcodeProxyBaseURL"])
        , allowInsecure: allowInsecureLookupEndpoints)

        let timeoutSeconds = doubleValue(
            env["LOOKUP_TIMEOUT_SECONDS"] ?? stringValue(info["LookupTimeoutSeconds"]),
            fallback: 3.0
        )

        let maxAttempts = intValue(
            env["LOOKUP_RETRY_COUNT"] ?? stringValue(info["LookupRetryCount"]),
            fallback: 2
        )

        let retryDelayMs = intValue(
            env["LOOKUP_RETRY_DELAY_MS"] ?? stringValue(info["LookupRetryDelayMilliseconds"]),
            fallback: 350
        )

        let providerCooldownMs = intValue(
            env["LOOKUP_PROVIDER_COOLDOWN_MS"] ?? stringValue(info["LookupProviderCooldownMilliseconds"]),
            fallback: 250
        )

        let circuitBreakerThreshold = intValue(
            env["LOOKUP_CIRCUIT_BREAKER_FAILURE_THRESHOLD"] ?? stringValue(info["LookupCircuitBreakerFailureThreshold"]),
            fallback: 3
        )

        let circuitBreakerCooldownSeconds = doubleValue(
            env["LOOKUP_CIRCUIT_BREAKER_COOLDOWN_SECONDS"] ?? stringValue(info["LookupCircuitBreakerCooldownSeconds"]),
            fallback: 60
        )

        let negativeCacheSeconds = doubleValue(
            env["LOOKUP_NEGATIVE_CACHE_SECONDS"] ?? stringValue(info["LookupNegativeCacheSeconds"]),
            fallback: 180
        )

        return AppConfig(
            enableEANDB: enableEANDB,
            enableRFProvider: enableRFProvider,
            enableOpenFoodFacts: enableOpenFoodFacts,
            allowInsecureLookupEndpoints: allowInsecureLookupEndpoints,
            eanDBApiKey: eanDBApiKey,
            rfLookupBaseURL: rfLookupBaseURL,
            lookupPolicy: BarcodeLookupPolicy(
                timeoutSeconds: max(0.5, timeoutSeconds),
                maxAttempts: max(1, maxAttempts),
                retryDelayMilliseconds: max(0, retryDelayMs),
                providerCooldownMilliseconds: max(0, providerCooldownMs),
                circuitBreakerFailureThreshold: max(1, circuitBreakerThreshold),
                circuitBreakerCooldownSeconds: max(1, circuitBreakerCooldownSeconds),
                negativeCacheSeconds: max(0, negativeCacheSeconds)
            )
        )
    }
}

private extension AppConfig {
    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    static func nonEmpty(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    static func sanitizeLookupBaseURL(_ value: String?, allowInsecure: Bool) -> URL? {
        guard
            let raw = nonEmpty(value),
            let url = URL(string: raw),
            let scheme = url.scheme?.lowercased()
        else {
            return nil
        }

        if allowInsecure {
            if scheme == "https" || scheme == "http" {
                return url
            }
            return nil
        }

        return scheme == "https" ? url : nil
    }

    static func boolValue(_ value: String?, fallback: Bool) -> Bool {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return fallback
        }

        switch raw {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return fallback
        }
    }

    static func intValue(_ value: String?, fallback: Int) -> Int {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), let parsed = Int(raw) else {
            return fallback
        }
        return parsed
    }

    static func doubleValue(_ value: String?, fallback: Double) -> Double {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), let parsed = Double(raw) else {
            return fallback
        }
        return parsed
    }
}
