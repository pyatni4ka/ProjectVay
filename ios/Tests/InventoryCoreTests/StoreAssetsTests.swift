import XCTest
@testable import InventoryCore

final class StoreAssetsTests: XCTestCase {
    func testStoreAssetMapping() {
        let storesWithAssets: [Store] = [
            .pyaterochka, .perekrestok, .magnit, .lenta, .okay,
            .vkusvill, .metro, .dixy, .fixPrice, .samokat, .yandexLavka,
            .auchan, .ozonfresh
        ]

        for store in storesWithAssets {
            XCTAssertNotNil(store.assetName, "Store \(store.title) should have an asset name")
        }

        let storesWithoutAssets: [Store] = [.chizhik, .custom]
        for store in storesWithoutAssets {
            XCTAssertNil(store.assetName, "Store \(store.title) should NOT have an asset name yet (or fallback to nil)")
        }
    }
}
