import XCTest
@testable import InventoryCore

final class BarcodeLookupServiceTests: XCTestCase {
    func testResolveReturnsLocalProductWhenExists() async {
        let existing = Product(
            barcode: "4601234567890",
            name: "Молоко",
            brand: "Бренд",
            category: "Молочные продукты",
            defaultUnit: .pcs,
            disliked: false,
            mayContainBones: false
        )

        let inventory = MockInventoryService(productsByBarcode: ["4601234567890": existing])
        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [MockProvider(providerID: "mock", payload: nil)]
        )

        let result = await service.resolve(rawCode: "4601234567890")

        guard case .found(let product, _, _) = result else {
            XCTFail("Expected found resolution")
            return
        }

        XCTAssertEqual(product.name, "Молоко")
        XCTAssertTrue(inventory.createdProducts.isEmpty)
    }

    func testResolveCreatesProductFromProvider() async {
        let inventory = MockInventoryService(productsByBarcode: [:])

        let providerPayload = BarcodeLookupPayload(
            barcode: "4601234567890",
            name: "Творог",
            brand: "Бренд",
            category: "Молочные продукты",
            nutrition: .empty
        )

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [MockProvider(providerID: "mock_provider", payload: providerPayload)]
        )

        let result = await service.resolve(rawCode: "4601234567890")

        guard case .created(let product, _, _, let provider) = result else {
            XCTFail("Expected created resolution")
            return
        }

        XCTAssertEqual(provider, "mock_provider")
        XCTAssertEqual(product.name, "Творог")
        XCTAssertEqual(inventory.createdProducts.count, 1)
    }

    func testResolveUsesParallelFirstHitAndPrefersFastProvider() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let slowProvider = DelayedSuccessProvider(
            providerID: "slow_provider",
            delayNanoseconds: 700_000_000,
            payload: BarcodeLookupPayload(
                barcode: "4601234567890",
                name: "Медленный",
                brand: nil,
                category: "Продукты",
                nutrition: .empty
            )
        )
        let fastProvider = DelayedSuccessProvider(
            providerID: "fast_provider",
            delayNanoseconds: 10_000_000,
            payload: BarcodeLookupPayload(
                barcode: "4601234567890",
                name: "Быстрый",
                brand: nil,
                category: "Продукты",
                nutrition: .empty
            )
        )

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [slowProvider, fastProvider],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 2.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 60
            )
        )

        let result = await service.resolve(rawCode: "4601234567890")

        guard case .created(let product, _, _, let providerID) = result else {
            XCTFail("Expected created resolution")
            return
        }

        XCTAssertEqual(providerID, "fast_provider")
        XCTAssertEqual(product.name, "Быстрый")
    }

    func testResolveInternalCodeByMapping() async {
        let mappedProduct = Product(
            barcode: nil,
            name: "Яблоки",
            brand: nil,
            category: "Фрукты",
            defaultUnit: .g,
            disliked: false,
            mayContainBones: false
        )

        let inventory = MockInventoryService(productsByBarcode: [:], productsByInternalCode: ["229999": mappedProduct])
        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: []
        )

        let result = await service.resolve(rawCode: "229999")

        guard case .found(let product, _, let weight) = result else {
            XCTFail("Expected found resolution")
            return
        }

        XCTAssertEqual(product.name, "Яблоки")
        XCTAssertEqual(weight, 999)
    }

    func testResolveRetriesAfterTransientFailure() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let flakyProvider = FlakyProvider(
            providerID: "flaky",
            failingCallsCount: 1,
            payload: BarcodeLookupPayload(
                barcode: "4601234567890",
                name: "Кефир",
                brand: "Бренд",
                category: "Молочные продукты",
                nutrition: .empty
            )
        )

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [flakyProvider],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 2,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 0
            )
        )

        let result = await service.resolve(rawCode: "4601234567890")

        guard case .created(let product, _, _, _) = result else {
            XCTFail("Expected created resolution after retry")
            return
        }

        XCTAssertEqual(product.name, "Кефир")
        let calls = await flakyProvider.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testResolveDataMatrixNormalizesGTIN14ToEAN13() async {
        let existing = Product(
            barcode: "4601234567890",
            name: "Сыр",
            brand: "Бренд",
            category: "Молочные продукты",
            defaultUnit: .pcs,
            disliked: false,
            mayContainBones: false
        )

        let inventory = MockInventoryService(productsByBarcode: ["4601234567890": existing])
        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: []
        )

        let result = await service.resolve(rawCode: "010460123456789017270101")

        guard case .found(let product, let expiry, _) = result else {
            XCTFail("Expected found resolution")
            return
        }

        XCTAssertEqual(product.id, existing.id)
        XCTAssertNotNil(expiry)
    }

    func testResolveInternalCodeUsesMappedWeightFallback() async {
        let mappedProduct = Product(
            barcode: nil,
            name: "Яблоки",
            brand: nil,
            category: "Фрукты",
            defaultUnit: .g,
            disliked: false,
            mayContainBones: false
        )

        let mapping = InternalCodeMapping(
            code: "AA12",
            productId: mappedProduct.id,
            parsedWeightGrams: 350,
            createdAt: Date()
        )

        let inventory = MockInventoryService(
            productsByBarcode: [:],
            productsByInternalCode: ["AA12": mappedProduct],
            mappingsByInternalCode: ["AA12": mapping]
        )
        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: []
        )

        let result = await service.resolve(rawCode: "AA12")

        guard case .found(let product, _, let weight) = result else {
            XCTFail("Expected found resolution")
            return
        }

        XCTAssertEqual(product.id, mappedProduct.id)
        XCTAssertEqual(weight, 350)
    }

    func testResolveUsesNegativeCacheForRepeatedNotFoundBarcodeInWriteOffMode() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let nilProvider = AlwaysNilProvider(providerID: "nil_provider")

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [nilProvider],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 60
            )
        )

        let first = await service.resolve(rawCode: "4601234567890", allowCreate: false)
        let second = await service.resolve(rawCode: "4601234567890", allowCreate: false)

        guard case .notFound = first else {
            XCTFail("Expected notFound for first lookup")
            return
        }

        guard case .notFound = second else {
            XCTFail("Expected notFound for cached lookup")
            return
        }

        let calls = await nilProvider.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testResolveCreatesAutoTemplateWhenProvidersMissInAddMode() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let nilProvider = AlwaysNilProvider(providerID: "nil_provider")

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [nilProvider],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 60
            )
        )

        let result = await service.resolve(rawCode: "4601234567890", allowCreate: true)

        guard case .created(let product, _, _, let providerID) = result else {
            XCTFail("Expected auto-template creation")
            return
        }

        XCTAssertEqual(providerID, "auto_template")
        XCTAssertEqual(product.barcode, "4601234567890")
        XCTAssertEqual(product.name, "Товар 4601234567890")
    }

    func testResolveKeepsNotFoundInWriteOffModeWhenProvidersMiss() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let nilProvider = AlwaysNilProvider(providerID: "nil_provider")

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [nilProvider],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 60
            )
        )

        let result = await service.resolve(rawCode: "4601234567890", allowCreate: false)

        guard case .notFound(let barcode, _, _, _) = result else {
            XCTFail("Expected notFound resolution")
            return
        }

        XCTAssertEqual(barcode, "4601234567890")
    }

    func testResolveIgnoreNegativeCacheInAddModeAndCreatesTemplate() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let nilProvider = AlwaysNilProvider(providerID: "nil_provider")

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [nilProvider],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 300
            )
        )

        let writeOffResult = await service.resolve(rawCode: "4601234567890", allowCreate: false)
        guard case .notFound = writeOffResult else {
            XCTFail("Expected notFound in write-off mode")
            return
        }

        let addModeResult = await service.resolve(rawCode: "4601234567890", allowCreate: true)
        guard case .created(let product, _, _, let providerID) = addModeResult else {
            XCTFail("Expected auto-template creation in add mode")
            return
        }

        XCTAssertEqual(providerID, "auto_template")
        XCTAssertEqual(product.name, "Товар 4601234567890")
        let calls = await nilProvider.callCount()
        XCTAssertEqual(calls, 2)
    }

    func testResolveSkipsProviderWhenCircuitBreakerOpen() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let failingProvider = AlwaysFailProvider(providerID: "always_fail")
        let successProvider = DynamicSuccessProvider(providerID: "dynamic_success")

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [failingProvider, successProvider],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 1,
                circuitBreakerCooldownSeconds: 600,
                negativeCacheSeconds: 0
            )
        )

        let first = await service.resolve(rawCode: "4601234567890")
        let second = await service.resolve(rawCode: "4601234567891")

        guard case .created(_, _, _, let firstProvider) = first else {
            XCTFail("Expected created result for first lookup")
            return
        }

        guard case .created(_, _, _, let secondProvider) = second else {
            XCTFail("Expected created result for second lookup")
            return
        }

        XCTAssertEqual(firstProvider, "dynamic_success")
        XCTAssertEqual(secondProvider, "dynamic_success")
        let failingCalls = await failingProvider.callCount()
        let successCalls = await successProvider.callCount()
        XCTAssertEqual(failingCalls, 1)
        XCTAssertEqual(successCalls, 2)
    }

    func testResolveSkipsInvalidFirstProviderAndUsesSecondValidProvider() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let invalidLocalPayload = BarcodeLookupPayload(
            barcode: "4601576009686",
            name: "4601576009686",
            brand: nil,
            category: "Продукты",
            nutrition: .empty
        )
        let validPayload = BarcodeLookupPayload(
            barcode: "4601576009686",
            name: "МАЙОНЕЗ ПРОВАНСАЛЬ",
            brand: nil,
            category: "Продукты",
            nutrition: .empty
        )

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [
                MockProvider(providerID: "local_barcode_db", payload: invalidLocalPayload),
                MockProvider(providerID: "barcode_list_ru", payload: validPayload)
            ],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 60
            )
        )

        let result = await service.resolve(rawCode: "4601576009686", allowCreate: true)

        guard case .created(let product, _, _, let providerID) = result else {
            XCTFail("Expected created resolution")
            return
        }

        XCTAssertEqual(providerID, "barcode_list_ru")
        XCTAssertEqual(product.name, "МАЙОНЕЗ ПРОВАНСАЛЬ")
    }

    func testResolveSkipsSearchPlaceholderNameAndUsesNextValidProvider() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let invalidPayload = BarcodeLookupPayload(
            barcode: "4680017928991",
            name: "Поиск:4680017928991",
            brand: nil,
            category: "Продукты",
            nutrition: .empty
        )
        let validPayload = BarcodeLookupPayload(
            barcode: "4680017928991",
            name: "Йогурт питьевой",
            brand: "Бренд",
            category: "Продукты",
            nutrition: .empty
        )

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [
                MockProvider(providerID: "barcode_list_ru", payload: invalidPayload),
                MockProvider(providerID: "go_upc", payload: validPayload)
            ],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 60
            )
        )

        let result = await service.resolve(rawCode: "4680017928991", allowCreate: true)
        guard case .created(let product, _, _, let providerID) = result else {
            XCTFail("Expected created resolution")
            return
        }

        XCTAssertEqual(providerID, "go_upc")
        XCTAssertEqual(product.name, "Йогурт питьевой")
    }

    func testResolveFallsBackToGoUPCWhenBarcodeListMisses() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [
                AlwaysNilProvider(providerID: "barcode_list_ru"),
                MockProvider(
                    providerID: "go_upc",
                    payload: BarcodeLookupPayload(
                        barcode: "4607001771562",
                        name: "Jacobs Кофе Растворимый Monarch",
                        brand: "Jacobs",
                        category: "Продукты",
                        nutrition: .empty
                    )
                )
            ],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 60
            )
        )

        let result = await service.resolve(rawCode: "4607001771562", allowCreate: true)
        guard case .created(let product, _, _, let providerID) = result else {
            XCTFail("Expected created resolution")
            return
        }

        XCTAssertEqual(providerID, "go_upc")
        XCTAssertEqual(product.name, "Jacobs Кофе Растворимый Monarch")
        XCTAssertEqual(product.brand, "Jacobs")
    }

    func testResolvePrefersLocalDatabaseProviderOverSlowerNetworkProvider() async {
        let inventory = MockInventoryService(productsByBarcode: [:])
        let localPayload = BarcodeLookupPayload(
            barcode: "4601576009686",
            name: "Майонез МЖК",
            brand: "МЖК",
            category: "Продукты",
            nutrition: .empty
        )
        let slowNetworkProvider = DelayedSuccessProvider(
            providerID: "barcode_list_ru",
            delayNanoseconds: 700_000_000,
            payload: BarcodeLookupPayload(
                barcode: "4601576009686",
                name: "Сетевой майонез",
                brand: nil,
                category: "Продукты",
                nutrition: .empty
            )
        )

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [
                MockProvider(providerID: "local_barcode_db", payload: localPayload),
                slowNetworkProvider
            ],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 2.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 0
            )
        )

        let result = await service.resolve(rawCode: "4601576009686")

        guard case .created(let product, _, _, let providerID) = result else {
            XCTFail("Expected created resolution")
            return
        }

        XCTAssertEqual(providerID, "local_barcode_db")
        XCTAssertEqual(product.name, "Майонез МЖК")
    }

    func testResolveEnrichesExistingProductWhenNameIsBarcode() async {
        let existing = Product(
            barcode: "4607001771562",
            name: "4607001771562",
            brand: "Неизвестно",
            category: "Напитки",
            defaultUnit: .pcs,
            nutrition: .empty,
            disliked: false,
            mayContainBones: false
        )
        let inventory = MockInventoryService(productsByBarcode: ["4607001771562": existing])

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [
                MockProvider(
                    providerID: "barcode_list_ru",
                    payload: BarcodeLookupPayload(
                        barcode: "4607001771562",
                        name: "Кофе ЯКОБС Крема Сублмирован. 95гр",
                        brand: "JACOBS",
                        category: "Кофе",
                        nutrition: .empty
                    )
                )
            ],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 0
            )
        )

        let result = await service.resolve(rawCode: "4607001771562", allowCreate: true)
        guard case .found(let product, _, _) = result else {
            XCTFail("Expected found resolution")
            return
        }

        XCTAssertEqual(product.barcode, "4607001771562")
        XCTAssertEqual(product.name, "Кофе ЯКОБС Крема Сублмирован. 95гр")
        XCTAssertEqual(product.brand, "JACOBS")
        XCTAssertEqual(product.category, "Кофе")
    }

    func testResolveEnrichesExistingInvalidProductInWriteOffMode() async {
        let existing = Product(
            barcode: "4607001771562",
            name: "4607001771562",
            brand: nil,
            category: "Напитки",
            defaultUnit: .pcs,
            nutrition: .empty,
            disliked: false,
            mayContainBones: false
        )
        let inventory = MockInventoryService(productsByBarcode: ["4607001771562": existing])

        let service = BarcodeLookupService(
            inventoryService: inventory,
            scannerService: ScannerService(),
            providers: [
                MockProvider(
                    providerID: "barcode_list_ru",
                    payload: BarcodeLookupPayload(
                        barcode: "4607001771562",
                        name: "Кофе ЯКОБС Крема Сублмирован. 95гр",
                        brand: nil,
                        category: "Кофе",
                        nutrition: .empty
                    )
                )
            ],
            policy: BarcodeLookupPolicy(
                timeoutSeconds: 1.0,
                maxAttempts: 1,
                retryDelayMilliseconds: 0,
                providerCooldownMilliseconds: 0,
                circuitBreakerFailureThreshold: 3,
                circuitBreakerCooldownSeconds: 60,
                negativeCacheSeconds: 0
            )
        )

        let result = await service.resolve(rawCode: "4607001771562", allowCreate: false)
        guard case .found(let product, _, _) = result else {
            XCTFail("Expected found resolution")
            return
        }

        XCTAssertEqual(product.name, "Кофе ЯКОБС Крема Сублмирован. 95гр")
        XCTAssertEqual(product.category, "Кофе")
    }
}

