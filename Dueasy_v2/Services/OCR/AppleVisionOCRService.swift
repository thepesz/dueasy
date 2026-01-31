import Foundation
import UIKit
import Vision
import CoreImage
import os.log

/// OCR service using Apple Vision framework.
/// Performs on-device text recognition with maximum accuracy.
///
/// Configuration:
/// - Recognition level: .accurate (not .fast) - critical for financial documents
/// - Language correction: enabled
/// - Recognition languages: Polish (primary), English (secondary)
/// - Minimum text height: 0.012 (filters out clutter, focuses on important text)
///
/// Image Pre-processing:
/// - Contrast enhancement (+20%) - makes text stand out
/// - Noise reduction - removes compression artifacts
/// - Sharpening - improves character edges
/// (VisionKit already handles: cropping, perspective correction, auto-crop)
final class AppleVisionOCRService: OCRServiceProtocol, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "OCR")
    // Polish first for better accuracy on Polish invoices
    private var _recognitionLanguages: [String] = ["pl-PL", "en-US"]

    init() {
        // Log supported languages on initialization
        logger.info("AppleVisionOCRService initialized")
        logger.info("Requested recognition languages: \(self._recognitionLanguages.joined(separator: ", "))")

        // Verify languages are supported
        let supported = Set(supportedLanguages)
        let unsupported = self._recognitionLanguages.filter { !supported.contains($0) }
        if !unsupported.isEmpty {
            logger.warning("Some requested languages are not supported: \(unsupported.joined(separator: ", "))")
        }
    }

    // MARK: - OCRServiceProtocol

    var supportedLanguages: [String] {
        // Check what Vision actually supports on this device
        if #available(iOS 16.0, *) {
            do {
                let request = VNRecognizeTextRequest()
                let supported = try request.supportedRecognitionLanguages()
                logger.info("Vision supported languages: \(supported.joined(separator: ", "))")
                return supported
            } catch {
                logger.error("Failed to get supported languages: \(error.localizedDescription)")
                // Fallback to common languages
                return ["en-US", "pl-PL", "de-DE", "fr-FR", "es-ES", "it-IT", "pt-PT"]
            }
        } else {
            // Pre-iOS 16 fallback
            return ["en-US", "pl-PL", "de-DE", "fr-FR", "es-ES", "it-IT", "pt-PT"]
        }
    }

    var recognitionLanguages: [String] {
        _recognitionLanguages
    }

    func setRecognitionLanguages(_ languages: [String]) {
        // Validate that requested languages are supported
        let supported = Set(supportedLanguages)
        let validLanguages = languages.filter { supported.contains($0) }

        if validLanguages.isEmpty {
            logger.warning("None of the requested languages are supported. Using default: pl-PL, en-US")
            _recognitionLanguages = ["pl-PL", "en-US"]
        } else {
            _recognitionLanguages = validLanguages
            logger.info("Recognition languages set to: \(validLanguages.joined(separator: ", "))")
        }
    }

    func recognizeText(from images: [UIImage]) async throws -> OCRResult {
        guard !images.isEmpty else {
            return OCRResult.empty
        }

        var allText: [String] = []
        var allConfidences: [Double] = []
        var allLineData: [OCRLineData] = []

        for (pageIndex, image) in images.enumerated() {
            let result = try await recognizeText(from: image, pageIndex: pageIndex)
            if result.hasText {
                allText.append(result.text)
                allConfidences.append(result.confidence)
                if let lineData = result.lineData {
                    allLineData.append(contentsOf: lineData)
                }
            }
        }

        let combinedText = allText.joined(separator: "\n\n")
        let averageConfidence = allConfidences.isEmpty ? 0.0 : allConfidences.reduce(0, +) / Double(allConfidences.count)

        return OCRResult(
            text: combinedText,
            confidence: averageConfidence,
            lineConfidences: allConfidences,
            lineData: allLineData.isEmpty ? nil : allLineData
        )
    }

    func recognizeText(from image: UIImage) async throws -> OCRResult {
        return try await recognizeText(from: image, pageIndex: 0)
    }

    private func recognizeText(from image: UIImage, pageIndex: Int) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw AppError.ocrFailed("Invalid image format")
        }

        // Pre-process image for better OCR results
        let processedImage = preprocessImage(cgImage)

        // 2-PASS OCR STRATEGY:
        // Pass A: Standard readable text (minTextHeight = 0.012)
        // Pass B: Small print for semantic keywords like "do zapłaty", "termin płatności" (minTextHeight = 0.007)
        // This ensures parser has both clean text AND critical semantic signals

        logger.info("Starting 2-pass OCR: Pass A (readable text) + Pass B (small print keywords)")

        // PASS A: Readable text
        let passAResult = try await performOCRPass(
            on: processedImage,
            pageIndex: pageIndex,
            minimumTextHeight: 0.012,
            passName: "A (readable)"
        )

        // PASS B: Small print (to capture "do zapłaty", "termin płatności", etc.)
        let passBResult = try await performOCRPass(
            on: processedImage,
            pageIndex: pageIndex,
            minimumTextHeight: 0.007,
            passName: "B (small print)"
        )

        // Combine both passes
        // Strategy: Use Pass A as primary text, append Pass B lines that weren't in Pass A
        let combinedText = combineOCRPasses(passA: passAResult, passB: passBResult)
        let combinedLineData = (passAResult.lineData ?? []) + (passBResult.lineData ?? [])

        // Use Pass A confidence as primary (more reliable)
        let finalConfidence = passAResult.confidence

        logger.info("2-pass OCR completed: Pass A (\(passAResult.lineData?.count ?? 0) lines), Pass B (\(passBResult.lineData?.count ?? 0) lines), Combined text length: \(combinedText.count) chars")

        return OCRResult(
            text: combinedText,
            confidence: finalConfidence,
            lineConfidences: passAResult.lineConfidences,
            lineData: combinedLineData.isEmpty ? nil : combinedLineData
        )
    }

    /// Perform a single OCR pass with specified minimum text height
    private func performOCRPass(
        on processedImage: CGImage,
        pageIndex: Int,
        minimumTextHeight: Float,
        passName: String
    ) async throws -> OCRResult {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { [pageIndex] request, error in
                if let error = error {
                    self.logger.error("OCR \(passName) error: \(error.localizedDescription)")
                    continuation.resume(throwing: AppError.ocrFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult.empty)
                    return
                }

                var lines: [String] = []
                var confidences: [Double] = []
                var lineDataArray: [OCRLineData] = []

                for observation in observations {
                    if let topCandidate = observation.topCandidates(1).first {
                        lines.append(topCandidate.string)
                        confidences.append(Double(topCandidate.confidence))

                        let bbox = observation.boundingBox
                        let normalizedBBox = BoundingBox(
                            x: Double(bbox.origin.x),
                            y: Double(bbox.origin.y),
                            width: Double(bbox.size.width),
                            height: Double(bbox.size.height)
                        )

                        let lineData = OCRLineData(
                            text: topCandidate.string,
                            pageIndex: pageIndex,
                            bbox: normalizedBBox,
                            confidence: Double(topCandidate.confidence)
                        )
                        lineDataArray.append(lineData)
                    }
                }

                let text = lines.joined(separator: "\n")
                let averageConfidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)

                self.logger.info("OCR pass \(passName) completed: \(lines.count) lines, confidence: \(averageConfidence)")

                let result = OCRResult(
                    text: text,
                    confidence: averageConfidence,
                    lineConfidences: confidences,
                    lineData: lineDataArray
                )

                continuation.resume(returning: result)
            }

            // Configure request
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = _recognitionLanguages
            request.minimumTextHeight = minimumTextHeight

            self.logger.info("OCR pass \(passName) configured: minTextHeight=\(minimumTextHeight)")

            // Perform request
            let handler = VNImageRequestHandler(cgImage: processedImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                logger.error("Failed to perform OCR pass \(passName): \(error.localizedDescription)")
                continuation.resume(throwing: AppError.ocrFailed(error.localizedDescription))
            }
        }
    }

    /// Combine two OCR passes intelligently
    /// Pass A: Primary readable text
    /// Pass B: Small print keywords
    /// Returns combined text with Pass A as base + unique lines from Pass B
    private func combineOCRPasses(passA: OCRResult, passB: OCRResult) -> String {
        // Normalize both texts for comparison (lowercase, trim)
        let passALines = Set(passA.text.components(separatedBy: "\n").map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })

        // Find unique lines from Pass B (not in Pass A)
        let passBLines = passB.text.components(separatedBy: "\n")
        let uniqueBLines = passBLines.filter { line in
            let normalized = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalized.isEmpty && !passALines.contains(normalized)
        }

        // Combine: Pass A text + unique small print from Pass B
        var combined = passA.text
        if !uniqueBLines.isEmpty {
            combined += "\n" + uniqueBLines.joined(separator: "\n")
            logger.info("Added \(uniqueBLines.count) unique small-print lines from Pass B")
        }

        return combined
    }

    // MARK: - Image Pre-processing

    /// Pre-processes image for optimal OCR results.
    ///
    /// Applies:
    /// - Contrast enhancement (makes text stand out from background)
    /// - Noise reduction (removes artifacts and compression noise)
    /// - Sharpening (improves character edges)
    ///
    /// Note: VisionKit already handles cropping and perspective correction
    /// from VNDocumentCameraViewController, so we only enhance the image quality.
    private func preprocessImage(_ cgImage: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: cgImage)
        var processedImage = ciImage

        // 1. Enhance contrast to make text more distinct from background
        // This is especially helpful for faded invoices or poor lighting
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(processedImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.2, forKey: kCIInputContrastKey) // 20% increase
            contrastFilter.setValue(1.05, forKey: kCIInputSaturationKey) // Slight saturation boost
            if let output = contrastFilter.outputImage {
                processedImage = output
            }
        }

        // 2. Reduce noise (compression artifacts, paper texture)
        if let noiseFilter = CIFilter(name: "CINoiseReduction") {
            noiseFilter.setValue(processedImage, forKey: kCIInputImageKey)
            noiseFilter.setValue(0.02, forKey: "inputNoiseLevel") // Gentle noise reduction
            noiseFilter.setValue(0.4, forKey: "inputSharpness") // Maintain sharpness
            if let output = noiseFilter.outputImage {
                processedImage = output
            }
        }

        // 3. Sharpen edges for better character recognition
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(processedImage, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.4, forKey: kCIInputSharpnessKey) // Moderate sharpening
            if let output = sharpenFilter.outputImage {
                processedImage = output
            }
        }

        // Convert back to CGImage
        let context = CIContext(options: [.useSoftwareRenderer: false])
        if let outputCGImage = context.createCGImage(processedImage, from: processedImage.extent) {
            logger.info("Image pre-processing applied: contrast +20%, noise reduction, sharpening")
            return outputCGImage
        } else {
            logger.warning("Failed to convert CIImage back to CGImage, using original")
            return cgImage
        }
    }
}
