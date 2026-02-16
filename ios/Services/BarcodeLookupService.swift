import Foundation
import OSLog

enum BarcodeLookupServiceError: Error {
    case timeout
}

struct BarcodeLookupPolicy {
    var timeoutSeconds: Double
    var maxAttempts: Int
    var retryDelayMilliseconds: Int
    var providerCooldownMilliseconds: Int
    var circuitBreakerFailureThreshold: Int
    var circuitBreakerCooldownSeconds: Double
    var negativeCacheSeconds: Double

    static let `default` = BarcodeLookupPolicy(
        timeoutSeconds: 3.0,
        maxAttempts: 2,
        retryDelayMilliseconds: 350,
        providerCooldownMilliseconds: 250,
        circuitBreakerFailureThreshold: 3,
        circuitBreakerCooldownSeconds: 60.0,
        negativeCacheSeconds: 180.0
    )
}

final class BarcodeLookupService: @unchecked Sendable {
    private let inventoryService: any InventoryServiceProtocol
    private let scannerService: ScannerService
    private let providers: [any BarcodeLookupProvider]
    private let policy: BarcodeLookupPolicy
    private let runtimeGuard = LookupRuntimeGuard()
#if DEBUG
    private static let logger = Logger(subsystem: "com.projectvay.inventoryai", category: "barcode_lookup")
#endif

    init(
        inventoryService: any InventoryServiceProtocol,
        scannerService: ScannerService,
        providers: [any BarcodeLookupProvider],
        policy: BarcodeLookupPolicy = .default
    ) {
        self.inventoryService = inventoryService
        self.scannerService = scannerService
        self.providers = providers
        self.policy = policy
    }

    func resolve(rawCode: String, allowCreate: Bool = true) async -> ScanResolution {
        let payload = scannerService.parse(code: rawCode)

        switch payload {
        case .ean13(let barcode):
            return await resolveEan(
                barcode,
                suggestedExpiry: nil,
                parsedWeightGrams: nil,
                allowCreate: allowCreate
            )
        case .dataMatrix(_, let gtin, let expiryDate):
            guard
                let gtin,
                let normalizedBarcode = normalizeDataMatrixGTIN(gtin)
            else {
                return .notFound(barcode: nil, internalCode: nil, parsedWeightGrams: nil, suggestedExpiry: expiryDate)
            }
            return await resolveEan(
                normalizedBarcode,
                suggestedExpiry: expiryDate,
                parsedWeightGrams: nil,
                allowCreate: allowCreate
            )
        case .internalCode(let code, let parsedWeightGrams):
            return await resolveInternalCode(code, parsedWeightGrams: parsedWeightGrams)
        }
    }

