import AVFoundation
import SwiftUI
import VisionKit

struct ScannerView: View {
    enum ScannerMode: String, CaseIterable, Identifiable {
        case add
        case writeOff

        var id: String { rawValue }

        var title: String {
            switch self {
            case .add:
                return "Добавление"
            case .writeOff:
                return "Списание"
            }
        }

        var icon: String {
            switch self {
            case .add: return "plus.circle"
            case .writeOff: return "minus.circle"
            }
        }
    }

    let inventoryService: any InventoryServiceProtocol
    let barcodeLookupService: BarcodeLookupService
    let onInventoryChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mode: ScannerMode
    @State private var manualCode: String = ""
    @State private var isProcessing = false
    @State private var scannerGate = ScannerOneShotGate()
    @State private var isScannerPaused = false
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
    @State private var isQuickActionInProgress = false
    @State private var quickActionMessage: String?

    init(
        inventoryService: any InventoryServiceProtocol,
        barcodeLookupService: BarcodeLookupService,
        initialMode: ScannerMode = .add,
        onInventoryChanged: @escaping () async -> Void
    ) {
        self.inventoryService = inventoryService
        self.barcodeLookupService = barcodeLookupService
        self.onInventoryChanged = onInventoryChanged
        _mode = State(initialValue: initialMode)
    }

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Camera / Fallback
            Group {
                if scannerAvailable {
                    ScannerCameraView(
                        isPaused: isScannerPaused,
                        onCodeDetected: { code in
                            handleCameraDetectedCode(code)
                        },
                        onError: { message in
                            errorMessage = message
                        }
                    )
                } else {
                    fallbackView
                }
            }
            .ignoresSafeArea()

