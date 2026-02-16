import SwiftUI

struct InventoryView: View {
    let inventoryService: any InventoryServiceProtocol
    var onOpenScanner: () -> Void = {}
    var onOpenReceiptScan: () -> Void = {}

    @State private var products: [Product] = []
    @State private var batches: [Batch] = []
    @State private var selectedLocation: InventoryLocation? = nil
    @State private var searchText = ""
    @State private var showAddProduct = false
    @State private var isLoading = true
    @State private var sortBy: SortOption = .name
    @State private var productToDelete: Product?
    @State private var showDeleteConfirm = false
    @State private var successMessage: String?

    enum SortOption: String, CaseIterable, Identifiable {
        case name, expiry, quantity
        var id: String { rawValue }
        var title: String {
            switch self {
            case .name: return "Имя"
            case .expiry: return "Срок"
            case .quantity: return "Кол-во"
            }
        }
        var icon: String {
            switch self {
            case .name: return "textformat"
            case .expiry: return "clock"
            case .quantity: return "number"
            }
        }
    }

    var body: some View {
        List {
            Section {
                // Inline search bar
                HStack(spacing: VaySpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Поиск продуктов...", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                locationFilter
                sortPicker
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            if isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
                .listRowBackground(Color.clear)
            } else if filteredProducts.isEmpty {
                Section {
                    emptyState
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredProducts) { product in
                        let productBatches = batches.filter { $0.productId == product.id }
                        let nearestExpiry = productBatches.compactMap(\.expiryDate).min()
                        let totalQty = productBatches.reduce(0.0) { $0 + $1.quantity }
                        let mainUnit = productBatches.first?.unit ?? .pcs

                        NavigationLink {
                            ProductDetailView(
                                productID: product.id,
                                inventoryService: inventoryService
                            )
                        } label: {
                            productCard(product)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                productToDelete = product
                                showDeleteConfirm = true
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }

                            Button {
                                Task { await writeOffProduct(product) }
                            } label: {
                                Label("Списать", systemImage: "minus.circle")
                            }
                            .tint(.vayWarning)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                Task { await consumeProduct(product) }
                            } label: {
                                Label("Съедено", systemImage: "checkmark.circle")
                            }
                            .tint(.vaySuccess)
                        }
                        .vayAccessibilityLabel(
                            accessibilityLabel(for: product, qty: totalQty, unit: mainUnit, expiry: nearestExpiry),
                            hint: "Нажмите для просмотра деталей. Смахните для действий."
                        )
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Bottom spacer for tab bar
            Section {
                Color.clear.frame(height: VayLayout.tabBarOverlayInset)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.vayBackground)
        .navigationTitle("Запасы")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: onOpenScanner) {
                        Label("Сканировать штрихкод", systemImage: "barcode.viewfinder")
                    }

                    Button(action: onOpenReceiptScan) {
                        Label("Сканировать чек", systemImage: "doc.text.viewfinder")
                    }

                    Button {
                        showAddProduct = true
                    } label: {
                        Label("Добавить вручную", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.vayPrimary)
                }
                .vayAccessibilityLabel("Действия с запасами", hint: "Сканировать штрихкод, чек или добавить вручную")
            }
        }
        .sheet(isPresented: $showAddProduct) {
            NavigationStack {
                AddProductView(
                    inventoryService: inventoryService,
                    initialName: nil,
                    initialBarcode: nil,
                    initialCategory: nil,
                    initialUnit: nil,
                    initialQuantity: nil,
                    initialExpiryDate: nil,
                    onSaved: { _ in
                        Task { await loadData() }
                    }
                )
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .confirmationDialog(
            "Удалить продукт?",
            isPresented: $showDeleteConfirm,
            presenting: productToDelete
        ) { product in
            Button("Удалить \(product.name)", role: .destructive) {
                Task { await deleteProduct(product) }
            }
            Button("Отмена", role: .cancel) { }
        } message: { product in
            Text("Все партии и история \(product.name) будут удалены. Это действие нельзя отменить.")
        }
        .overlay(alignment: .top) {
            if let msg = successMessage {
                Text(msg)
                    .font(VayFont.label(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, VaySpacing.lg)
                    .padding(.vertical, VaySpacing.sm)
                    .background(Color.vaySuccess)
                    .clipShape(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, VaySpacing.md)
            }
        }
    }

    private var emptyState: some View {
        Group {
            if searchText.isEmpty, products.isEmpty {
                EmptyStateView(
                    icon: "barcode.viewfinder",
                    title: "Инвентарь пуст",
                    subtitle: "Сканируйте первый товар, чтобы начать отслеживание запасов.",
                    actionTitle: "Сканировать первый товар",
                    action: onOpenScanner
                )
            } else if !searchText.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Ничего не найдено",
                    subtitle: "По запросу «\(searchText)» совпадений нет. Попробуйте другое название или сбросьте поиск.",
                    actionTitle: "Сбросить поиск",
                    action: { searchText = "" }
                )
            } else {
                EmptyStateView(
                    icon: selectedLocation?.icon ?? "tray",
                    title: "В этой зоне пока пусто",
                    subtitle: "Поменяйте фильтр или добавьте продукты в выбранную зону.",
                    actionTitle: "Снять фильтр",
                    action: { selectedLocation = nil }
                )
            }
        }
    }

