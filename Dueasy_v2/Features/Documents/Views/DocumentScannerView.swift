import SwiftUI
import VisionKit
import os.log

/// Document scanner view using VisionKit's VNDocumentCameraViewController.
///
/// This provides the same professional document scanning experience as the Notes app:
/// - Automatic edge detection and perspective correction
/// - Auto-cropping to document bounds (removes background)
/// - Contrast enhancement and glare reduction
/// - Live guidance for optimal positioning
/// - Multi-page scanning support
///
/// This is MUCH better than regular photos because:
/// - Photos have poor contrast and lighting issues
/// - Photos include background clutter
/// - Photos have perspective distortion
/// - Photos don't get automatic enhancement
///
/// VNDocumentCameraViewController returns processed images optimized for OCR.
struct DocumentScannerView: View {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "Scanner")

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let documentType: DocumentType
    let onScanComplete: ([UIImage]) -> Void
    let onCancel: () -> Void

    var body: some View {
        // VNDocumentCameraViewController is available on iOS 13+
        // It provides the same document scanning experience as the Notes app:
        // - Automatic edge detection and perspective correction
        // - Auto-cropping to document bounds
        // - Contrast enhancement and glare reduction
        // - Much better quality than regular photos
        if VNDocumentCameraViewController.isSupported {
            DocumentCameraViewControllerRepresentable(
                onScanComplete: onScanComplete,
                onCancel: onCancel
            )
            .ignoresSafeArea()
        } else {
            // Fallback for devices without document scanner (very rare on iOS 13+)
            VStack(spacing: Spacing.lg) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Scanner Not Available")
                    .font(Typography.title2)

                Text("Document scanning requires iOS 13 or later.")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                PrimaryButton.secondary("Cancel") {
                    onCancel()
                }
            }
            .padding(Spacing.xl)
        }
    }
}

// MARK: - VisionKit Wrapper

struct DocumentCameraViewControllerRepresentable: UIViewControllerRepresentable {

    let onScanComplete: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator

        // Log that we're using the proper document scanner
        let logger = Logger(subsystem: "com.dueasy.app", category: "Scanner")
        logger.info("Initialized VNDocumentCameraViewController (VisionKit document scanner)")
        logger.info("Scanner provides: edge detection, perspective correction, contrast enhancement")

        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanComplete: onScanComplete, onCancel: onCancel)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanComplete: ([UIImage]) -> Void
        let onCancel: () -> Void
        private let logger = Logger(subsystem: "com.dueasy.app", category: "Scanner")

        init(onScanComplete: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScanComplete = onScanComplete
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Extract all scanned pages
            // These images are already processed by VisionKit with:
            // - Perspective correction
            // - Edge detection and cropping
            // - Contrast enhancement
            var images: [UIImage] = []
            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                images.append(image)
            }

            logger.info("Document scan completed: \(scan.pageCount) page(s) scanned")
            logger.info("Images are pre-processed by VisionKit for optimal OCR quality")

            onScanComplete(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            logger.info("Document scan cancelled by user")
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            logger.error("Document scanner error: \(error.localizedDescription)")
            onCancel()
        }
    }
}

// MARK: - Preview

#Preview {
    DocumentScannerView(
        documentType: .invoice,
        onScanComplete: { _ in },
        onCancel: {}
    )
    .environment(AppEnvironment.preview)
}
