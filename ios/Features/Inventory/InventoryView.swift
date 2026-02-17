import SwiftUI

struct InventoryView: View {
    let inventoryService: any InventoryServiceProtocol
    let barcodeLookupService: BarcodeLookupService

    @State private var selectedLocation: InventoryLocation = .fridge
    @State private var searchText: String = ""
    @State private var snapshot = InventorySnapshot(products: [], expiringSoon: [], productByID: [:])
    @State private var isPresentingAddProduct = false
    @State private var isPresentingScanner = false
    @State private var scannerMode: ScannerView.ScannerMode = .add
    @State private var batchPendingWriteOff: Batch?
    @State private var errorMessage: String?

    private var groupedProducts: [ProductWithBatches] {
        snapshot.products
    }

    var body: some View {
        List {
            locationSection
            expiringSection
            productsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Инвентарь")
        .searchable(text: $searchText, prompt: "Поиск по товарам")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("Сканировать") {
                    Button("Добавить по штрихкоду") {
                        scannerMode = .add
                        isPresentingScanner = true
                    }

                    Button("Списать по штрихкоду") {
                        scannerMode = .writeOff
                        isPresentingScanner = true
                    }
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
                    initialMode: scannerMode,
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
        .confirmationDialog(
            "Списать партию?",
            isPresented: Binding(
                get: { batchPendingWriteOff != nil },
                set: { isPresented in
                    if !isPresented {
                        batchPendingWriteOff = nil
                    }
                }
            ),
            presenting: batchPendingWriteOff
        ) { batch in
            Button("Списать", role: .destructive) {
                Task { await writeOff(batch: batch) }
            }
            Button("Отмена", role: .cancel) {}
        } message: { batch in
            Text("\(productName(for: batch.productId)), \(batch.quantity.formatted()) \(batch.unit.title)")
        }
        .task(id: reloadKey) {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section {
            Picker("Зона", selection: $selectedLocation) {
                ForEach(InventoryLocation.allCases) { location in
                    Text(location.title).tag(location)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var expiringSection: some View {
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
    }

    @ViewBuilder
    private var productsSection: some View {
        if groupedProducts.isEmpty {
            Section {
                Text("В этой зоне пока нет товаров")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(groupedProducts) { item in
                section(for: item)
            }
        }
    }

    private func section(for item: ProductWithBatches) -> some View {
        Section {
            NavigationLink {
                ProductDetailView(productID: item.product.id, inventoryService: inventoryService)
            } label: {
                Label("Открыть карточку товара", systemImage: "square.and.pencil")
            }

            if item.batches.isEmpty {
                Text("Партии не добавлены")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(item.batches) { batch in
                    batchRow(batch)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.name)
                if let barcode = item.product.barcode {
                    Text(barcode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func batchRow(_ batch: Batch) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(batch.quantity.formatted()) \(batch.unit.title)")
                    .font(.subheadline)
                Text(batch.isOpened ? "Открыто" : "Закрыто")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(batch.location.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let expiryDate = batch.expiryDate {
                    Text(expiryDate.formatted(date: .numeric, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Без срока")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                batchPendingWriteOff = batch
            } label: {
                Label("Списать", systemImage: "trash")
            }
        }
    }

    private var reloadKey: String {
        "\(selectedLocation.rawValue)-\(searchText)"
    }

    private func productName(for productID: UUID) -> String {
        snapshot.productByID[productID]?.name ?? "Продукт"
    }

    private func writeOff(batch: Batch) async {
        do {
            try await inventoryService.removeBatch(id: batch.id)
            batchPendingWriteOff = nil
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
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