private final class MockInventoryService: InventoryServiceProtocol {
    var productsByBarcode: [String: Product]
    var productsByInternalCode: [String: Product]
    var mappingsByInternalCode: [String: InternalCodeMapping]
    var createdProducts: [Product] = []

    init(
        productsByBarcode: [String: Product],
        productsByInternalCode: [String: Product] = [:],
        mappingsByInternalCode: [String: InternalCodeMapping] = [:]
    ) {
        self.productsByBarcode = productsByBarcode
        self.productsByInternalCode = productsByInternalCode
        self.mappingsByInternalCode = mappingsByInternalCode
    }

    func findProduct(by barcode: String) async throws -> Product? {
        productsByBarcode[barcode]
    }

    func findProduct(byInternalCode code: String) async throws -> Product? {
        productsByInternalCode[code]
    }

    func createProduct(_ product: Product) async throws -> Product {
        createdProducts.append(product)
        if let barcode = product.barcode {
            productsByBarcode[barcode] = product
        }
        return product
    }

    func updateProduct(_ product: Product) async throws -> Product {
        product
    }

    func deleteProduct(id: UUID) async throws {}

    func addBatch(_ batch: Batch) async throws -> Batch { batch }

    func updateBatch(_ batch: Batch) async throws -> Batch { batch }