    private var locationFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VaySpacing.sm) {
                filterChip(title: "Все", icon: "tray.full", isSelected: selectedLocation == nil) {
                    withAnimation(VayAnimation.springSnappy) { selectedLocation = nil }
                    VayHaptic.selection()
                }

                ForEach(InventoryLocation.allCases) { location in
                    filterChip(
                        title: location.title,
                        icon: location.icon,
                        isSelected: selectedLocation == location,
                        color: location.color
                    ) {
                        withAnimation(VayAnimation.springSnappy) {
                            selectedLocation = selectedLocation == location ? nil : location
                        }
                        VayHaptic.selection()
                    }
                }
            }
        }
        .vayAccessibilityLabel("Фильтр по зонам хранения")
    }

    private func filterChip(
        title: String,
        icon: String,
        isSelected: Bool,
        color: Color = .vayPrimary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: VaySpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(VayFont.label(13))
            }
            .padding(.horizontal, VaySpacing.md)
            .padding(.vertical, VaySpacing.sm)
            .background(isSelected ? color.opacity(0.15) : Color.vayCardBackground)
            .foregroundStyle(isSelected ? color : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? color.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .vayAccessibilityLabel(
            "\(title)",
            hint: isSelected ? "Фильтр активен" : "Нажмите чтобы выбрать"
        )
    }

    private var sortPicker: some View {
        HStack {
            Text("\(filteredProducts.count) продуктов")
                .font(VayFont.caption(12))
                .foregroundStyle(.tertiary)

            Spacer()

            Menu {
                ForEach(SortOption.allCases) { option in
                    Button {
                        withAnimation(VayAnimation.springSnappy) { sortBy = option }
                    } label: {
                        Label(option.title, systemImage: option.icon)
                    }
                }
            } label: {
                HStack(spacing: VaySpacing.xs) {
                    Image(systemName: sortBy.icon)
                    Text(sortBy.title)
                }
                .font(VayFont.caption(12))
                .foregroundStyle(.secondary)
            }
            .vayAccessibilityLabel("Сортировка: \(sortBy.title)", hint: "Открывает меню сортировки")
        }
        .padding(.horizontal, VaySpacing.xs)
    }



    private func productCard(_ product: Product) -> some View {
        let productBatches = batches.filter { $0.productId == product.id }
        let nearestExpiry = productBatches.compactMap(\.expiryDate).min()
        let totalQty = productBatches.reduce(0.0) { $0 + $1.quantity }
        let mainUnit = productBatches.first?.unit ?? .pcs
        let locations = Set(productBatches.map(\.location))

        return HStack(spacing: VaySpacing.md) {
            VStack {
                Image(systemName: iconForCategory(product.category))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.vayPrimary)
            }
            .frame(width: 44, height: 44)
            .background(Color.vayPrimary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: VaySpacing.xs) {
                HStack {
                    Text(product.name)
                        .font(VayFont.label(15))
                        .lineLimit(1)

                    if product.disliked {
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.vayWarning)
                    }
                }

                HStack(spacing: VaySpacing.sm) {
                    HStack(spacing: 2) {
                        ForEach(Array(locations), id: \.self) { loc in
                            Image(systemName: loc.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(loc.color)
                        }
                    }

                    Text(product.category)
                        .font(VayFont.caption(11))
                        .foregroundStyle(.tertiary)

                    if product.nutrition.kcal != nil ||
                        product.nutrition.protein != nil ||
                        product.nutrition.fat != nil ||
                        product.nutrition.carbs != nil {
                        let nutrition = product.nutrition
                        InlineMacros(
                            kcal: nutrition.kcal,
                            protein: nutrition.protein,
                            fat: nutrition.fat,
                            carbs: nutrition.carbs
                        )
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: VaySpacing.xs) {
                Text("\(totalQty.formatted()) \(mainUnit.title)")
                    .font(VayFont.label(13))
                    .foregroundStyle(.primary)

                if let expiry = nearestExpiry {
                    Text(expiry.expiryLabel)
                        .font(VayFont.caption(10))
                        .foregroundStyle(expiry.expiryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(expiry.expiryColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(VaySpacing.md)
        .background(Color.vayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
        .vayShadow(.subtle)
    }

    private var filteredProducts: [Product] {
        var result = products

        if let location = selectedLocation {
            let productIds = Set(batches.filter { $0.location == location }.map(\.productId))
            result = result.filter { productIds.contains($0.id) }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.category.lowercased().contains(query) ||
                ($0.brand?.lowercased().contains(query) ?? false)
            }
        }

        switch sortBy {
        case .name:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .expiry:
            result.sort { a, b in
                let aExpiry = batches.filter { $0.productId == a.id }.compactMap(\.expiryDate).min() ?? .distantFuture
                let bExpiry = batches.filter { $0.productId == b.id }.compactMap(\.expiryDate).min() ?? .distantFuture
                return aExpiry < bExpiry
            }
        case .quantity:
            result.sort { a, b in
                let aQty = batches.filter { $0.productId == a.id }.reduce(0.0) { $0 + $1.quantity }
                let bQty = batches.filter { $0.productId == b.id }.reduce(0.0) { $0 + $1.quantity }
                return aQty > bQty
            }
        }

        return result
    }

    private func iconForCategory(_ category: String) -> String {
        let lower = category.lowercased()
        if lower.contains("мясо") || lower.contains("птиц") || lower.contains("рыб") { return "fish" }
        if lower.contains("молоч") || lower.contains("сыр") { return "cup.and.saucer" }
        if lower.contains("овощ") || lower.contains("фрукт") { return "carrot" }
        if lower.contains("круп") || lower.contains("макарон") || lower.contains("хлеб") { return "basket" }
        if lower.contains("напит") { return "waterbottle" }
        if lower.contains("заморож") { return "snowflake" }
        if lower.contains("конс") { return "takeoutbag.and.cup.and.straw" }
        if lower.contains("специ") || lower.contains("соус") { return "flame" }
        return "fork.knife"
    }

    private func loadData() async {
        do {
            products = try await inventoryService.listProducts(location: nil, search: nil)
            batches = try await inventoryService.listBatches(productId: nil)
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func deleteProduct(_ product: Product) async {
        do {
            try await inventoryService.deleteProduct(id: product.id)
            VayHaptic.success()
            showSuccess("\(product.name) удалён")
            await loadData()
        } catch {
            VayHaptic.error()
        }
    }

    private func writeOffProduct(_ product: Product) async {
        let productBatches = batches.filter { $0.productId == product.id }
        guard let firstBatch = productBatches.first else { return }
        do {
            try await inventoryService.removeBatch(
                id: firstBatch.id,
                quantity: nil,
                intent: .writeOff,
                note: "Списано из списка запасов"
            )
            VayHaptic.impact(.medium)
            showSuccess("\(product.name) списан")
            await loadData()
        } catch {
            VayHaptic.error()
        }
    }

    private func consumeProduct(_ product: Product) async {
        let productBatches = batches.filter { $0.productId == product.id }
        guard let firstBatch = productBatches.first else { return }
        do {
            try await inventoryService.removeBatch(
                id: firstBatch.id,
                quantity: nil,
                intent: .consumed,
                note: "Съедено"
            )
            VayHaptic.success()
            showSuccess("👍 \(product.name) съедено")
            await loadData()
        } catch {
            VayHaptic.error()
        }
    }

    private func showSuccess(_ message: String) {
        withAnimation(VayAnimation.springSnappy) {
            successMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(VayAnimation.springSmooth) {
                successMessage = nil
            }
        }
    }

    private func accessibilityLabel(for product: Product, qty: Double, unit: UnitType, expiry: Date?) -> String {
        var parts = [product.name, "\(qty.formatted()) \(unit.title)"]
        if let expiry {
            let days = expiry.daysUntilExpiry
            if days < 0 {
                parts.append("просрочен")
            } else if days == 0 {
                parts.append("истекает сегодня")
            } else if days == 1 {
                parts.append("истекает завтра")
            } else {
                parts.append("годен \(days) дней")
            }
        }
        return parts.joined(separator: ", ")
    }
}