    private func resolveEan(
        _ barcode: String,
        suggestedExpiry: Date?,
        parsedWeightGrams: Double?,
        allowCreate: Bool
    ) async -> ScanResolution {
        debugLog("resolve barcode=\(barcode) allowCreate=\(allowCreate)")
        do {
            if let product = try await inventoryService.findProduct(by: barcode) {
                if
                    shouldEnrichLocalProduct(product: product, barcode: barcode),
                    case .hit(let payload, _) = await lookupProvidersParallelFirstHit(barcode: barcode)
                {
                    var updated = product
                    updated.name = payload.name
                    updated.brand = payload.brand
                    updated.category = payload.category
                    updated.nutrition = payload.nutrition
                    let saved = try await inventoryService.updateProduct(updated)
                    await runtimeGuard.clearNegativeCache(barcode: barcode)
                    debugLog("enriched existing product barcode=\(barcode) newName=\"\(payload.name)\"")
                    return .found(product: saved, suggestedExpiry: suggestedExpiry, parsedWeightGrams: parsedWeightGrams)
                }

                await runtimeGuard.clearNegativeCache(barcode: barcode)
                debugLog("local product hit barcode=\(barcode) no remote enrichment")
                return .found(product: product, suggestedExpiry: suggestedExpiry, parsedWeightGrams: parsedWeightGrams)
            }

            if !allowCreate, await runtimeGuard.isNegativeCached(barcode: barcode) {
                debugLog("negative cache hit barcode=\(barcode) in write-off mode")
                return .notFound(barcode: barcode, internalCode: nil, parsedWeightGrams: parsedWeightGrams, suggestedExpiry: suggestedExpiry)
            }

            let providerResolution = await lookupProvidersParallelFirstHit(barcode: barcode)
            if case .hit(let payload, let providerID) = providerResolution {
                debugLog("provider hit provider=\(providerID) barcode=\(barcode) name=\"\(payload.name)\"")
                guard allowCreate else {
                    await runtimeGuard.clearNegativeCache(barcode: barcode)
                    debugLog("provider result ignored in write-off mode provider=\(providerID) barcode=\(barcode)")
                    return .notFound(
                        barcode: barcode,
                        internalCode: nil,
                        parsedWeightGrams: parsedWeightGrams,
                        suggestedExpiry: suggestedExpiry
                    )
                }

                let creationResult = try await createOrLoadProduct(
                    Product(
                        barcode: payload.barcode,
                        name: payload.name,
                        brand: payload.brand,
                        category: payload.category,
                        defaultUnit: .pcs,
                        nutrition: payload.nutrition,
                        disliked: false,
                        mayContainBones: false
                    )
                )

                await runtimeGuard.clearNegativeCache(barcode: barcode)
                switch creationResult {
                case .created(let product):
                    debugLog("created product from provider provider=\(providerID) barcode=\(barcode)")
                    return .created(
                        product: product,
                        suggestedExpiry: suggestedExpiry,
                        parsedWeightGrams: parsedWeightGrams,
                        provider: providerID
                    )
                case .existing(let product):
                    debugLog("provider returned existing product provider=\(providerID) barcode=\(barcode)")
                    return .found(product: product, suggestedExpiry: suggestedExpiry, parsedWeightGrams: parsedWeightGrams)
                }
            }

            guard allowCreate else {
                await runtimeGuard.saveNegativeCache(barcode: barcode, ttlSeconds: policy.negativeCacheSeconds)
                debugLog("provider miss in write-off mode barcode=\(barcode), saved negative cache")
                return .notFound(
                    barcode: barcode,
                    internalCode: nil,
                    parsedWeightGrams: parsedWeightGrams,
                    suggestedExpiry: suggestedExpiry
                )
            }

            let templateResult = try await createOrLoadProduct(
                Product(
                    barcode: barcode,
                    name: "Товар \(barcode)",
                    brand: nil,
                    category: "Продукты",
                    defaultUnit: .pcs,
                    nutrition: .empty,
                    disliked: false,
                    mayContainBones: false
                )
            )
            await runtimeGuard.clearNegativeCache(barcode: barcode)

            switch templateResult {
            case .created(let product):
                debugLog("auto_template created barcode=\(barcode)")
                return .created(
                    product: product,
                    suggestedExpiry: suggestedExpiry,
                    parsedWeightGrams: parsedWeightGrams,
                    provider: "auto_template"
                )
            case .existing(let product):
                debugLog("auto_template resolved existing barcode=\(barcode)")
                return .found(product: product, suggestedExpiry: suggestedExpiry, parsedWeightGrams: parsedWeightGrams)
            }
        } catch {
            debugLog("resolve error barcode=\(barcode) error=\(String(describing: error))")
            if allowCreate {
                if let product = try? await inventoryService.findProduct(by: barcode) {
                    debugLog("resolve error fallback to existing product barcode=\(barcode)")
                    return .found(product: product, suggestedExpiry: suggestedExpiry, parsedWeightGrams: parsedWeightGrams)
                }

                if let fallback = try? await inventoryService.createProduct(
                    Product(
                        barcode: barcode,
                        name: "Товар \(barcode)",
                        brand: nil,
                        category: "Продукты",
                        defaultUnit: .pcs,
                        nutrition: .empty,
                        disliked: false,
                        mayContainBones: false
                    )
                ) {
                    return .created(
                        product: fallback,
                        suggestedExpiry: suggestedExpiry,
                        parsedWeightGrams: parsedWeightGrams,
                        provider: "auto_template"
                    )
                }
            } else {
                await runtimeGuard.saveNegativeCache(barcode: barcode, ttlSeconds: policy.negativeCacheSeconds)
                debugLog("resolve error in write-off mode, saved negative cache barcode=\(barcode)")
            }

            return .notFound(barcode: barcode, internalCode: nil, parsedWeightGrams: parsedWeightGrams, suggestedExpiry: suggestedExpiry)
        }
    }

