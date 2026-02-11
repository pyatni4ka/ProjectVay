import SwiftUI

struct ScannerView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 56))
            Text("Сканируйте EAN-13 / DataMatrix")
            Text("Для MVP используйте ScannerService + VisionKit DataScannerViewController")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Сканер")
    }
}
