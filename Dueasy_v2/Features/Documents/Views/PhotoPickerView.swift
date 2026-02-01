import SwiftUI
import PhotosUI

/// Photo picker view using PHPickerViewController for selecting photos from the library.
/// Supports selecting multiple photos for multi-page document analysis.
struct PhotoPickerView: UIViewControllerRepresentable {

    let maxSelectionCount: Int
    let onPhotosSelected: ([UIImage]) -> Void
    let onCancel: () -> Void

    init(
        maxSelectionCount: Int = 10,
        onPhotosSelected: @escaping ([UIImage]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.maxSelectionCount = maxSelectionCount
        self.onPhotosSelected = onPhotosSelected
        self.onCancel = onCancel
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = maxSelectionCount
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPhotosSelected: onPhotosSelected, onCancel: onCancel)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        let onPhotosSelected: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(
            onPhotosSelected: @escaping ([UIImage]) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPhotosSelected = onPhotosSelected
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty {
                onCancel()
                return
            }

            // Load images asynchronously
            Task {
                var images: [UIImage] = []

                for result in results {
                    if let image = await loadImage(from: result) {
                        images.append(image)
                    }
                }

                await MainActor.run {
                    if images.isEmpty {
                        onCancel()
                    } else {
                        onPhotosSelected(images)
                    }
                }
            }
        }

        private func loadImage(from result: PHPickerResult) async -> UIImage? {
            let itemProvider = result.itemProvider

            guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
                return nil
            }

            return await withCheckedContinuation { continuation in
                itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let image = object as? UIImage {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoPickerView(
        onPhotosSelected: { _ in },
        onCancel: {}
    )
}