    private func resolveInternalCode(_ code: String, parsedWeightGrams: Double?) async -> ScanResolution {
        do {
            let mapping = try await inventoryService.internalCodeMapping(for: code)
            let resolvedWeight = parsedWeightGrams ?? mapping?.parsedWeightGrams
            if let product = try await inventoryService.findProduct(byInternalCode: code) {
                return .found(product: product, suggestedExpiry: nil, parsedWeightGrams: resolvedWeight)
            }
            return .notFound(barcode: nil, internalCode: code, parsedWeightGrams: resolvedWeight, suggestedExpiry: nil)
        } catch {
            return .notFound(barcode: nil, internalCode: code, parsedWeightGrams: parsedWeightGrams, suggestedExpiry: nil)
        }
    }

    private func lookupProvidersParallelFirstHit(barcode: String) async -> ProviderLookupAggregateResult {
        var eligibleProviders: [any BarcodeLookupProvider] = []
        for provider in providers {
            guard await runtimeGuard.canQueryProvider(
                providerID: provider.providerID,
                failureThreshold: policy.circuitBreakerFailureThreshold
            ) else {
                debugLog("skip provider due circuit breaker provider=\(provider.providerID) barcode=\(barcode)")
                continue
            }
            eligibleProviders.append(provider)
        }

        guard !eligibleProviders.isEmpty else {
            debugLog("no eligible providers barcode=\(barcode)")
            return .miss
        }
        let providerIDs = eligibleProviders.map { $0.providerID }.joined(separator: ",")
        debugLog("query providers barcode=\(barcode) providers=\(providerIDs)")

        return await withTaskGroup(of: ProviderLookupTaskResult.self) { group in
            for provider in eligibleProviders {
                group.addTask { [self] in
                    let result = await lookupWithRetry(provider: provider, barcode: barcode)
                    switch result {
                    case .hit(let payload):
                        await runtimeGuard.markProviderSuccess(providerID: provider.providerID)
                        return .hit(payload: payload, providerID: provider.providerID)
                    case .miss:
                        await runtimeGuard.markProviderSuccess(providerID: provider.providerID)
                        return .miss(providerID: provider.providerID)
                    case .failed:
                        await runtimeGuard.markProviderFailure(
                            providerID: provider.providerID,
                            failureThreshold: policy.circuitBreakerFailureThreshold,
                            cooldownSeconds: policy.circuitBreakerCooldownSeconds
                        )
                        return .failed(providerID: provider.providerID)
                    case .cancelled:
                        return .cancelled(providerID: provider.providerID)
                    }
                }
            }

            var hasFailure = false
            while let taskResult = await group.next() {
                switch taskResult {
                case .hit(let payload, let providerID):
                    debugLog("provider completed hit provider=\(providerID) barcode=\(barcode) name=\"\(payload.name)\"")
                    group.cancelAll()
                    return .hit(payload: payload, providerID: providerID)
                case .failed(let providerID):
                    debugLog("provider completed failed provider=\(providerID) barcode=\(barcode)")
                    hasFailure = true
                case .miss(let providerID):
                    debugLog("provider completed miss provider=\(providerID) barcode=\(barcode)")
                    continue
                case .cancelled(let providerID):
                    debugLog("provider completed cancelled provider=\(providerID) barcode=\(barcode)")
                    continue
                }
            }

            debugLog("providers completed barcode=\(barcode) aggregate=\(hasFailure ? "failed" : "miss")")
            return hasFailure ? .failed : .miss
        }
    }

