import AVFoundation
import SwiftUI
import VisionKit

struct ScannerView: View {
    enum ScannerMode: String, CaseIterable, Identifiable {
        case add
        case writeOff
        case checkOff

        var id: String { rawValue }

        var title: String {
            switch self {
            case .add: return "Добавление"
            case .writeOff: return "Списание"
            case .checkOff: return "Отметка"
            }
        }

        var icon: String {
            switch self {
            case .add: return "plus.circle"
            case .writeOff: return "minus.circle"
            case .checkOff: return "checkmark.circle"
            }
        }
    }

    let inventoryService: any InventoryServiceProtocol
    let barcodeLookupService: BarcodeLookupService
    let onInventoryChanged: () async -> Void
    let allowedModes: [ScannerMode]
    let onProductScanned: ((Product) async -> Void)?

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
    @State private var isTorchOn = false

    init(
        inventoryService: any InventoryServiceProtocol,
        barcodeLookupService: BarcodeLookupService,
        initialMode: ScannerMode = .add,
        allowedModes: [ScannerMode] = [.add, .writeOff],
        onProductScanned: ((Product) async -> Void)? = nil,
        onInventoryChanged: @escaping () async -> Void = {}
    ) {
        self.inventoryService = inventoryService
        self.barcodeLookupService = barcodeLookupService
        self.allowedModes = allowedModes
        self.onProductScanned = onProductScanned
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

                if let errorMessage {
                    HStack(alignment: .top, spacing: VaySpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.white)
                            .padding(.top, 2)

                        Text(errorMessage)
                            .font(VayFont.label(13))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            withAnimation(VayAnimation.springSmooth) {
                                self.errorMessage = nil
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(VayFont.caption(12))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(VaySpacing.xs)
                                .background(.white.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, VaySpacing.md)
                    .padding(.vertical, VaySpacing.sm)
                    .background(.red.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
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
            .animation(VayAnimation.springSmooth, value: errorMessage != nil)
        }
        .navigationTitle("Сканер")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isTorchOn.toggle()
                    toggleTorch(on: isTorchOn)
                } label: {
                    Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(VayFont.body(18))
                        .foregroundStyle(isTorchOn ? Color.yellow : .white.opacity(0.7))
                }
                .accessibilityLabel(isTorchOn ? "Выключить фонарик" : "Включить фонарик")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(VayFont.heading(20))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .sheet(isPresented: $showAddBatchSheet) {
            if let selectedProduct {
                let classification = ProductClassifier.classify(rawCategory: selectedProduct.category)
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
                        initialUnit: parsedWeightGrams == nil ? selectedProduct.defaultUnit : .g,
                        initialLocation: classification.location
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
                    initialExpiryDate: suggestedExpiry,
                    initialLocation: ProductClassifier.classify(rawCategory: "Продукты").location
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
    }

    // MARK: - Fallback View

    private var fallbackView: some View {
        VStack(spacing: VaySpacing.md) {
            Image(systemName: "camera.metering.unknown")
                .font(VayFont.hero(48))
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
        Group {
            if allowedModes.count > 1 {
                HStack(spacing: 0) {
                    ForEach(allowedModes) { m in
                        Button {
                            withAnimation(VayAnimation.springSnappy) {
                                mode = m
                            }
                            VayHaptic.selection()
                        } label: {
                            HStack(spacing: VaySpacing.xs) {
                                Image(systemName: m.icon)
                                    .font(VayFont.caption(12))
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
        }
    }

    // MARK: - Manual Input

    private var manualLookupView: some View {
        HStack(spacing: VaySpacing.sm) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(VayFont.label(13))
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
                    .font(VayFont.title(28))
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
                title: mode == .add ? "Найдено" : (mode == .writeOff ? "Для списания" : "В списке"),
                productName: product.name,
                category: product.category,
                expiry: suggestedExpiry,
                product: product,
                showAddActions: mode == .add,
                showWriteOffActions: mode == .writeOff,
                showCheckOffActions: mode == .checkOff
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
                showAddActions: mode == .add,
                showWriteOffActions: false,
                showCheckOffActions: mode == .checkOff
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
        showWriteOffActions: Bool,
        showCheckOffActions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.md) {
            HStack(spacing: VaySpacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(VayFont.label(16))
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

                if showCheckOffActions {
                    Button {
                        Task { await performCheckOff(product: product) }
                    } label: {
                        HStack(spacing: VaySpacing.xs) {
                            Image(systemName: "checkmark")
                            Text(isQuickActionInProgress ? "…" : "Отметить")
                        }
                        .font(VayFont.label(13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, VaySpacing.md)
                        .padding(.vertical, VaySpacing.sm)
                        .background(Color.vaySuccess)
                        .clipShape(Capsule())
                    }
                    .disabled(isQuickActionInProgress)
                }

                Spacer()

                Button {
                    resetResolutionState()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(VayFont.label(14))
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
                    .font(VayFont.label(16))
                Text("Не найдено")
                    .font(VayFont.label(13))
                    .foregroundStyle(.secondary)
            }

            Text((mode == .add || mode == .checkOff)
                 ? "Создайте карточку — распознавание будет работать офлайн"
                 : "Для списания товар должен быть в инвентаре")
                .font(VayFont.body(14))
                .foregroundStyle(.secondary)

            if let barcode {
                HStack(spacing: VaySpacing.xs) {
                    Image(systemName: "barcode")
                        .font(VayFont.caption(11))
                    Text(barcode)
                        .font(VayFont.caption(12))
                }
                .foregroundStyle(.tertiary)
            }

            HStack(spacing: VaySpacing.sm) {
                if mode == .add || mode == .checkOff {
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
                        .font(VayFont.label(14))
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

        let resolved = await barcodeLookupService.resolve(rawCode: normalized, allowCreate: mode == .add || mode == .checkOff)
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
            
            if mode == .checkOff {
                Task { await performCheckOff(product: product) }
            }

        case .created(let product, let expiry, let weight, _):
            selectedProduct = product
            suggestedExpiry = expiry
            internalCodeToBind = nil
            parsedWeightGrams = weight
            barcodeForManualCreation = product.barcode

            if mode == .checkOff {
                Task { await performCheckOff(product: product) }
            }

        case .notFound(let barcode, let internalCode, let weight, let expiry):
            self.resolution = resolved
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

        let suggestedLocation = ProductClassifier.classify(rawCategory: product.category).location ?? .fridge
        let batch = Batch(
            productId: product.id,
            location: suggestedLocation,
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

    private func toggleTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    private func providerTitle(_ provider: String) -> String {
        switch provider {
        case "local_barcode_db":
            return "Локальная база"
        case "barcode_list_ru":
            return "barcode-list.ru"
        case "go_upc":
            return "Go-UPC"
        case "open_food_facts":
            return "Open Food Facts"
        case "open_beauty_facts":
            return "Open Beauty Facts"
        case "open_pet_food_facts":
            return "Open Pet Food Facts"
        case "open_products_facts":
            return "Open Products Facts"
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
    
    private func performCheckOff(product: Product) async {
        guard let onProductScanned = onProductScanned else { return }
        guard !isQuickActionInProgress else { return }
        
        isQuickActionInProgress = true
        defer { isQuickActionInProgress = false }

        await onProductScanned(product)
        
        withAnimation(VayAnimation.springSmooth) {
            quickActionMessage = "Отмечено: \(product.name)"
        }
        VayHaptic.success()
        
        try? await Task.sleep(for: .seconds(2))
        
        if self.selectedProduct?.id == product.id {
            resetResolutionState()
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
