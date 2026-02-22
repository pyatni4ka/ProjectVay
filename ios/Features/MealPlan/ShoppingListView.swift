import SwiftUI

@MainActor
final class ShoppingListViewModel: ObservableObject {
    @Published private(set) var items: [ShoppingListItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    
    // Dependencies
    private let shoppingListService: ShoppingListServiceProtocol
    let barcodeLookupService: BarcodeLookupService
    
    init(
        shoppingListService: ShoppingListServiceProtocol,
        barcodeLookupService: BarcodeLookupService
    ) {
        self.shoppingListService = shoppingListService
        self.barcodeLookupService = barcodeLookupService
    }
    
    func loadItems() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await shoppingListService.getItems()
        } catch {
            errorMessage = "Не удалось загрузить список покупок: \(userFacingErrorMessage(error))"
        }
        isLoading = false
    }
    
    func toggleCompletion(for item: ShoppingListItem) async {
        do {
            // Optimistic update
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].isCompleted.toggle()
            }
            try await shoppingListService.toggleItemCompletion(id: item.id)
            await loadItems() // Refresh to ensure sync
        } catch {
            errorMessage = "Не удалось обновить статус: \(userFacingErrorMessage(error))"
            await loadItems() // Revert on failure
        }
    }
    
    func deleteItem(_ item: ShoppingListItem) async {
        do {
            try await shoppingListService.deleteItem(id: item.id)
            await loadItems()
        } catch {
            errorMessage = "Не удалось удалить пункт: \(userFacingErrorMessage(error))"
        }
    }
    
    func clearCompleted() async {
        do {
            try await shoppingListService.clearCompleted()
            await loadItems()
        } catch {
            errorMessage = "Не удалось очистить завершённые: \(userFacingErrorMessage(error))"
        }
    }
    
    func addItem(name: String, quantity: Double = 1, unit: UnitType = .pcs) async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        do {
            try await shoppingListService.addItem(name: name, quantity: quantity, unit: unit)
            await loadItems()
        } catch {
            errorMessage = "Не удалось добавить пункт: \(userFacingErrorMessage(error))"
            isLoading = false
        }
    }
    
    func checkOffScannedItems(scannedNames: [String]) async {
        let activeItems = items.filter { !$0.isCompleted }
        let lowercasedScannedNames = Set(scannedNames.map { $0.lowercased() })
        
        for item in activeItems {
            let itemNameLow = item.name.lowercased()
            if lowercasedScannedNames.contains(itemNameLow) {
                await toggleCompletion(for: item)
                continue
            }
            // Partial matching
            for scannedName in lowercasedScannedNames {
                if scannedName.contains(itemNameLow) || itemNameLow.contains(scannedName) {
                    await toggleCompletion(for: item)
                    break
                }
            }
        }
    }
    
    func generateFromMealPlan(missingIngredients: [String]) async {
        guard !missingIngredients.isEmpty else { return }
        isLoading = true
        do {
            try await shoppingListService.generateFromMealPlan(missingIngredients)
            await loadItems()
        } catch {
            errorMessage = "Не удалось добавить ингредиенты из плана: \(userFacingErrorMessage(error))"
        }
        isLoading = false
    }
    
    private func userFacingErrorMessage(_ error: Error) -> String {
        return error.localizedDescription
    }
}

struct ShoppingListView: View {
    @StateObject private var viewModel: ShoppingListViewModel
    @Environment(\.dismiss) private var dismiss
    
    // Dependencies required for sub-views (e.g. Scanner)
    let inventoryService: any InventoryServiceProtocol
    
    @State private var showScannerSheet = false
    @State private var showManualAddAlert = false
    @State private var manualName = ""
    @State private var manualQuantity = "1"
    