    private func createOrLoadProduct(_ product: Product) async throws -> ProductCreationResult {
        do {
            let saved = try await inventoryService.createProduct(product)
            return .created(saved)
        } catch {
            if
                let barcode = product.barcode,
                let existing = try await inventoryService.findProduct(by: barcode)
            {
                return .existing(existing)
            }
            throw error
        }
    }

    private func lookupWithRetry(provider: any BarcodeLookupProvider, barcode: String) async -> ProviderLookupResult {
        var hadTransportError = false

        for attempt in 1...policy.maxAttempts {
            let startedAt = Date()
            await runtimeGuard.waitForProviderCooldown(
                providerID: provider.providerID,
                minimumDelayMilliseconds: policy.providerCooldownMilliseconds
            )

            do {
                let providerTimeout = timeoutSeconds(for: provider)
                let payload = try await withTimeout(seconds: providerTimeout) {
                    try await provider.lookup(barcode: barcode)
                }

                if
                    let payload,
                    BarcodeLookupPayloadValidator.isValidPayload(payload, requestedBarcode: barcode)
                {
                    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    debugLog("attempt hit provider=\(provider.providerID) barcode=\(barcode) attempt=\(attempt) elapsedMs=\(elapsedMs)")
                    return .hit(payload)
                }

                if let payload {
                    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    debugLog("attempt invalid payload provider=\(provider.providerID) barcode=\(barcode) attempt=\(attempt) elapsedMs=\(elapsedMs) name=\"\(payload.name)\"")
                } else {
                    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    debugLog("attempt miss provider=\(provider.providerID) barcode=\(barcode) attempt=\(attempt) elapsedMs=\(elapsedMs)")
                }
                return hadTransportError ? .failed : .miss
            } catch {
                if error is CancellationError {
                    debugLog("attempt cancelled provider=\(provider.providerID) barcode=\(barcode) attempt=\(attempt)")
                    return .cancelled
                }

                hadTransportError = true
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                debugLog("attempt failed provider=\(provider.providerID) barcode=\(barcode) attempt=\(attempt) elapsedMs=\(elapsedMs) error=\(String(describing: error))")

                guard attempt < policy.maxAttempts else {
                    return .failed
                }

                let delayNs = UInt64(policy.retryDelayMilliseconds * attempt) * 1_000_000
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }

        return hadTransportError ? .failed : .miss
    }

    private func debugLog(_ message: String) {
#if DEBUG
        Self.logger.debug("\(message, privacy: .public)")
#endif
    }

    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let timeoutNs = UInt64(max(0.1, seconds) * 1_000_000_000)

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNs)
                throw BarcodeLookupServiceError.timeout
            }

            guard let first = try await group.next() else {
                throw BarcodeLookupServiceError.timeout
            }

            group.cancelAll()
            return first
        }
    }

    private func timeoutSeconds(for provider: any BarcodeLookupProvider) -> Double {
        switch provider.providerID {
        case "barcode_list_ru":
            // Remote HTML/markdown mirror can be slower than JSON APIs.
            return max(policy.timeoutSeconds, 9.0)
        default:
            return policy.timeoutSeconds
        }
    }

    private func normalizeDataMatrixGTIN(_ gtin: String) -> String? {
        let digitsOnly = gtin.filter(\.isNumber)
        guard !digitsOnly.isEmpty else { return nil }

        if digitsOnly.count == 13 {
            return digitsOnly
        }

        if digitsOnly.count == 14, digitsOnly.hasPrefix("0") {
            return String(digitsOnly.dropFirst())
        }

        return digitsOnly
    }

    private func shouldEnrichLocalProduct(product: Product, barcode: String) -> Bool {
        if !BarcodeLookupPayloadValidator.isMeaningfulName(product.name, barcode: barcode) {
            return true
        }

        let normalized = product.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let templatePrefix = "товар \(barcode)"
        if normalized.hasPrefix(templatePrefix.lowercased()) {
            return true
        }

        let looksGenericCategory = product.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "продукты"
        let missingBrand = (product.brand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let emptyNutrition = product.nutrition == .empty
        return looksGenericCategory && missingBrand && emptyNutrition && normalized.contains(barcode)
    }
}

