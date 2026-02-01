import SwiftUI
import UniformTypeIdentifiers

/// Document picker view for selecting PDF files from Files app or cloud storage.
/// Uses UIDocumentPickerViewController for system file picker integration.
struct PDFPickerView: UIViewControllerRepresentable {

    let onPDFSelected: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.pdf],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPDFSelected: onPDFSelected, onCancel: onCancel)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIDocumentPickerDelegate {

        let onPDFSelected: (URL) -> Void
        let onCancel: () -> Void

        init(
            onPDFSelected: @escaping (URL) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPDFSelected = onPDFSelected
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPDFSelected(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

// MARK: - Preview

#Preview {
    PDFPickerView(
        onPDFSelected: { _ in },
        onCancel: {}
    )
}
