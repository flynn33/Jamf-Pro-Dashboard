import SwiftUI
#if os(iOS)
import AVFoundation
import Vision
import VisionKit
import UIKit
#endif

/// ScannerPresentationState declaration.
private enum ScannerPresentationState {
    case checking
    case ready
    case unsupported
    case unavailable
    case permissionDenied
}

/// CodeScannerSheet declaration.
struct CodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onScanned: (String) -> Void

    @State private var state: ScannerPresentationState = .checking
    @State private var scannerErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .checking:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing camera scanner...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready:
#if os(iOS)
                    BarcodeScannerRepresentable(
                        onScanned: { value in
                            onScanned(value)
                            dismiss()
                        },
                        onError: { message in
                            scannerErrorMessage = message
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
#else
                    ScannerStatusView(
                        title: "Scanner Unsupported",
                        message: "Barcode and QR scanning is only available on iOS."
                    )
#endif

                case .unsupported:
                    ScannerStatusView(
                        title: "Scanner Unsupported",
                        message: "This device does not support live barcode and QR scanning."
                    )

                case .unavailable:
                    ScannerStatusView(
                        title: "Scanner Unavailable",
                        message: "Camera scanning is currently unavailable. Try again in a moment."
                    )

                case .permissionDenied:
                    ScannerStatusView(
                        title: "Camera Access Required",
                        message: "Enable camera access in Settings to scan barcode and QR data."
                    ) {
                        openSystemSettings()
                    }
                }
            }
            .navigationTitle("Scan Code")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .appTopBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await configureScannerAvailability()
            }
            .alert(
                "Scanner Error",
                isPresented: Binding(
                    get: { scannerErrorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            scannerErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(scannerErrorMessage ?? "Unknown scanner failure.")
            }
        }
    }

    /// Handles configureScannerAvailability.
    private func configureScannerAvailability() async {
#if os(iOS)
        guard DataScannerViewController.isSupported else {
            state = .unsupported
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            state = DataScannerViewController.isAvailable ? .ready : .unavailable
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { accessGranted in
                    continuation.resume(returning: accessGranted)
                }
            }

            if granted {
                state = DataScannerViewController.isAvailable ? .ready : .unavailable
            } else {
                state = .permissionDenied
            }
        case .restricted, .denied:
            state = .permissionDenied
        @unknown default:
            state = .unavailable
        }
#else
        state = .unsupported
#endif
    }

    /// Handles openSystemSettings.
    private func openSystemSettings() {
#if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
#endif
    }
}

/// ScannerStatusView declaration.
private struct ScannerStatusView: View {
    let title: String
    let message: String
    let action: (() -> Void)?

    /// Initializes the instance.
    init(
        title: String,
        message: String,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.largeTitle)
                .foregroundStyle(BrandColors.bluePrimary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let action {
                Button("Open Settings") {
                    action()
                }
                .buttonStyle(.appPrimary)
            }
        }
        .padding(20)
        .background(BrandTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: BrandTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BrandTheme.Radius.card, style: .continuous)
                .stroke(BrandTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// BarcodeScannerRepresentable declaration.
#if os(iOS)
private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: (String) -> Void
    let onError: (String) -> Void

    /// Handles makeCoordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onError: onError)
    }

    /// Handles makeUIViewController.
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.supportedSymbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        scanner.delegate = context.coordinator

        do {
            try scanner.startScanning()
        } catch {
            onError(error.localizedDescription)
        }

        return scanner
    }

    /// Handles updateUIViewController.
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) { }

    /// Handles dismantleUIViewController.
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    static let supportedSymbologies: [VNBarcodeSymbology] = [
        .qr,
        .aztec,
        .code128,
        .code39,
        .code93,
        .ean8,
        .ean13,
        .itf14,
        .pdf417,
        .upce,
        .dataMatrix
    ]

    /// Coordinator declaration.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScanned: (String) -> Void
        private let onError: (String) -> Void
        private var hasCapturedValue = false

        /// Initializes the instance.
        init(
            onScanned: @escaping (String) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onScanned = onScanned
            self.onError = onError
        }

        /// Handles dataScanner.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            process(items: [item])
        }

        /// Handles dataScanner.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            process(items: addedItems)
        }

        /// Handles dataScanner.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            onError(error.localizedDescription)
        }

        /// Handles process.
        private func process(items: [RecognizedItem]) {
            guard hasCapturedValue == false else {
                return
            }

            for item in items {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue,
                   payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    hasCapturedValue = true
                    onScanned(payload)
                    return
                }
            }
        }
    }
}
#endif

//endofline
