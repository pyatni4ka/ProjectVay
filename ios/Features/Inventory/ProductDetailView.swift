import SwiftUI

struct ProductDetailView: View {
    let productID: UUID
    let inventoryService: any InventoryServiceProtocol

    @Environment(\.dismiss) private var dismiss

    @State private var product: Product?
    @State private var batches: [Batch] = []
    @State private var priceHistory: [PriceEntry] = []
    @State private var isPresentingAddBatch = false
    @State private var errorMessage: String?

    @State private var editableName = ""
    @State private var editableBrand = ""
    @State private var editableCategory = ""
    @State private var editableDisliked = false
    @State private var editableBones = false
    @State private var newPriceText = ""
    @State private var newPriceStore: Store = .pyaterochka

    var body: some View {
        List {
            if let product {
                Section("Карточка") {
                    TextField("Название", text: $editableName)
                    TextField("Бренд", text: $editableBrand)
                    TextField("Категория", text: $editableCategory)
                    Toggle("Нелюбимый продукт", isOn: $editableDisliked)
                    Toggle("Может быть с костями", isOn: $editableBones)

                    Button("Сохранить изменения") {
                        Task { await saveProductChanges() }
                    }
                }

                Section("Партии") {
                    if batches.isEmpty {
                        Text("Партии не добавлены")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(batches) { batch in
                            NavigationLink {
                                EditBatchView(
                                    productID: product.id,
                                    batch: batch,
                                    inventoryService: inventoryService,
                                    onSaved: {
                                        Task { await loadData() }
                                    }
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(batch.quantity.formatted()) \(batch.unit.title)")
                                        .font(.headline)
                                    HStack {
                                        Text(batch.location.title)
                                        if let expiryDate = batch.expiryDate {
                                            Text("• \(expiryDate.formatted(date: .abbreviated, time: .omitted))")
                                        }
                                        Text(batch.isOpened ? "• открыто" : "• закрыто")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(batch.isOpened ? "Закрыть" : "Открыть") {
                                    Task { await toggleBatchOpened(batch) }
                                }
                                .tint(.blue)

                                Button("Списать", role: .destructive) {
                                    Task { await removeBatch(batch) }
                                }
                            }
                        }
                    }

                    Button("Добавить партию") {
                        isPresentingAddBatch = true
                    }
                }

                Section("Цены") {
                    if let latest = priceHistory.first {
                        HStack {
                            Text("Последняя цена")
                            Spacer()
                            Text("\(latest.price.formattedPriceRub) ₽ • \(latest.store.title)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Магазин", selection: $newPriceStore) {
                        ForEach(Store.allCases) { store in
                            Text(store.title).tag(store)
                        }
                    }

                    TextField("Новая цена, ₽", text: $newPriceText)
                        .keyboardType(.decimalPad)

                    Button("Добавить цену") {
                        Task { await addPriceEntry() }
                    }

                    if priceHistory.isEmpty {
                        Text("История цен пустая")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(priceHistory) { entry in
                            HStack {
                                Text(entry.store.title)
                                Spacer()
                                Text("\(entry.price.formattedPriceRub) ₽")
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Section {
                    Button("Удалить товар", role: .destructive) {
                        Task { await deleteProduct() }
                    }
                }
            }
        }
        .navigationTitle(product?.name ?? "Товар")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Обновить") {
                    Task { await loadData() }
                }
            }
        }
        .sheet(isPresented: $isPresentingAddBatch) {
            if let product {
                NavigationStack {
                    EditBatchView(
                        productID: product.id,
                        batch: nil,
                        inventoryService: inventoryService,
                        onSaved: {
                            Task { await loadData() }
                        }
                    )
                }
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
        .task {
            await loadData()
        }
    }

    private func saveProductChanges() async {
        guard var product else { return }
        let normalizedName = editableName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = editableCategory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedName.isEmpty, !normalizedCategory.isEmpty else {
            errorMessage = "Название и категория обязательны"
            return
        }

        product.name = normalizedName
        product.brand = editableBrand.emptyToNil
        product.category = normalizedCategory
        product.disliked = editableDisliked
        product.mayContainBones = editableBones

        do {
            self.product = try await inventoryService.updateProduct(product)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProduct() async {
        do {
            try await inventoryService.deleteProduct(id: productID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleBatchOpened(_ batch: Batch) async {
        do {
            var updated = batch
            updated.isOpened.toggle()
            _ = try await inventoryService.updateBatch(updated)
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeBatch(_ batch: Batch) async {
        do {
            try await inventoryService.removeBatch(id: batch.id)
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addPriceEntry() async {
        guard
            let product,
            let value = Decimal(string: newPriceText.replacingOccurrences(of: ",", with: ".")),
            value >= 0
        else {
            errorMessage = "Введите корректную цену"
            return
        }

        do {
            let entry = PriceEntry(
                productId: product.id,
                store: newPriceStore,
                price: value
            )
            try await inventoryService.savePriceEntry(entry)
            newPriceText = ""
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadData() async {
        do {
            let products = try await inventoryService.listProducts(location: nil, search: nil)
            guard let product = products.first(where: { $0.id == productID }) else {
                return
            }

            let batches = try await inventoryService.listBatches(productId: productID)
            let history = try await inventoryService.listPriceHistory(productId: productID)

            self.product = product
            self.batches = batches
            self.priceHistory = history
            editableName = product.name
            editableBrand = product.brand ?? ""
            editableCategory = product.category
            editableDisliked = product.disliked
            editableBones = product.mayContainBones
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var emptyToNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Decimal {
    var formattedPriceRub: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = ","
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "0"
    }
}
