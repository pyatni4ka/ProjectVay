import SwiftUI

struct EditBatchView: View {
    let productID: UUID
    let batch: Batch?
    let inventoryService: any InventoryServiceProtocol
    let onSaved: () -> Void
    let initialExpiryDate: Date?
    let initialQuantity: Double?
    let initialUnit: UnitType?

    @Environment(\.dismiss) private var dismiss

    @State private var location: InventoryLocation = .fridge
    @State private var quantity: String = "1"
    @State private var unit: UnitType = .pcs
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()
    @State private var isOpened = false
    @State private var errorMessage: String?

    init(
        productID: UUID,
        batch: Batch?,
        inventoryService: any InventoryServiceProtocol,
        onSaved: @escaping () -> Void,
        initialExpiryDate: Date? = nil,
        initialQuantity: Double? = nil,
        initialUnit: UnitType? = nil
    ) {
        self.productID = productID
        self.batch = batch
        self.inventoryService = inventoryService
        self.onSaved = onSaved
        self.initialExpiryDate = initialExpiryDate
        self.initialQuantity = initialQuantity
        self.initialUnit = initialUnit
    }

    var body: some View {
        Form {
            Section("Партия") {
                Picker("Зона хранения", selection: $location) {
                    ForEach(InventoryLocation.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }

                TextField("Количество", text: $quantity)
                    .keyboardType(.decimalPad)

                Picker("Единица", selection: $unit) {
                    ForEach(UnitType.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }

                Toggle("Указать срок годности", isOn: $hasExpiryDate)
                if hasExpiryDate {
                    DatePicker("Срок годности", selection: $expiryDate, displayedComponents: [.date])
                }

                Toggle("Упаковка открыта", isOn: $isOpened)
            }

            if batch != nil {
                Section {
                    Button("Удалить партию", role: .destructive) {
                        Task { await deleteBatch() }
                    }
                }
            }
        }
        .navigationTitle(batch == nil ? "Новая партия" : "Редактирование")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    Task { await save() }
                }
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
        .onAppear(perform: loadFromInput)
    }

    private func loadFromInput() {
        guard let batch else {
            if let initialQuantity {
                quantity = initialQuantity.formatted()
            }

            if let initialUnit {
                unit = initialUnit
            }

            if let initialExpiryDate {
                hasExpiryDate = true
                expiryDate = initialExpiryDate
            }
            return
        }

        location = batch.location
        quantity = batch.quantity.formatted()
        unit = batch.unit
        hasExpiryDate = batch.expiryDate != nil
        expiryDate = batch.expiryDate ?? Date()
        isOpened = batch.isOpened
    }

    private func save() async {
        guard let quantityValue = Double(quantity.replacingOccurrences(of: ",", with: ".")), quantityValue > 0 else {
            errorMessage = "Введите корректное количество"
            return
        }

        do {
            if let existingBatch = batch {
                var updated = existingBatch
                updated.location = location
                updated.quantity = quantityValue
                updated.unit = unit
                updated.expiryDate = hasExpiryDate ? expiryDate : nil
                updated.isOpened = isOpened
                _ = try await inventoryService.updateBatch(updated)
            } else {
                let newBatch = Batch(
                    productId: productID,
                    location: location,
                    quantity: quantityValue,
                    unit: unit,
                    expiryDate: hasExpiryDate ? expiryDate : nil,
                    isOpened: isOpened
                )
                _ = try await inventoryService.addBatch(newBatch)
            }

            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBatch() async {
        guard let batch else { return }

        do {
            try await inventoryService.removeBatch(id: batch.id)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