    init(
        shoppingListService: ShoppingListServiceProtocol,
        barcodeLookupService: BarcodeLookupService,
        inventoryService: any InventoryServiceProtocol
    ) {
        _viewModel = StateObject(wrappedValue: ShoppingListViewModel(
            shoppingListService: shoppingListService,
            barcodeLookupService: barcodeLookupService
        ))
        self.inventoryService = inventoryService
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.vayBackground.ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.items.isEmpty {
                    SwiftUI.ProgressView("Загрузка списка...")
                } else if viewModel.items.isEmpty {
                    emptyStateView
                } else {
                    listView
                }
            }
            .navigationTitle("Список покупок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Button {
                            manualName = ""
                            manualQuantity = "1"
                            showManualAddAlert = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        
                        Menu {
                            Button(role: .destructive) {
                                Task { await viewModel.clearCompleted() }
                            } label: {
                                Label("Очистить купленное", systemImage: "trash")
                            }
                            
                            Button {
                                showScannerSheet = true
                            } label: {
                                Label("Сканировать чек", systemImage: "doc.text.viewfinder")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Ошибка", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Добавить продукт", isPresented: $showManualAddAlert) {
                TextField("Название", text: $manualName)
                TextField("Количество", text: $manualQuantity)
                    .keyboardType(.decimalPad)
                Button("Добавить") {
                    let qty = Double(manualQuantity.replacingOccurrences(of: ",", with: ".")) ?? 1.0
                    Task { await viewModel.addItem(name: manualName, quantity: qty) }
                }
                Button("Отмена", role: .cancel) { }
            } message: {
                Text("Введите название продукта и количество.")
            }
            .sheet(isPresented: $showScannerSheet) {
                NavigationStack {
                    ScannerView(
                        inventoryService: inventoryService,
                        barcodeLookupService: viewModel.barcodeLookupService,
                        initialMode: .checkOff,
                        allowedModes: [.checkOff],
                        onProductScanned: { product in
                            await viewModel.checkOffScannedItems(scannedNames: [product.name])
                            await viewModel.loadItems()
                        }
                    )
                }
            }
            .task {
                await viewModel.loadItems()
            }
        }
    }
    
    private var emptyStateView: some View {
        EmptyStateView(
            icon: "cart",
            lottieName: "empty_box",
            title: "Список пуст",
            subtitle: "Ингредиенты, которых не хватает для рецептов из плана питания, появятся здесь.",
            actionTitle: "Закрыть",
            action: { dismiss() }
        )
    }
    
    private var listView: some View {
        List {
            let activeItems = viewModel.items.filter { !$0.isCompleted }
            let completedItems = viewModel.items.filter { $0.isCompleted }
            
            if !activeItems.isEmpty {
                let groupedActiveItems = Dictionary(grouping: activeItems, by: { $0.category })
                let sortedCategories = groupedActiveItems.keys.sorted()
                
                ForEach(sortedCategories, id: \.self) { category in
                    Section(header: Text(category).font(VayFont.heading(16)).foregroundStyle(.primary)) {
                        ForEach(groupedActiveItems[category] ?? []) { item in
                            itemRow(item)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                if let itemsInCategory = groupedActiveItems[category] {
                                    Task { await viewModel.deleteItem(itemsInCategory[index]) }
                                }
                            }
                        }
                    }
                }
            }
            
            if !completedItems.isEmpty {
                Section("Куплено") {
                    ForEach(completedItems) { item in
                        itemRow(item)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            Task { await viewModel.deleteItem(completedItems[index]) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func itemRow(_ item: ShoppingListItem) -> some View {
        Button {
            VayHaptic.selection()
            Task { await viewModel.toggleCompletion(for: item) }
        } label: {
            HStack(spacing: VaySpacing.md) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? Color.vayPrimary : Color.secondary.opacity(0.5))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(VayFont.body(16))
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted)
                    
                    Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(item.unit.rawValue)")
                        .font(VayFont.caption(13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vayAccessibilityLabel(
            item.name,
            hint: item.isCompleted ? "Отметить как не куплено" : "Отметить как куплено"
        )
    }
    
}
