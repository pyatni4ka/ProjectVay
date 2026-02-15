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
    @State private var quantity = "1"
    @State private var hasExpiryDate = false
    @State private var expiryDate = Date()
    @State private var location: InventoryLocation = .fridge
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let categories = [
        "Мясо", "Рыба", "Молочное", "Овощи", "Фрукты",
        "Крупы", "Хлеб", "Напитки", "Замороженное",
        "Консервы", "Специи", "Снеки", "Другое"
    ]

    var body: some View {
        List {
            // Main Info
            Section {
                settingRow(icon: "tag.fill", color: .vayPrimary) {
                    TextField("Название продукта", text: $name)
                }

                settingRow(icon: "barcode", color: .vayInfo) {
                    TextField("Штрихкод (необязательно)", text: $barcode)
                        .keyboardType(.numberPad)
                }

                settingRow(icon: "building.2.fill", color: .vaySecondary) {
                    TextField("Бренд (необязательно)", text: $brand)
                }
            } header: {
                sectionHeader(icon: "info.circle", title: "Информация")
            }

            // Category
            Section {
                settingRow(icon: "folder.fill", color: .vayWarning) {
                    Picker("Категория", selection: $category) {
                        Text("Выберите").tag("")
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                sectionHeader(icon: "square.grid.2x2", title: "Категория")
            }

            // Batch Info
            Section {
                settingRow(icon: "number", color: .vayPrimary) {
                    TextField("Количество", text: $quantity)
                        .keyboardType(.decimalPad)
                }

                settingRow(icon: "scalemass", color: .vayInfo) {
                    Picker("Единица", selection: $unit) {
                        ForEach(UnitType.allCases) { u in
                            Text(u.title).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                settingRow(icon: "mappin.circle.fill", color: .vayFridge) {
                    Picker("Место", selection: $location) {
                        ForEach(InventoryLocation.allCases) { loc in
                            Label(loc.title, systemImage: loc.icon).tag(loc)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                sectionHeader(icon: "shippingbox", title: "Партия")
            }

            // Expiry
            Section {
                settingRow(icon: "calendar.badge.clock", color: .vayWarning) {
                    Toggle("Указать срок", isOn: $hasExpiryDate)
                }

                if hasExpiryDate {
                    DatePicker(
                        "Годен до",
                        selection: $expiryDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .tint(.vayPrimary)
                }
            } header: {
                sectionHeader(icon: "clock", title: "Срок годности")
            }

            // Save Button
            Section {
                Button {
                    Task { await saveProduct() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Добавить продукт")
                        }
                        Spacer()
                    }
                    .font(VayFont.label())
                    .foregroundStyle(.white)
                    .padding(.vertical, VaySpacing.sm)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: VayRadius.md)
                            .fill(name.isEmpty || category.isEmpty ? Color.gray : Color.vayPrimary)
                    )
                }
                .disabled(name.isEmpty || category.isEmpty || isSaving)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Новый продукт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            name = initialName ?? ""
            barcode = initialBarcode ?? ""
            category = initialCategory ?? ""
            if let initialUnit { unit = initialUnit }
            if let initialQuantity { quantity = initialQuantity.formatted() }
            if let initialExpiryDate {
                hasExpiryDate = true
                expiryDate = initialExpiryDate
            }
        }
    }

    // MARK: - Components

    private func settingRow<Content: View>(
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
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

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(title)
        }
        .font(VayFont.caption(12))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    // MARK: - Save

    private func saveProduct() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !category.isEmpty else {
            errorMessage = "Заполните название и категорию"
            return
        }

        guard let quantityValue = Double(quantity.replacingOccurrences(of: ",", with: ".")), quantityValue > 0 else {
            errorMessage = "Введите корректное количество"
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let product = Product(
                barcode: barcode.isEmpty ? nil : barcode,
                name: trimmedName,
                brand: brand.isEmpty ? nil : brand,
                category: category
            )

            let saved = try await inventoryService.createProduct(product)

            let batch = Batch(
                productId: saved.id,
                location: location,
                quantity: quantityValue,
                unit: unit,
                expiryDate: hasExpiryDate ? expiryDate : nil,
                isOpened: false
            )
            _ = try await inventoryService.addBatch(batch)

            VayHaptic.success()
            onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
