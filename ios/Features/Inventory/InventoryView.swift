import SwiftUI

struct InventoryView: View {
    let inventoryService: any InventoryServiceProtocol
    let barcodeLookupService: BarcodeLookupService

    @State private var selectedLocation: InventoryLocation = .fridge
    @State private var searchText: String = ""
    @State private var snapshot = InventorySnapshot(products: [], expiringSoon: [])
    @State private var isPresentingAddProduct = false
    @State private var isPresentingScanner = false
    @State private var errorMessage: String?

    private var groupedProducts: [ProductWithBatches] {
        snapshot.products
    }

    var body: some View {
        List {
            if !snapshot.expiringSoon.isEmpty {
                Section("Срочно использовать") {
                    ForEach(snapshot.expiringSoon) { batch in
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(productName(for: batch.productId))
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
            }

            Section {
                ForEach(groupedProducts) { item in
                    NavigationLink {
                        ProductDetailView(productID: item.product.id, inventoryService: inventoryService)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.product.name)
                                    .font(.headline)
                                Spacer()
                                if let barcode = item.product.barcode {
                                    Text(barcode)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            ForEach(item.batches) { batch in
                                HStack {
                                    Text("\(Int(batch.quantity.rounded())) \(batch.unit.title)")
                                        .font(.subheadline)
                                    Spacer()
                                    Text(batch.location.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let expiryDate = batch.expiryDate {
                                        Text(expiryDate.formatted(date: .numeric, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } header: {
                Picker("Зона", selection: $selectedLocation) {
                    ForEach(InventoryLocation.allCases) { location in
                        Text(location.title).tag(location)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 6)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Инвентарь")
        .searchable(text: $searchText, prompt: "Поиск по товарам")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Сканировать") {
                    isPresentingScanner = true
                }

                Button("Добавить") {
                    isPresentingAddProduct = true
                }
            }
        }
        .sheet(isPresented: $isPresentingAddProduct) {
            NavigationStack {
                AddProductView(inventoryService: inventoryService) { _ in
                    Task { await reload() }
                }
            }
        }
        .sheet(isPresented: $isPresentingScanner) {
            NavigationStack {
                ScannerView(
                    inventoryService: inventoryService,
                    barcodeLookupService: barcodeLookupService,
                    onInventoryChanged: {
                        await reload()
                    }
                )
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
        .task(id: reloadKey) {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    private var reloadKey: String {
        "\(selectedLocation.rawValue)-\(searchText)"
    }

    private func productName(for productID: UUID) -> String {
        groupedProducts.first(where: { $0.product.id == productID })?.product.name ?? "Продукт"
    }

    private func reload() async {
        let useCase = LoadInventorySnapshotUseCase(inventoryService: inventoryService)
        do {
            snapshot = try await useCase.execute(location: selectedLocation, search: searchText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