private enum ProviderLookupResult {
    case hit(BarcodeLookupPayload)
    case miss
    case failed
    case cancelled
}

private enum ProviderLookupAggregateResult {
    case hit(payload: BarcodeLookupPayload, providerID: String)
    case miss
    case failed
}

private enum ProviderLookupTaskResult {
    case hit(payload: BarcodeLookupPayload, providerID: String)
    case miss(providerID: String)
    case failed(providerID: String)
    case cancelled(providerID: String)
}

private enum ProductCreationResult {
    case created(Product)
    case existing(Product)
}

private actor LookupRuntimeGuard {
    private struct ProviderState {
        var consecutiveFailures: Int = 0
        var openUntil: Date?
    }

    private var lastRequestByProvider: [String: Date] = [:]
    private var providerStates: [String: ProviderState] = [:]
    private var negativeCacheByBarcode: [String: Date] = [:]

    func canQueryProvider(providerID: String, failureThreshold: Int) -> Bool {
        pruneExpiredProviderLocks()

        guard failureThreshold > 0 else {
            return true
        }

        guard let state = providerStates[providerID] else {
            return true
        }

        if let openUntil = state.openUntil, openUntil > Date() {
            return false
        }

        return true
    }

    func markProviderSuccess(providerID: String) {
        providerStates[providerID] = ProviderState(consecutiveFailures: 0, openUntil: nil)
    }

    func markProviderFailure(providerID: String, failureThreshold: Int, cooldownSeconds: Double) {
        var state = providerStates[providerID] ?? ProviderState()
        state.consecutiveFailures += 1

        let threshold = max(1, failureThreshold)
        if state.consecutiveFailures >= threshold {
            state.openUntil = Date().addingTimeInterval(max(1, cooldownSeconds))
        }

        providerStates[providerID] = state
    }

    func isNegativeCached(barcode: String) -> Bool {
        pruneExpiredNegativeCache()

        guard let expiresAt = negativeCacheByBarcode[barcode] else {
            return false
        }

        return expiresAt > Date()
    }

    func saveNegativeCache(barcode: String, ttlSeconds: Double) {
        guard ttlSeconds > 0 else {
            return
        }

        negativeCacheByBarcode[barcode] = Date().addingTimeInterval(ttlSeconds)
    }

    func clearNegativeCache(barcode: String) {
        negativeCacheByBarcode.removeValue(forKey: barcode)
    }

    func waitForProviderCooldown(providerID: String, minimumDelayMilliseconds: Int) async {
        guard minimumDelayMilliseconds > 0 else {
            lastRequestByProvider[providerID] = Date()
            return
        }

        let now = Date()
        if let last = lastRequestByProvider[providerID] {
            let elapsed = now.timeIntervalSince(last)
            let required = Double(minimumDelayMilliseconds) / 1000.0
            if elapsed < required {
                let remaining = required - elapsed
                let delayNs = UInt64(remaining * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }

        lastRequestByProvider[providerID] = Date()
    }

    private func pruneExpiredProviderLocks() {
        let now = Date()
        for (providerID, state) in providerStates {
            guard let openUntil = state.openUntil else {
                continue
            }

            if openUntil <= now {
                providerStates[providerID] = ProviderState(consecutiveFailures: 0, openUntil: nil)
            }
        }
    }

    private func pruneExpiredNegativeCache() {
        let now = Date()
        negativeCacheByBarcode = negativeCacheByBarcode.filter { $0.value > now }
    }
}