    func removeBatch(id: UUID, quantity: Double?, intent: InventoryRemovalIntent, note: String?) async throws {}

    func listProducts(location: InventoryLocation?, search: String?) async throws -> [Product] {
        Array(productsByBarcode.values)
    }

    func listBatches(productId: UUID?) async throws -> [Batch] { [] }

    func savePriceEntry(_ entry: PriceEntry) async throws {}

    func listPriceHistory(productId: UUID?) async throws -> [PriceEntry] { [] }

    func recordEvent(_ event: InventoryEvent) async throws {}

    func listEvents(productId: UUID?) async throws -> [InventoryEvent] { [] }

    func expiringBatches(horizonDays: Int) async throws -> [Batch] { [] }

    func bindInternalCode(_ code: String, productId: UUID, parsedWeightGrams: Double?) async throws {}

    func internalCodeMapping(for code: String) async throws -> InternalCodeMapping? { mappingsByInternalCode[code] }
}

private struct MockProvider: BarcodeLookupProvider {
    let providerID: String
    let payload: BarcodeLookupPayload?

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        payload
    }
}

private final actor FlakyProvider: BarcodeLookupProvider {
    let providerID: String
    private var remainingFailures: Int
    private let payload: BarcodeLookupPayload
    private(set) var calls: Int = 0

    init(providerID: String, failingCallsCount: Int, payload: BarcodeLookupPayload) {
        self.providerID = providerID
        self.remainingFailures = failingCallsCount
        self.payload = payload
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        calls += 1
        if remainingFailures > 0 {
            remainingFailures -= 1
            struct TransientError: Error {}
            throw TransientError()
        }
        return payload
    }

    func callCount() -> Int {
        calls
    }
}

