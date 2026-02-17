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
    @State private var isSaving = false
    @State private var showDeleteConfirm = false

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
        List {
            Section {
                iconRow("mappin.circle.fill", .vayFridge) {
                    Picker("Зона", selection: $location) {
                        ForEach(InventoryLocation.allCases) { v in
                            Label(v.title, systemImage: v.icon).tag(v)
                        }
                    }
                    .pickerStyle(.menu)
                }
                iconRow("number", .vayPrimary) {
                    TextField("Количество", text: $quantity)
                        .keyboardType(.decimalPad)
                }
                iconRow("scalemass", .vayInfo) {
                    Picker("Ед.", selection: $unit) {
                        ForEach(UnitType.allCases) { v in
                            Text(v.title).tag(v)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                secHead("shippingbox", "Партия")
            }

            Section {
                iconRow("calendar.badge.clock", .vayWarning) {
                    Toggle("Указать срок", isOn: $hasExpiryDate)
                }
                if hasExpiryDate {
                    DatePicker("Годен до", selection: $expiryDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .tint(.vayPrimary)
                }
                iconRow("seal.fill", .vaySecondary) {
                    Toggle("Открыта", isOn: $isOpened)
                }
            } header: {
                secHead("clock", "Срок и статус")
            }

            if batch != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "trash.fill")
                            Text("Удалить партию")
                            Spacer()
                        }
                        .font(VayFont.label())
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .navigationTitle(batch == nil ? "Новая партия" : "Редактирование")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() }
                    else { Text("Сохранить").fontWeight(.semibold) }
                }
                .disabled(isSaving)
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: loadFromInput)
        .confirmationDialog(
            "Удалить партию?",
            isPresented: $showDeleteConfirm
        ) {
            Button("Удалить", role: .destructive) {
                Task { await deleteBatch() }
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Партия будет удалена безвозвратно.")
        }
    }

    private func iconRow<C: View>(_ icon: String, _ color: Color, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            content()
        }
    }

    private func secHead(_ icon: String, _ title: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: icon).font(.system(size: 11))
            Text(title)
        }
        .font(VayFont.caption(12))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    private func loadFromInput() {
        guard let batch else {
            if let initialQuantity { quantity = initialQuantity.formatted() }
            if let initialUnit { unit = initialUnit }
            if let initialExpiryDate { hasExpiryDate = true; expiryDate = initialExpiryDate }
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
        guard let qv = Double(quantity.replacingOccurrences(of: ",", with: ".")), qv > 0 else {
            errorMessage = "Введите корректное количество"; return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if let existing = batch {
                var u = existing
                u.location = location; u.quantity = qv; u.unit = unit
                u.expiryDate = hasExpiryDate ? expiryDate : nil; u.isOpened = isOpened
                _ = try await inventoryService.updateBatch(u)
            } else {
                _ = try await inventoryService.addBatch(Batch(
                    productId: productID, location: location, quantity: qv,
                    unit: unit, expiryDate: hasExpiryDate ? expiryDate : nil, isOpened: isOpened
                ))
            }
            VayHaptic.success(); onSaved(); dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteBatch() async {
        guard let batch else { return }
        do {
            try await inventoryService.removeBatch(
                id: batch.id,
                quantity: nil,
                intent: .writeOff,
                note: "Списано вручную"
            )
            onSaved()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
