import AVFoundation
import SwiftUI
import VisionKit

struct ScannerView: View {
    let inventoryService: any InventoryServiceProtocol
    let barcodeLookupService: BarcodeLookupService
    let onInventoryChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var manualCode: String = ""
    @State private var isProcessing = false
    @State private var lastScannedCode: String = ""
    @State private var lastScanAt: Date = .distantPast
    @State private var resolution: ScanResolution?
    @State private var selectedProduct: Product?
    @State private var suggestedExpiry: Date?
    @State private var internalCodeToBind: String?
    @State private var parsedWeightGrams: Double?
    @State private var barcodeForManualCreation: String?
    @State private var errorMessage: String?
    @State private var showAddBatchSheet = false
    @State private var showCreateProductSheet = false
    @State private var isQuickAdding = false
    @State private var quickAddMessage: String?

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if scannerAvailable {
                    ScannerCameraView(
                        onCodeDetected: { code in
                            Task { await processScannedCode(code) }
                        },
                        onError: { message in
                            errorMessage = message
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                } else {
                    fallbackView
                }
            }
            .padding(.horizontal)

            manualLookupView
                .padding(.horizontal)

            if let quickAddMessage {
                Text(quickAddMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal)
            }

            if let resolution {
                resolutionCard(for: resolution)
                    .padding(.horizontal)
            }

            Spacer(minLength: 0)
        }
        .navigationTitle("Сканер")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Закрыть") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showAddBatchSheet) {
            if let selectedProduct {
                NavigationStack {
                    EditBatchView(
                        productID: selectedProduct.id,
                        batch: nil,
                        inventoryService: inventoryService,
                        onSaved: {
                            Task {
                                await onInventoryChanged()
                            }
                        },
                        initialExpiryDate: suggestedExpiry,
                        initialQuantity: parsedWeightGrams,
                        initialUnit: parsedWeightGrams == nil ? selectedProduct.defaultUnit : .g
                    )
                }
            }
        }
        .sheet(isPresented: $showCreateProductSheet) {
            NavigationStack {
                AddProductView(
                    inventoryService: inventoryService,
                    initialName: nil,
                    initialBarcode: barcodeForManualCreation,
                    initialCategory: "Продукты",
                    initialUnit: parsedWeightGrams == nil ? nil : .g,
                    initialQuantity: parsedWeightGrams ?? 1,
                    initialExpiryDate: suggestedExpiry
                ) { savedProduct in
                    Task {
                        if let internalCodeToBind {
                            try? await inventoryService.bindInternalCode(
                                internalCodeToBind,
                                productId: savedProduct.id,
                                parsedWeightGrams: parsedWeightGrams
                            )
                        }

                        selectedProduct = savedProduct
                        resolution = .found(
                            product: savedProduct,
                            suggestedExpiry: suggestedExpiry,
                            parsedWeightGrams: parsedWeightGrams
                        )
                        await onInventoryChanged()
                    }
                }
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
    }

    private var fallbackView: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 36))
            Text("Live-сканер недоступен на этом устройстве")
                .font(.headline)
            Text("Введите код вручную ниже")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: 220)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var manualLookupView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ручной ввод")
                .font(.headline)

            HStack {
                TextField("EAN-13 / DataMatrix / внутренний код", text: $manualCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button(isProcessing ? "..." : "Найти") {
                    Task { await processScannedCode(manualCode) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func resolutionCard(for resolution: ScanResolution) -> some View {
        switch resolution {
        case .found(let product, let suggestedExpiry, _):
            VStack(alignment: .leading, spacing: 8) {
                Text("Найдено локально")
                    .font(.headline)
                Text(product.name)
                    .font(.title3)
                Text(product.category)
                    .foregroundStyle(.secondary)

                if let suggestedExpiry {
                    Text("Срок из кода: \(suggestedExpiry.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(isQuickAdding ? "Добавляем..." : "Быстро +1") {
                        Task { await quickAddBatch(product: product) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isQuickAdding)

                    Button("Добавить партию") {
                        showAddBatchSheet = true
                    }
                    .buttonStyle(.bordered)

                    Button("Сканировать снова") {
                        resetResolutionState()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .created(let product, let suggestedExpiry, _, let provider):
            VStack(alignment: .leading, spacing: 8) {
                Text("Карточка создана автоматически")
                    .font(.headline)
                Text(product.name)
                    .font(.title3)

                Text("Источник: \(provider)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let suggestedExpiry {
                    Text("Срок из DataMatrix: \(suggestedExpiry.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(isQuickAdding ? "Добавляем..." : "Быстро +1") {
                        Task { await quickAddBatch(product: product) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isQuickAdding)

                    Button("Добавить партию") {
                        showAddBatchSheet = true
                    }
                    .buttonStyle(.bordered)

                    Button("Сканировать снова") {
                        resetResolutionState()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        case .notFound(let barcode, let internalCode, let parsedWeightGrams, let suggestedExpiry):
            VStack(alignment: .leading, spacing: 8) {
                Text("Товар не найден")
                    .font(.headline)
                Text("Создайте локальную карточку. После сохранения распознавание будет работать офлайн.")
                    .foregroundStyle(.secondary)

                if let barcode {
                    Text("Штрихкод: \(barcode)")
                        .font(.caption)
                }

                if let internalCode {
                    Text("Внутренний код: \(internalCode)")
                        .font(.caption)
                }

                if let parsedWeightGrams {
                    Text("Определён вес: \(parsedWeightGrams.formatted()) г")
                        .font(.caption)
                }

                if let suggestedExpiry {
                    Text("Срок из DataMatrix: \(suggestedExpiry.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                }

                Button("Создать вручную") {
                    showCreateProductSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func processScannedCode(_ rawCode: String) async {
        let normalized = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if normalized == lastScannedCode, Date().timeIntervalSince(lastScanAt) < 1.5 {
            return
        }

        lastScannedCode = normalized
        lastScanAt = Date()

        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let resolved = await barcodeLookupService.resolve(rawCode: normalized)
        applyResolution(resolved)
    }

    private func applyResolution(_ resolved: ScanResolution) {
        resolution = resolved
        quickAddMessage = nil

        switch resolved {
        case .found(let product, let expiry, let weight):
            selectedProduct = product
            suggestedExpiry = expiry
            internalCodeToBind = nil
            parsedWeightGrams = weight
            barcodeForManualCreation = product.barcode

        case .created(let product, let expiry, let weight, _):
            selectedProduct = product
            suggestedExpiry = expiry
            internalCodeToBind = nil
            parsedWeightGrams = weight
            barcodeForManualCreation = product.barcode

        case .notFound(let barcode, let internalCode, let weight, let expiry):
            selectedProduct = nil
            suggestedExpiry = expiry
            internalCodeToBind = internalCode
            parsedWeightGrams = weight
            barcodeForManualCreation = barcode
        }
    }

    private func quickAddBatch(product: Product) async {
        guard !isQuickAdding else { return }

        isQuickAdding = true
        defer { isQuickAdding = false }

        let quantity: Double
        let unit: UnitType

        if let grams = parsedWeightGrams, grams > 0 {
            quantity = grams
            unit = .g
        } else {
            quantity = 1
            unit = product.defaultUnit
        }

        let batch = Batch(
            productId: product.id,
            location: .fridge,
            quantity: quantity,
            unit: unit,
            expiryDate: suggestedExpiry,
            isOpened: false
        )

        do {
            _ = try await inventoryService.addBatch(batch)
            await onInventoryChanged()
            quickAddMessage = "Партия добавлена: \(quantity.formatted()) \(unit.title)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetResolutionState() {
        resolution = nil
        selectedProduct = nil
        suggestedExpiry = nil
        internalCodeToBind = nil
        parsedWeightGrams = nil
        barcodeForManualCreation = nil
        quickAddMessage = nil
    }
}

private struct ScannerCameraView: UIViewControllerRepresentable {
    let onCodeDetected: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeDetected: onCodeDetected, onError: onError)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .dataMatrix])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )

        scanner.delegate = context.coordinator

        do {
            try scanner.startScanning()
        } catch {
            context.coordinator.onError("Не удалось запустить сканер: \(error.localizedDescription)")
        }

        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCodeDetected: (String) -> Void
        let onError: (String) -> Void

        init(onCodeDetected: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCodeDetected = onCodeDetected
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let first = addedItems.first else { return }
            handle(first)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(item)
        }

        private func handle(_ item: RecognizedItem) {
            guard case .barcode(let barcode) = item else { return }
            guard let payload = barcode.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !payload.isEmpty else {
                return
            }

            onCodeDetected(payload)
        }
    }
}