            // Gradient overlay at bottom for readability
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35), .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 320)

                // Solid fill beneath the gradient to cover edge-to-edge
                Color.black.opacity(0.55)
            }
            .ignoresSafeArea()

            // Bottom Controls
            VStack(spacing: VaySpacing.md) {
                // Quick action success message
                if let quickActionMessage {
                    HStack(spacing: VaySpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(quickActionMessage)
                    }
                    .font(VayFont.label(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, VaySpacing.lg)
                    .padding(.vertical, VaySpacing.sm)
                    .background(.green.opacity(0.8))
                    .clipShape(Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if scannerGate.isLocked {
                    HStack(spacing: VaySpacing.sm) {
                        Image(systemName: "scope")
                            .foregroundStyle(Color.vayInfo)
                        Text("Код зафиксирован, можно убрать камеру")
                            .font(VayFont.label(13))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, VaySpacing.lg)
                    .padding(.vertical, VaySpacing.sm)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }

                // Scanning indicator
                if isProcessing {
                    HStack(spacing: VaySpacing.sm) {
                        ProgressView()
                            .tint(.white)
                        Text("Распознаю…")
                            .font(VayFont.label(13))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, VaySpacing.lg)
                    .padding(.vertical, VaySpacing.sm)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }

                // Resolution Card (overlaying camera)
                if let resolution {
                    resolutionCard(for: resolution)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Mode Picker
                modePicker

                // Manual Input
                manualLookupView
            }
            .padding(.horizontal, VaySpacing.lg)
            .padding(.bottom, VaySpacing.xxl)
            .animation(VayAnimation.springSmooth, value: resolution != nil)
            .animation(VayAnimation.springSmooth, value: quickActionMessage)
        }
        .navigationTitle("Сканер")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.7))
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

    // MARK: - Fallback View

    private var fallbackView: some View {
        VStack(spacing: VaySpacing.md) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
            Text("Live-сканер недоступен")
                .font(VayFont.heading())
                .foregroundStyle(.white)
            Text("Введите код вручную ниже")
                .font(VayFont.caption())
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(ScannerMode.allCases) { m in
                Button {
                    withAnimation(VayAnimation.springSnappy) {
                        mode = m
                    }
                    VayHaptic.selection()
                } label: {
                    HStack(spacing: VaySpacing.xs) {
                        Image(systemName: m.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(m.title)
                            .font(VayFont.label(13))
                    }
                    .foregroundStyle(mode == m ? .white : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VaySpacing.sm)
                    .background(mode == m ? Color.vayPrimary : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(VaySpacing.xs)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    // MARK: - Manual Input

    private var manualLookupView: some View {
        HStack(spacing: VaySpacing.sm) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.system(size: 13))
                TextField("EAN-13 / DataMatrix / код", text: $manualCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .font(VayFont.body(14))
            }
            .padding(.horizontal, VaySpacing.md)
            .padding(.vertical, VaySpacing.sm + 2)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))

            Button {
                Task { await processScannedCode(manualCode) }
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.vayPrimary)
            }
            .disabled(isProcessing || manualCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Resolution Card

    @ViewBuilder
    private func resolutionCard(for resolution: ScanResolution) -> some View {
        switch resolution {
        case .found(let product, let suggestedExpiry, _):
            resolutionContent(
                icon: "checkmark.circle.fill",
                iconColor: .vaySuccess,
                title: mode == .add ? "Найдено" : "Для списания",
                productName: product.name,
                category: product.category,
                expiry: suggestedExpiry,
                product: product,
                showAddActions: mode == .add,
                showWriteOffActions: mode == .writeOff
            )

        case .created(let product, let suggestedExpiry, _, let provider):
            resolutionContent(
                icon: "sparkles",
                iconColor: .vayInfo,
                title: "Создано автоматически",
                productName: product.name,
                category: "\(product.category) • \(providerTitle(provider))",
                expiry: suggestedExpiry,
                product: product,
                showAddActions: true,
                showWriteOffActions: false
            )

        case .notFound(let barcode, let internalCode, let parsedWeightGrams, let suggestedExpiry):
            notFoundContent(
                barcode: barcode,
                internalCode: internalCode,
                parsedWeightGrams: parsedWeightGrams,
                suggestedExpiry: suggestedExpiry
            )
        }
    }

    private func resolutionContent(
        icon: String,
        iconColor: Color,
        title: String,
        productName: String,
        category: String,
        expiry: Date?,
        product: Product,
        showAddActions: Bool,
        showWriteOffActions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(VayFont.label(13))
                    .foregroundStyle(.secondary)
            }

            Text(productName)
                .font(VayFont.heading())

            HStack(spacing: VaySpacing.sm) {
                Text(category)
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)

                if let expiry {
                    Text("• до \(expiry.formatted(date: .abbreviated, time: .omitted))")
                        .font(VayFont.caption(12))
                        .foregroundStyle(Color.vayWarning)
                }
            }

            HStack(spacing: VaySpacing.sm) {
                if showAddActions {
                    Button {
                        Task { await quickAddBatch(product: product) }
                    } label: {
                        HStack(spacing: VaySpacing.xs) {
                            Image(systemName: "plus")
                            Text(isQuickActionInProgress ? "…" : "Быстро +1")
                        }
                        .font(VayFont.label(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, VaySpacing.md)
                        .padding(.vertical, VaySpacing.sm)
                        .background(Color.vayPrimary)
                        .clipShape(Capsule())
                    }
                    .disabled(isQuickActionInProgress)

                    Button {
                        showAddBatchSheet = true
                    } label: {
                        Text("Партия")
                            .font(VayFont.label(13))
                            .foregroundStyle(Color.vayPrimary)
                            .padding(.horizontal, VaySpacing.md)
                            .padding(.vertical, VaySpacing.sm)
                            .background(Color.vayPrimary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if showWriteOffActions {
                    Button {
                        Task { await quickWriteOffBatch(product: product) }
                    } label: {
                        HStack(spacing: VaySpacing.xs) {
                            Image(systemName: "minus")
                            Text(isQuickActionInProgress ? "…" : "Списать")
                        }
                        .font(VayFont.label(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, VaySpacing.md)
                        .padding(.vertical, VaySpacing.sm)
                        .background(Color.vayDanger)
                        .clipShape(Capsule())
                    }
                    .disabled(isQuickActionInProgress)
                }

                Spacer()

                Button {
                    resetResolutionState()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(VaySpacing.sm)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
            }
        }
        .padding(VaySpacing.lg)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous))
    }

    private func notFoundContent(
        barcode: String?,
        internalCode: String?,
        parsedWeightGrams: Double?,
        suggestedExpiry: Date?
    ) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(Color.vayWarning)
                    .font(.system(size: 16, weight: .semibold))
                Text("Не найдено")
                    .font(VayFont.label(13))
                    .foregroundStyle(.secondary)
            }

            Text(mode == .add
                 ? "Создайте карточку — распознавание будет работать офлайн"
                 : "Для списания товар должен быть в инвентаре")
                .font(VayFont.body(14))
                .foregroundStyle(.secondary)

            if let barcode {
                HStack(spacing: VaySpacing.xs) {
                    Image(systemName: "barcode")
                        .font(.system(size: 11))
                    Text(barcode)
                        .font(VayFont.caption(12))
                }
                .foregroundStyle(.tertiary)
            }

            HStack(spacing: VaySpacing.sm) {
                if mode == .add {
                    Button {
                        showCreateProductSheet = true
                    } label: {
                        HStack(spacing: VaySpacing.xs) {
                            Image(systemName: "plus.circle.fill")
                            Text("Создать")
                        }
                        .font(VayFont.label(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, VaySpacing.md)
                        .padding(.vertical, VaySpacing.sm)
                        .background(Color.vayPrimary)
                        .clipShape(Capsule())
                    }
                } else {
                    Button {
                        mode = .add
                    } label: {
                        Text("В режим добавления")
                            .font(VayFont.label(13))
                            .foregroundStyle(Color.vayPrimary)
                            .padding(.horizontal, VaySpacing.md)
                            .padding(.vertical, VaySpacing.sm)
                            .background(Color.vayPrimary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button {
                    resetResolutionState()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(VaySpacing.sm)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
            }
        }
        .padding(VaySpacing.lg)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.xl, style: .continuous))
    }

    // MARK: - Logic (preserved exactly)

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

        let resolved = await barcodeLookupService.resolve(rawCode: normalized, allowCreate: mode == .add)
        applyResolution(resolved)
        VayHaptic.impact(.medium)
    }

    private func handleCameraDetectedCode(_ rawCode: String) {
        guard !isProcessing else { return }
        guard let capturedCode = scannerGate.capture(rawCode) else { return }
        if capturedCode == lastScannedCode, Date().timeIntervalSince(lastScanAt) < 1.5 {
            scannerGate.reset()
            return
        }

        isScannerPaused = true

        Task {
            await processScannedCode(capturedCode)
        }
    }

    private func applyResolution(_ resolved: ScanResolution) {
        resolution = resolved
        quickActionMessage = nil

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
        guard !isQuickActionInProgress else { return }

        isQuickActionInProgress = true
        defer { isQuickActionInProgress = false }

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
            withAnimation(VayAnimation.springSmooth) {
                quickActionMessage = "Добавлено: \(quantity.formatted()) \(unit.title)"
            }
            VayHaptic.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func quickWriteOffBatch(product: Product) async {
        guard !isQuickActionInProgress else { return }

        isQuickActionInProgress = true
        defer { isQuickActionInProgress = false }

        do {
            let batches = try await inventoryService.listBatches(productId: product.id)
            guard !batches.isEmpty else {
                errorMessage = "Нет партий для списания"
                return
            }

            let preferredUnit: UnitType = parsedWeightGrams == nil ? product.defaultUnit : .g
            let targetBatch = batches.first(where: { $0.unit == preferredUnit }) ?? batches.first!

            var quantityToWriteOff = parsedWeightGrams ?? 1
            if quantityToWriteOff <= 0 {
                quantityToWriteOff = 1
            }

            if targetBatch.unit != preferredUnit {
                quantityToWriteOff = min(targetBatch.quantity, targetBatch.unit == .pcs ? 1 : quantityToWriteOff)
            }

            if targetBatch.quantity <= quantityToWriteOff + 0.000_001 {
                try await inventoryService.removeBatch(
                    id: targetBatch.id,
                    quantity: nil,
                    intent: .writeOff,
                    note: "Списано через сканер"
                )
                withAnimation(VayAnimation.springSmooth) {
                    quickActionMessage = "Партия полностью списана"
                }
            } else {
                try await inventoryService.removeBatch(
                    id: targetBatch.id,
                    quantity: quantityToWriteOff,
                    intent: .writeOff,
                    note: "Списано через сканер"
                )
                withAnimation(VayAnimation.springSmooth) {
                    quickActionMessage = "Списано: \(quantityToWriteOff.formatted()) \(targetBatch.unit.title)"
                }
            }

            VayHaptic.success()
            await onInventoryChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetResolutionState() {
        withAnimation(VayAnimation.springSmooth) {
            resolution = nil
        }
        scannerGate.reset()
        isScannerPaused = false
        lastScannedCode = ""
        lastScanAt = .distantPast
        selectedProduct = nil
        suggestedExpiry = nil
        internalCodeToBind = nil
        parsedWeightGrams = nil
        barcodeForManualCreation = nil
        quickActionMessage = nil
    }

    private func providerTitle(_ provider: String) -> String {
        switch provider {
        case "barcode_list_ru":
            return "barcode-list.ru"
        case "open_food_facts":
            return "Open Food Facts"
        case "ean_db":
            return "EAN-DB"
        case "rf_source":
            return "RF proxy"
        case "auto_template":
            return "Автошаблон"
        default:
            return provider
        }
    }
}

private struct ScannerCameraView: UIViewControllerRepresentable {
    let isPaused: Bool
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

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if isPaused {
            if uiViewController.isScanning {
                uiViewController.stopScanning()
            }
            return
        }

        guard !uiViewController.isScanning else { return }
        do {
            try uiViewController.startScanning()
        } catch {
            context.coordinator.onError("Не удалось запустить сканер: \(error.localizedDescription)")
        }
    }

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

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let first = updatedItems.first else { return }
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
