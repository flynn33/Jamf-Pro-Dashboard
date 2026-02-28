import SwiftUI

/// ScanIntoTextFieldButton declaration.
struct ScanIntoTextFieldButton: View {
    @Binding var text: String
    let onScanned: ((String) -> Void)?

    @State private var isScannerPresented = false

    /// Initializes the instance.
    init(
        text: Binding<String>,
        onScanned: ((String) -> Void)? = nil
    ) {
        _text = text
        self.onScanned = onScanned
    }

    var body: some View {
        Button {
            isScannerPresented = true
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.appSecondary)
        .accessibilityLabel("Scan Barcode or QR")
        .sheet(isPresented: $isScannerPresented) {
            CodeScannerSheet { scannedValue in
                text = scannedValue
                onScanned?(scannedValue)
            }
        }
    }
}

//endofline