private final actor AlwaysNilProvider: BarcodeLookupProvider {
    let providerID: String
    private(set) var calls: Int = 0

    init(providerID: String) {
        self.providerID = providerID
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        calls += 1
        return nil
    }

    func callCount() -> Int {
        calls
    }
}

private final actor AlwaysFailProvider: BarcodeLookupProvider {
    let providerID: String
    private(set) var calls: Int = 0

    init(providerID: String) {
        self.providerID = providerID
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        calls += 1
        struct TransportError: Error {}
        throw TransportError()
    }

    func callCount() -> Int {
        calls
    }
}

private final actor DynamicSuccessProvider: BarcodeLookupProvider {
    let providerID: String
    private(set) var calls: Int = 0

    init(providerID: String) {
        self.providerID = providerID
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        calls += 1
        return BarcodeLookupPayload(
            barcode: barcode,
            name: "Авто-\(barcode.suffix(4))",
            brand: "Provider",
            category: "Продукты",
            nutrition: .empty
        )
    }

    func callCount() -> Int {
        calls
    }
}

private final actor DelayedSuccessProvider: BarcodeLookupProvider {
    let providerID: String
    private let delayNanoseconds: UInt64
    private let payload: BarcodeLookupPayload
    private(set) var calls: Int = 0

    init(providerID: String, delayNanoseconds: UInt64, payload: BarcodeLookupPayload) {
        self.providerID = providerID
        self.delayNanoseconds = delayNanoseconds
        self.payload = payload
    }

    func lookup(barcode: String) async throws -> BarcodeLookupPayload? {
        calls += 1
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return payload
    }

    func callCount() -> Int {
        calls
    }
}
