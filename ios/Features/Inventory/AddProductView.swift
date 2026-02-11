import SwiftUI

struct AddProductView: View {
    let inventoryService: any InventoryServiceProtocol
    let initialName: String?
    let initialBarcode: String?
    let initialCategory: String?
    let initialUnit: UnitType?
    let initialQuantity: Double?
    let initialExpiryDate: Date?
    let onSaved: (Product) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var barcode = ""
    @State private var brand = ""
    @State private var category = ""
    @State private var unit: UnitType = .pcs
    @State private var disliked = false
    @State private var mayContainBones = false

    @State private var quantity = "1"
    @State private var location: InventoryLocation = .fridge
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()
    @State private var isOpened = false

    @State private var addPrice = false
    @State private var price = ""
    @State private var store: Store = .pyaterochka

    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        inventoryService: any InventoryServiceProtocol,
        initialName: String? = nil,
        initialBarcode: String? = nil,
        initialCategory: String? = nil,
        initialUnit: UnitType? = nil,
        initialQuantity: Double? = nil,
        initialExpiryDate: Date? = nil,
        onSaved: @escaping (Product) -> Void
    ) {
        self.inventoryService = inventoryService
        self.initialName = initialName
        self.initialBarcode = initialBarcode
        self.initialCategory = initialCategory
        self.initialUnit = initialUnit
        self.initialQuantity = initialQuantity
        self.initialExpiryDate = initialExpiryDate
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section("Товар") {
                TextField("Название", text: $name)
                TextField("Штрихкод (опционально)", text: $barcode)
                    .keyboardType(.numberPad)
                TextField("Бренд", text: $brand)
                TextField("Категория", text: $category)

                Picker("Единица", selection: $unit) {
                    ForEach(UnitType.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }

                Toggle("Нелюбимый продукт", isOn: $disliked)
                Toggle("Может быть с костями", isOn: $mayContainBones)
            }

            Section("Первая партия") {
                TextField("Количество", text: $quantity)
                    .keyboardType(.decimalPad)

                Picker("Зона хранения", selection: $location) {
                    ForEach(InventoryLocation.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }

                Toggle("Указать срок годности", isOn: $hasExpiryDate)
                if hasExpiryDate {
                    DatePicker("Срок годности", selection: $expiryDate, displayedComponents: [.date])
                }

                Toggle("Упаковка открыта", isOn: $isOpened)
            }

            Section("Цена (опционально)") {
                Toggle("Добавить цену", isOn: $addPrice)
                if addPrice {
                    TextField("Цена, ₽", text: $price)
                        .keyboardType(.decimalPad)
                    Picker("Магазин", selection: $store) {
                        ForEach(Store.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                }
            }
        }
        .navigationTitle("Новый товар")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Сохраняем..." : "Сохранить") {
                    Task {
                        await save()
                    }
                }
                .disabled(!canSave || isSaving)
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Не удалось сохранить")
        }
        .onAppear(perform: applyInitialValues)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyInitialValues() {
        if let initialName, name.isEmpty {
            name = initialName
        }

        if let initialBarcode, barcode.isEmpty {
            barcode = initialBarcode
        }

        if let initialCategory, category.isEmpty {
            category = initialCategory
        }

        if let initialUnit {
            unit = initialUnit
        }

        if let initialQuantity {
            quantity = initialQuantity.formatted()
        }

        if let initialExpiryDate {
            hasExpiryDate = true
            expiryDate = initialExpiryDate
        }
    }

    private func save() async {
        guard let quantityValue = Double(quantity.replacingOccurrences(of: ",", with: ".")), quantityValue > 0 else {
            errorMessage = "Количество должно быть больше нуля"
            return
        }

        if addPrice {
            guard let priceValue = Decimal(string: price.replacingOccurrences(of: ",", with: ".")), priceValue >= 0 else {
                errorMessage = "Введите корректную цену"
                return
            }
            _ = priceValue
        }

        isSaving = true
        defer { isSaving = false }

        let product = Product(
            barcode: barcode.emptyToNil,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.emptyToNil,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultUnit: unit,
            nutrition: .empty,
            disliked: disliked,
            mayContainBones: mayContainBones
        )

        let initialBatch = Batch(
            productId: product.id,
            location: location,
            quantity: quantityValue,
            unit: unit,
            expiryDate: hasExpiryDate ? expiryDate : nil,
            isOpened: isOpened
        )

        var initialPrice: PriceEntry?
        if addPrice, let priceValue = Decimal(string: price.replacingOccurrences(of: ",", with: ".")) {
            initialPrice = PriceEntry(productId: product.id, store: store, price: priceValue)
        }

        do {
            let useCase = CreateProductWithBatchUseCase(inventoryService: inventoryService)
            let savedProduct = try await useCase.execute(product: product, initialBatch: initialBatch, initialPrice: initialPrice)
            onSaved(savedProduct)
            dismiss()
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
