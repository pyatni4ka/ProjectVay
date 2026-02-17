import SwiftUI
import AVFoundation

struct ReceiptScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scannedItems: [ScannedReceiptItem] = []
    @State private var isScanning = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var errorMessage: String?
    @State private var showError = false
    
    let inventoryService: any InventoryServiceProtocol
    let onItemsAdded: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: VaySpacing.lg) {
                if isScanning {
                    scanningView
                } else if scannedItems.isEmpty {
                    emptyStateView
                } else {
                    resultsView
                }
            }
            .padding(VaySpacing.lg)
            .background(Color.vayBackground)
            .navigationTitle("Сканирование чека")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImagePicker = true
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage)
            }
            .onChange(of: selectedImage) { _, newImage in
                if let image = newImage {
                    Task {
                        await processImage(image)
                    }
                }
            }
            .alert("Ошибка", isPresented: $showError) {
                Button("Ок", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
        }
    }
    
    private var scanningView: some View {
        VStack(spacing: VaySpacing.lg) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Распознаём чек...")
                .font(VayFont.body(16))
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: VaySpacing.xl) {
            Spacer()
            
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(Color.vayPrimary)
            
            VStack(spacing: VaySpacing.sm) {
                Text("Сканирование чеков")
                    .font(VayFont.heading(20))
                
                Text("Сфотографируйте чек, и мы автоматически добавим товары в список покупок.")
                    .font(VayFont.body(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showImagePicker = true
            } label: {
                Label("Выбрать фото", systemImage: "camera.fill")
                    .font(VayFont.label())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VaySpacing.md)
                    .background(Color.vayPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
            }
            
            Spacer()
        }
    }
    
    private var resultsView: some View {
        VStack(spacing: VaySpacing.lg) {
            HStack {
                Text("Найденные товары")
                    .font(VayFont.heading(16))
                Spacer()
                Text("\(scannedItems.count) шт")
                    .font(VayFont.caption(12))
                    .foregroundStyle(.secondary)
            }
            
            List {
                ForEach(scannedItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(VayFont.label(14))
                            
                            if let category = item.category {
                                Text(category)
                                    .font(VayFont.caption(11))
                                    .foregroundStyle(Color.vayPrimary)
                            }
                        }
                        
                        Spacer()
                        
                        if let price = item.price {
                            Text(verbatim: "\(price) ₽")
                                .font(VayFont.caption(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg))
            
            Button {
                Task {
                    await addAllToInventory()
                }
            } label: {
                Label("Добавить все в инвентарь", systemImage: "plus.circle.fill")
                    .font(VayFont.label())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VaySpacing.md)
                    .background(Color.vayPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: VayRadius.lg, style: .continuous))
            }
        }
    }
    
    private func processImage(_ image: UIImage) async {
        isScanning = true
        selectedImage = nil
        
        do {
            let items = try await ReceiptScannerService.shared.scanReceipt(from: image)
            await MainActor.run {
                scannedItems = items
                isScanning = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isScanning = false
            }
        }
    }
    
    private func addAllToInventory() async {
        var addedCount = 0
        for item in scannedItems {
            let product = Product(
                name: item.name,
                category: item.category ?? "Другое",
                defaultUnit: .pcs,
                nutrition: .empty
            )
            
            do {
                _ = try await inventoryService.createProduct(product)
                addedCount += 1
            } catch {
                continue
            }
        }

        if addedCount > 0 {
            await MainActor.run {
                GamificationService.shared.trackReceiptScan(count: addedCount)
                GamificationService.shared.trackProductAdded(count: addedCount)
            }
        }
        onItemsAdded()
        dismiss()
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
