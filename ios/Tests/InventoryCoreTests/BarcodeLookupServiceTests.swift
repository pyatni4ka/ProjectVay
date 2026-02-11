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

    func testResolveUsesNegativeCacheForRepeatedNotFoundBarcode() async {
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

        let first = await service.resolve(rawCode: "4601234567890")
        let second = await service.resolve(rawCode: "4601234567890")

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

    func removeBatch(id: UUID) async throws {}

    func listProducts(location: InventoryLocation?, search: String?) async throws -> [Product] {
        Array(productsByBarcode.values)
    }

    func listBatches(productId: UUID?) async throws -> [Batch] { [] }

    func savePriceEntry(_ entry: PriceEntry) async throws {}

    func listPriceHistory(productId: UUID) async throws -> [PriceEntry] { [] }

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
