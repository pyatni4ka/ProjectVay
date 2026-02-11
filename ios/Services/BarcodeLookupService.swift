import Foundation

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

final class BarcodeLookupService {
    private let inventoryService: any InventoryServiceProtocol
    private let scannerService: ScannerService
    private let providers: [any BarcodeLookupProvider]
    private let policy: BarcodeLookupPolicy
    private let runtimeGuard = LookupRuntimeGuard()

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
        do {
            if await runtimeGuard.isNegativeCached(barcode: barcode) {
                return .notFound(barcode: barcode, internalCode: nil, parsedWeightGrams: parsedWeightGrams, suggestedExpiry: suggestedExpiry)
            }

            if let product = try await inventoryService.findProduct(by: barcode) {
                await runtimeGuard.clearNegativeCache(barcode: barcode)
                return .found(product: product, suggestedExpiry: suggestedExpiry, parsedWeightGrams: parsedWeightGrams)
            }

            guard allowCreate else {
                await runtimeGuard.saveNegativeCache(barcode: barcode, ttlSeconds: policy.negativeCacheSeconds)
                return .notFound(
                    barcode: barcode,
                    internalCode: nil,
                    parsedWeightGrams: parsedWeightGrams,
                    suggestedExpiry: suggestedExpiry
                )
            }

            for provider in providers {
                guard await runtimeGuard.canQueryProvider(
                    providerID: provider.providerID,
                    failureThreshold: policy.circuitBreakerFailureThreshold
                ) else {
                    continue
                }

                let lookupResult = await lookupWithRetry(provider: provider, barcode: barcode)

                switch lookupResult {
                case .hit(let payload):
                    await runtimeGuard.markProviderSuccess(providerID: provider.providerID)
                    await runtimeGuard.clearNegativeCache(barcode: barcode)

                    let product = Product(
                        barcode: payload.barcode,
                        name: payload.name,
                        brand: payload.brand,
                        category: payload.category,
                        defaultUnit: .pcs,
                        nutrition: payload.nutrition,
                        disliked: false,
                        mayContainBones: false
                    )

                    let saved = try await inventoryService.createProduct(product)
                    return .created(
                        product: saved,
                        suggestedExpiry: suggestedExpiry,
                        parsedWeightGrams: parsedWeightGrams,
                        provider: provider.providerID
                    )
                case .miss:
                    await runtimeGuard.markProviderSuccess(providerID: provider.providerID)
                    continue
                case .failed:
                    await runtimeGuard.markProviderFailure(
                        providerID: provider.providerID,
                        failureThreshold: policy.circuitBreakerFailureThreshold,
                        cooldownSeconds: policy.circuitBreakerCooldownSeconds
                    )
                }
            }

            await runtimeGuard.saveNegativeCache(barcode: barcode, ttlSeconds: policy.negativeCacheSeconds)
            return .notFound(barcode: barcode, internalCode: nil, parsedWeightGrams: parsedWeightGrams, suggestedExpiry: suggestedExpiry)
        } catch {
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

    private func lookupWithRetry(provider: any BarcodeLookupProvider, barcode: String) async -> ProviderLookupResult {
        var hadTransportError = false

        for attempt in 1...policy.maxAttempts {
            await runtimeGuard.waitForProviderCooldown(
                providerID: provider.providerID,
                minimumDelayMilliseconds: policy.providerCooldownMilliseconds
            )

            do {
                let payload = try await withTimeout(seconds: policy.timeoutSeconds) {
                    try await provider.lookup(barcode: barcode)
                }

                if let payload {
                    return .hit(payload)
                }

                return hadTransportError ? .failed : .miss
            } catch {
                hadTransportError = true

                guard attempt < policy.maxAttempts else {
                    return .failed
                }

                let delayNs = UInt64(policy.retryDelayMilliseconds * attempt) * 1_000_000
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }

        return hadTransportError ? .failed : .miss
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
}

private enum ProviderLookupResult {
    case hit(BarcodeLookupPayload)
    case miss
    case failed
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
