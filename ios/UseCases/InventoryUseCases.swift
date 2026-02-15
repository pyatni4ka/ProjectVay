import Foundation

struct ProductWithBatches: Identifiable {
    let product: Product
    let batches: [Batch]

    var id: UUID { product.id }
}

struct InventorySnapshot {
    let products: [ProductWithBatches]
    let expiringSoon: [Batch]
    let productByID: [UUID: Product]
}

struct LoadInventorySnapshotUseCase {
    let inventoryService: any InventoryServiceProtocol

    func execute(location: InventoryLocation?, search: String?) async throws -> InventorySnapshot {
        let products = try await inventoryService.listProducts(location: location, search: search)
        let allProducts = try await inventoryService.listProducts(location: nil, search: nil)

        var productWithBatches: [ProductWithBatches] = []
        for product in products {
            let batches = try await inventoryService.listBatches(productId: product.id)
            productWithBatches.append(ProductWithBatches(product: product, batches: batches))
        }

        let expiring = try await inventoryService.expiringBatches(horizonDays: 5)
        return InventorySnapshot(
            products: productWithBatches,
            expiringSoon: expiring,
            productByID: Dictionary(uniqueKeysWithValues: allProducts.map { ($0.id, $0) })
        )
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

struct RecipeWriteOffEntry: Identifiable {
    let id: String
    let ingredient: String
    let product: Product
    let batch: Batch
    let quantity: Double
    let unit: UnitType
}

struct RecipeWriteOffPlan {
    let entries: [RecipeWriteOffEntry]
    let missingIngredients: [String]

    var totalEntries: Int { entries.count }

    var summaryText: String {
        let missing = missingIngredients.isEmpty ? "без пропусков" : "без совпадений: \(missingIngredients.count)"
        return "Будет списано позиций: \(entries.count), \(missing)."
    }
}

struct RecipeWriteOffResult {
    let removedBatches: Int
    let updatedBatches: Int
}

struct BuildRecipeWriteOffPlanUseCase {
    let inventoryService: any InventoryServiceProtocol

    func execute(recipe: Recipe) async throws -> RecipeWriteOffPlan {
        let products = try await inventoryService.listProducts(location: nil, search: nil)
        let allBatches = try await inventoryService.listBatches(productId: nil)

        let batchesByProductID = Dictionary(grouping: allBatches, by: \.productId)
        var remainingByBatchID = Dictionary(uniqueKeysWithValues: allBatches.map { ($0.id, $0.quantity) })

        var entries: [RecipeWriteOffEntry] = []
        var missingIngredients: [String] = []

        for (index, ingredient) in recipe.ingredients.enumerated() {
            guard let product = bestMatchProduct(for: ingredient, products: products) else {
                missingIngredients.append(ingredient)
                continue
            }

            let sortedBatches = (batchesByProductID[product.id] ?? [])
                .sorted(by: batchSortComparator)
            guard let batch = chooseBatch(sortedBatches, remainingByBatchID: remainingByBatchID, preferredUnit: product.defaultUnit) else {
                missingIngredients.append(ingredient)
                continue
            }

            let remaining = remainingByBatchID[batch.id] ?? 0
            guard remaining > 0 else {
                missingIngredients.append(ingredient)
                continue
            }

            let requested = parseIngredientQuantity(ingredient, targetUnit: batch.unit) ?? defaultQuantity(for: batch.unit)
            let writeOffQuantity = min(remaining, max(0, requested))
            guard writeOffQuantity > 0 else {
                missingIngredients.append(ingredient)
                continue
            }

            remainingByBatchID[batch.id] = max(0, remaining - writeOffQuantity)
            entries.append(
                RecipeWriteOffEntry(
                    id: "\(batch.id.uuidString)-\(index)",
                    ingredient: ingredient,
                    product: product,
                    batch: batch,
                    quantity: writeOffQuantity,
                    unit: batch.unit
                )
            )
        }

        return RecipeWriteOffPlan(entries: entries, missingIngredients: missingIngredients)
    }

    private func batchSortComparator(_ lhs: Batch, _ rhs: Batch) -> Bool {
        switch (lhs.expiryDate, rhs.expiryDate) {
        case let (left?, right?):
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func chooseBatch(
        _ batches: [Batch],
        remainingByBatchID: [UUID: Double],
        preferredUnit: UnitType
    ) -> Batch? {
        let preferred = batches.first {
            $0.unit == preferredUnit && (remainingByBatchID[$0.id] ?? 0) > 0
        }
        if let preferred {
            return preferred
        }

        return batches.first {
            (remainingByBatchID[$0.id] ?? 0) > 0
        }
    }

    private func bestMatchProduct(for ingredient: String, products: [Product]) -> Product? {
        let normalizedIngredient = normalize(ingredient)
        guard !normalizedIngredient.isEmpty else { return nil }

        let ingredientTokens = tokens(normalizedIngredient)
        var best: (product: Product, score: Int)?

        for product in products {
            let normalizedProduct = normalize(product.name)
            guard !normalizedProduct.isEmpty else { continue }

            var score = 0
            if normalizedIngredient.contains(normalizedProduct) {
                score += 200 + normalizedProduct.count
            }
            if normalizedProduct.contains(normalizedIngredient) {
                score += 150 + normalizedIngredient.count
            }

            let productTokens = tokens(normalizedProduct)
            let tokenOverlap = ingredientTokens.intersection(productTokens).count
            score += tokenOverlap * 20

            if let brand = product.brand, !brand.isEmpty {
                let normalizedBrand = normalize(brand)
                if normalizedIngredient.contains(normalizedBrand) {
                    score += 30
                }
            }

            if score == 0 {
                continue
            }

            if let currentBest = best {
                if score > currentBest.score {
                    best = (product, score)
                }
            } else {
                best = (product, score)
            }
        }

        return best?.product
    }

    private func parseIngredientQuantity(_ ingredient: String, targetUnit: UnitType) -> Double? {
        let normalized = ingredient.lowercased().replacingOccurrences(of: ",", with: ".")
        let pattern = #"(\d+(?:\.\d+)?)\s*(кг|kg|г|гр|грамм|грамма|мл|ml|л|l|шт|pcs|pc)"#

        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: normalized, range: NSRange(location: 0, length: normalized.utf16.count)),
            let valueRange = Range(match.range(at: 1), in: normalized),
            let unitRange = Range(match.range(at: 2), in: normalized),
            let value = Double(normalized[valueRange])
        else {
            return nil
        }

        let rawUnit = String(normalized[unitRange])

        switch targetUnit {
        case .pcs:
            return rawUnit == "шт" || rawUnit == "pcs" || rawUnit == "pc" ? value : nil
        case .g:
            switch rawUnit {
            case "кг", "kg":
                return value * 1000
            case "г", "гр", "грамм", "грамма":
                return value
            default:
                return nil
            }
        case .ml:
            switch rawUnit {
            case "л", "l":
                return value * 1000
            case "мл", "ml":
                return value
            default:
                return nil
            }
        }
    }

    private func defaultQuantity(for unit: UnitType) -> Double {
        switch unit {
        case .pcs: return 1
        case .g: return 100
        case .ml: return 100
        }
    }

    private func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func tokens(_ text: String) -> Set<String> {
        Set(
            text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

struct ApplyRecipeWriteOffUseCase {
    let inventoryService: any InventoryServiceProtocol

    func execute(plan: RecipeWriteOffPlan) async throws -> RecipeWriteOffResult {
        let groupedByBatch = Dictionary(grouping: plan.entries, by: { $0.batch.id })
        let allBatches = try await inventoryService.listBatches(productId: nil)
        let batchByID = Dictionary(uniqueKeysWithValues: allBatches.map { ($0.id, $0) })

        var removedBatches = 0
        var updatedBatches = 0

        for (batchID, entries) in groupedByBatch {
            guard let batch = batchByID[batchID] else { continue }
            let quantityToWriteOff = entries.reduce(0) { $0 + $1.quantity }
            if quantityToWriteOff <= 0 {
                continue
            }

            try await inventoryService.removeBatch(
                id: batch.id,
                quantity: quantityToWriteOff,
                intent: .consumed,
                note: "Съедено по рецепту"
            )

            if batch.quantity <= quantityToWriteOff + 0.000_001 {
                removedBatches += 1
            } else {
                updatedBatches += 1
            }
        }

        return RecipeWriteOffResult(
            removedBatches: removedBatches,
            updatedBatches: updatedBatches
        )
    }
}
