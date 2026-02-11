import SwiftUI

struct HomeView: View {
    let inventoryService: any InventoryServiceProtocol

    @State private var expiringSoon: [Batch] = []
    @State private var productsByID: [UUID: Product] = [:]
    @State private var searchText = ""

    var body: some View {
        List {
            Section("Срочно использовать") {
                if expiringSoon.isEmpty {
                    Text("Нет продуктов с близким сроком")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(expiringSoon) { batch in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(productsByID[batch.productId]?.name ?? "Продукт")
                                .font(.headline)
                            if let expiryDate = batch.expiryDate {
                                Text("Срок: \(expiryDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Рекомендации") {
                NavigationLink("Омлет с овощами") {
                    RecipeView()
                }
                NavigationLink("Творожная запеканка") {
                    RecipeView()
                }
            }
        }
        .navigationTitle("Что приготовить")
        .searchable(text: $searchText, prompt: "Поиск рецептов")
        .task {
            await loadUrgentProducts()
        }
    }

    private func loadUrgentProducts() async {
        do {
            let expiring = try await inventoryService.expiringBatches(horizonDays: 5)
            let products = try await inventoryService.listProducts(location: nil, search: nil)

            expiringSoon = expiring
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        } catch {
            expiringSoon = []
            productsByID = [:]
        }
    }
}
