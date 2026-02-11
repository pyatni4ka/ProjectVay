import Foundation

struct ProductWithBatches: Identifiable {
    let product: Product
    let batches: [Batch]

    var id: UUID { product.id }
}

struct InventorySnapshot {
    let products: [ProductWithBatches]
    let expiringSoon: [Batch]
}

struct LoadInventorySnapshotUseCase {
    let inventoryService: any InventoryServiceProtocol

    func execute(location: InventoryLocation?, search: String?) async throws -> InventorySnapshot {
        let products = try await inventoryService.listProducts(location: location, search: search)

        var productWithBatches: [ProductWithBatches] = []
        for product in products {
            let batches = try await inventoryService.listBatches(productId: product.id)
            productWithBatches.append(ProductWithBatches(product: product, batches: batches))
        }

        let expiring = try await inventoryService.expiringBatches(horizonDays: 5)
        return InventorySnapshot(products: productWithBatches, expiringSoon: expiring)
    }
}

struct CreateProductWithBatchUseCase {
    let inventoryService: any InventoryServiceProtocol

    func execute(product: Product, initialBatch: Batch?, initialPrice: PriceEntry?) async throws -> Product {
        let storedProduct = try await inventoryService.createProduct(product)

        if var batch = initialBatch {
            batch = Batch(
                id: batch.id,
                productId: storedProduct.id,
                location: batch.location,
                quantity: batch.quantity,
                unit: batch.unit,
                expiryDate: batch.expiryDate,
                isOpened: batch.isOpened,
                createdAt: batch.createdAt,
                updatedAt: batch.updatedAt
            )
            _ = try await inventoryService.addBatch(batch)
        }

        if var initialPrice {
            initialPrice = PriceEntry(
                id: initialPrice.id,
                productId: storedProduct.id,
                store: initialPrice.store,
                price: initialPrice.price,
                currency: initialPrice.currency,
                date: initialPrice.date
            )
            try await inventoryService.savePriceEntry(initialPrice)
        }

        return storedProduct
    }
}
