import SwiftUI

struct ProductDetailView: View {
    let productID: UUID
    let inventoryService: any InventoryServiceProtocol

    @Environment(\.dismiss) private var dismiss

    @State private var product: Product?
    @State private var batches: [Batch] = []
    @State private var priceHistory: [PriceEntry] = []
    @State private var inventoryEvents: [InventoryEvent] = []
    @State private var isPresentingAddBatch = false
    @State private var errorMessage: String?

    @State private var editableName = ""
    @State private var editableBrand = ""
    @State private var editableCategory = ""
    @State private var editableDisliked = false
    @State private var editableBones = false
    @State private var newPriceText = ""
    @State private var newPriceStore: Store = .pyaterochka

    @State private var showDeleteProductConfirm = false
    @State private var batchToRemove: Batch?
    @State private var showRemoveBatchConfirm = false

    var body: some View {
        List {
            if let product {
                // Product Card Section
                Section {
                    settingRow(icon: "tag.fill", color: .vayPrimary) {
                        TextField("Название", text: $editableName)
                    }
                    settingRow(icon: "building.2.fill", color: .vaySecondary) {
                        TextField("Бренд", text: $editableBrand)
                    }
                    settingRow(icon: "folder.fill", color: .vayWarning) {
                        TextField("Категория", text: $editableCategory)
                    }
                    settingRow(icon: "hand.thumbsdown.fill", color: .vayDanger) {
                        Toggle("Нелюбимый", isOn: $editableDisliked)
                    }
                    settingRow(icon: "fish.fill", color: .vayInfo) {
                        Toggle("С костями", isOn: $editableBones)
                    }

                    Button {
                        Task { await saveProductChanges() }
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                            Text("Сохранить")
                            Spacer()
                        }
                        .font(VayFont.label())
                        .foregroundStyle(Color.vayPrimary)
                    }
                } header: {
                    sectionHeader(icon: "info.circle", title: "Карточка")
                }

                // Batches Section
                Section {
                    if batches.isEmpty {
                        HStack(spacing: VaySpacing.sm) {
                            Image(systemName: "shippingbox")
                                .foregroundStyle(.tertiary)
                            Text("Партии не добавлены")
                                .foregroundStyle(.secondary)
                                .font(VayFont.body(14))
                        }
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
                                batchRow(batch)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(batch.isOpened ? "Закрыть" : "Открыть") {
                                    Task { await toggleBatchOpened(batch) }
                                }
                                .tint(.vayInfo)

                                Button("Списать", role: .destructive) {
                                    batchToRemove = batch
                                    showRemoveBatchConfirm = true
                                }
                            }
                            .vayAccessibilityLabel(
                                batchAccessibilityLabel(batch),
                                hint: "Нажмите для редактирования. Смахните для действий."
                            )
                        }
                    }

                    Button {
                        isPresentingAddBatch = true
                    } label: {
                        HStack(spacing: VaySpacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.vayPrimary)
                            Text("Добавить партию")
                                .font(VayFont.label(14))
                                .foregroundStyle(Color.vayPrimary)
                        }
                    }
                } header: {
                    sectionHeader(icon: "shippingbox", title: "Партии (\(batches.count))")
                }

                // Prices Section
                Section {
                    if let latest = priceHistory.first {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Последняя цена")
                                    .font(VayFont.caption(12))
                                    .foregroundStyle(.secondary)
                                Text("\(latest.price.formattedPriceRub) ₽")
                                    .font(VayFont.title(20))
                                    .foregroundStyle(Color.vayWarning)
                            }
                            Spacer()
                            Text(latest.store.title)
                                .font(VayFont.caption(12))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, VaySpacing.sm)
                                .padding(.vertical, VaySpacing.xs)
                                .background(Color.vayWarning.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }

                    settingRow(icon: "storefront.fill", color: .vaySecondary) {
                        Picker("Магазин", selection: $newPriceStore) {
                            ForEach(Store.allCases) { store in
                                Text(store.title).tag(store)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    settingRow(icon: "rublesign.circle.fill", color: .vayWarning) {
                        TextField("Новая цена, ₽", text: $newPriceText)
                            .keyboardType(.decimalPad)
                    }

                    Button {
                        Task { await addPriceEntry() }
                    } label: {
                        HStack(spacing: VaySpacing.sm) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.vayWarning)
                            Text("Добавить цену")
                                .font(VayFont.label(14))
                                .foregroundStyle(Color.vayWarning)
                        }
                    }

                    ForEach(priceHistory) { entry in
                        HStack {
                            Text(entry.store.title)
                                .font(VayFont.body(14))
                            Spacer()
                            Text("\(entry.price.formattedPriceRub) ₽")
                                .font(VayFont.label(14))
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(VayFont.caption(11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    sectionHeader(icon: "rublesign", title: "Цены")
                }

                // History Section
                Section {
                    if inventoryEvents.isEmpty {
                        HStack(spacing: VaySpacing.sm) {
                            Image(systemName: "clock")
                                .foregroundStyle(.tertiary)
                            Text("История пока пустая")
                                .foregroundStyle(.secondary)
                                .font(VayFont.body(14))
                        }
                    } else {
                        ForEach(inventoryEvents.prefix(20)) { event in
                            HStack(spacing: VaySpacing.md) {
                                Image(systemName: eventIcon(event.type))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(eventColor(event.type))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(eventTitle(event.type))
                                        .font(VayFont.body(14))
                                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(VayFont.caption(11))
                                        .foregroundStyle(.tertiary)
                                    if let note = event.note, !note.isEmpty {
                                        Text(note)
                                            .font(VayFont.caption(11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader(icon: "clock.arrow.circlepath", title: "История")
                }

                // Delete
                Section {
                    Button(role: .destructive) {
                        showDeleteProductConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "trash.fill")
                            Text("Удалить товар")
                            Spacer()
                        }
                        .font(VayFont.label())
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(product?.name ?? "Товар")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
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
        .confirmationDialog(
            "Удалить товар?",
            isPresented: $showDeleteProductConfirm
        ) {
            Button("Удалить навсегда", role: .destructive) {
                Task { await deleteProduct() }
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Все партии, цены и история будут удалены безвозвратно.")
        }
        .confirmationDialog(
            "Списать партию?",
            isPresented: $showRemoveBatchConfirm,
            presenting: batchToRemove
        ) { batch in
            Button("Списать", role: .destructive) {
                Task { await removeBatch(batch) }
            }
            Button("Отмена", role: .cancel) { }
        } message: { batch in
            Text("\(batch.quantity.formatted()) \(batch.unit.title) будет списано.")
        }
    }

    // MARK: - Components

    private func batchRow(_ batch: Batch) -> some View {
        HStack(spacing: VaySpacing.md) {
            Image(systemName: batch.location.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(batch.location.color)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(batch.quantity.formatted()) \(batch.unit.title)")
                    .font(VayFont.label(14))

                HStack(spacing: VaySpacing.xs) {
                    Text(batch.location.title)
                        .font(VayFont.caption(11))
                        .foregroundStyle(.secondary)

                    if let expiryDate = batch.expiryDate {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(expiryDate.formatted(date: .abbreviated, time: .omitted))
                            .font(VayFont.caption(11))
                            .foregroundStyle(expiryDate.expiryColor)
                    }

                    if batch.isOpened {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Image(systemName: "seal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.vayWarning)
                    }
                }
            }
        }
    }

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

    // MARK: - Accessibility

    private func batchAccessibilityLabel(_ batch: Batch) -> String {
        var parts = [
            "\(batch.quantity.formatted()) \(batch.unit.title)",
            batch.location.title
        ]
        if let exp = batch.expiryDate {
            let days = exp.daysUntilExpiry
            if days < 0 { parts.append("просрочено") }
            else if days == 0 { parts.append("истекает сегодня") }
            else { parts.append("годен \(days) дн.") }
        }
        if batch.isOpened { parts.append("открыта") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Event Helpers

    private func eventIcon(_ type: InventoryEvent.EventType) -> String {
        switch type {
        case .add: return "plus"
        case .remove: return "minus"
        case .adjust: return "arrow.up.arrow.down"
        case .open: return "seal"
        case .close: return "lock"
        }
    }

    private func eventColor(_ type: InventoryEvent.EventType) -> Color {
        switch type {
        case .add: return .vaySuccess
        case .remove: return .vayDanger
        case .adjust: return .vayInfo
        case .open: return .vayWarning
        case .close: return .vaySecondary
        }
    }

    private func eventTitle(_ type: InventoryEvent.EventType) -> String {
        switch type {
        case .add: return "Добавление"
        case .remove: return "Списание"
        case .adjust: return "Корректировка"
        case .open: return "Открыто"
        case .close: return "Закрыто"
        }
    }

    // MARK: - Logic (preserved)

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
            VayHaptic.success()
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
            VayHaptic.impact(.light)
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeBatch(_ batch: Batch) async {
        do {
            try await inventoryService.removeBatch(
                id: batch.id,
                quantity: nil,
                intent: .writeOff,
                note: "Списано из карточки товара"
            )
            VayHaptic.impact(.medium)
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
            VayHaptic.success()
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
            let events = try await inventoryService.listEvents(productId: productID)

            self.product = product
            self.batches = batches
            self.priceHistory = history
            self.inventoryEvents = events
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
