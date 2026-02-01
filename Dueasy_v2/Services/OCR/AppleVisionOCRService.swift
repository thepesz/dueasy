import Foundation
import UIKit
import Vision
import CoreImage
import os

/// OCR service using Apple Vision framework with 2-pass recognition.
/// Performs on-device text recognition with maximum accuracy for financial documents.
///
/// **2-Pass OCR Strategy:**
/// - Pass 1 (Standard): minTextHeight = 0.012 - Captures normal-sized readable text
/// - Pass 2 (Sensitive): minTextHeight = 0.007 - Captures fine print, labels, table headers
///
/// **Image Pre-processing Pipeline:**
/// 1. Deskew (straighten) - corrects rotated/skewed scans
/// 2. Contrast enhancement (+20%) - makes text stand out
/// 3. Noise reduction - removes compression artifacts
/// 4. Sharpening - improves character edges
///
/// **Merge Strategy:**
/// - Deduplicate by bounding box overlap (>80%) and text similarity (>60%)
/// - Keep higher confidence result when duplicates found
/// - Sort final results by Y position (top to bottom), then X (left to right)
///
/// PRIVACY: Uses PrivacyLogger to ensure no raw OCR text is logged.
/// Only metrics (line counts, confidence scores, durations) are logged.
///
/// Note: VisionKit already handles cropping and perspective correction
final class AppleVisionOCRService: OCRServiceProtocol, @unchecked Sendable {
    // Polish first for better accuracy on Polish invoices
    private var _recognitionLanguages: [String] = ["pl-PL", "en-US"]

    // MARK: - OCR Pass Configuration

    /// Standard pass configuration for normal readable text
    private let standardPassConfig = OCRPassConfig(
        minimumTextHeight: 0.012,
        passName: "Standard",
        source: .standard
    )

    /// Sensitive pass configuration for fine print and small text
    private let sensitivePassConfig = OCRPassConfig(
        minimumTextHeight: 0.007,
        passName: "Sensitive",
        source: .sensitive
    )

    /// Configuration for an OCR pass
    private struct OCRPassConfig {
        let minimumTextHeight: Float
        let passName: String
        let source: OCRPassSource
    }

    // MARK: - Preprocessing Statistics

    /// Statistics from preprocessing for debugging
    struct PreprocessingStats {
        var deskewApplied: Bool = false
        var deskewAngle: Double = 0.0
        var contrastEnhanced: Bool = false
        var noiseReduced: Bool = false
        var sharpened: Bool = false
        var documentCropped: Bool = false
    }

    // MARK: - Initialization

    init() {
        // Log initialization metrics (no PII)
        PrivacyLogger.ocr.info("AppleVisionOCRService initialized with 2-pass recognition")
        PrivacyLogger.ocr.info("Recognition languages: \(self._recognitionLanguages.joined(separator: ", "))")
        PrivacyLogger.ocr.debug("Standard pass minTextHeight: \(self.standardPassConfig.minimumTextHeight)")
        PrivacyLogger.ocr.debug("Sensitive pass minTextHeight: \(self.sensitivePassConfig.minimumTextHeight)")

        // Verify languages are supported
        let supported = Set(supportedLanguages)
        let unsupported = self._recognitionLanguages.filter { !supported.contains($0) }
        if !unsupported.isEmpty {
            PrivacyLogger.ocr.warning("Some requested languages not supported: \(unsupported.joined(separator: ", "))")
        }
    }

    // MARK: - OCRServiceProtocol

    var supportedLanguages: [String] {
        // Check what Vision actually supports on this device
        if #available(iOS 16.0, *) {
            do {
                let request = VNRecognizeTextRequest()
                let supported = try request.supportedRecognitionLanguages()
                PrivacyLogger.ocr.debug("Vision supported languages: \(supported.count) languages")
                return supported
            } catch {
                PrivacyLogger.ocr.error("Failed to get supported languages: \(error.localizedDescription)")
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
            PrivacyLogger.ocr.warning("None of the requested languages are supported. Using default: pl-PL, en-US")
            _recognitionLanguages = ["pl-PL", "en-US"]
        } else {
            _recognitionLanguages = validLanguages
            PrivacyLogger.ocr.info("Recognition languages set to: \(validLanguages.joined(separator: ", "))")
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

        // Step 1: Pre-process image for better OCR results
        var stats = PreprocessingStats()
        let processedImage = preprocessImageEnhanced(cgImage, stats: &stats)

        logPreprocessingStats(stats)

        // Step 2: Perform 2-pass OCR
        PrivacyLogger.ocr.info("Starting 2-pass OCR: Standard + Sensitive passes")

        // PASS 1: Standard - readable text
        let pass1Result = try await performOCRPass(
            on: processedImage,
            pageIndex: pageIndex,
            config: standardPassConfig
        )

        // PASS 2: Sensitive - fine print, labels, table headers
        let pass2Result = try await performOCRPass(
            on: processedImage,
            pageIndex: pageIndex,
            config: sensitivePassConfig
        )

        // Step 3: Merge and deduplicate results
        let mergedResult = mergeAndDeduplicateResults(
            standardResult: pass1Result,
            sensitiveResult: pass2Result
        )

        // PRIVACY: Log only metrics, not content
        PrivacyLogger.logOCRMetrics(
            lineCount: mergedResult.lineData?.count ?? 0,
            confidence: mergedResult.confidence,
            duration: 0 // Duration tracked externally
        )

        return mergedResult
    }

    /// Log preprocessing statistics for debugging
    private func logPreprocessingStats(_ stats: PreprocessingStats) {
        var applied: [String] = []
        if stats.deskewApplied {
            applied.append("deskew(\(String(format: "%.2f", stats.deskewAngle))deg)")
        }
        if stats.contrastEnhanced { applied.append("contrast") }
        if stats.noiseReduced { applied.append("denoise") }
        if stats.sharpened { applied.append("sharpen") }
        if stats.documentCropped { applied.append("crop") }

        if applied.isEmpty {
            PrivacyLogger.ocr.debug("Preprocessing: none applied")
        } else {
            PrivacyLogger.ocr.debug("Preprocessing applied: \(applied.joined(separator: ", "))")
        }
    }

    /// Perform a single OCR pass with specified configuration
    private func performOCRPass(
        on processedImage: CGImage,
        pageIndex: Int,
        config: OCRPassConfig
    ) async throws -> OCRResult {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { [pageIndex, config] request, error in
                if let error = error {
                    PrivacyLogger.ocr.error("OCR pass error: \(error.localizedDescription)")
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

                        // COORDINATE SYSTEM CONVERSION:
                        // Vision Framework uses bottom-left origin (y=0 at bottom, y=1 at top)
                        // Our app uses top-left origin (y=0 at top, y=1 at bottom)
                        // We must flip the Y axis here at the source.
                        //
                        // In Vision coordinates:
                        //   - bbox.origin.y is the BOTTOM edge of the text
                        //   - bbox.origin.y + bbox.size.height is the TOP edge
                        //
                        // In our app coordinates:
                        //   - y should represent the TOP edge of the text
                        //   - To convert: ourTop = 1.0 - visionTop = 1.0 - (visionBottom + height)
                        let visionBbox = observation.boundingBox
                        let visionBottom = Double(visionBbox.origin.y)
                        let visionHeight = Double(visionBbox.size.height)
                        let visionTop = visionBottom + visionHeight
                        let ourTop = 1.0 - visionTop  // Flip Y axis: top in Vision becomes our y origin

                        let normalizedBBox = BoundingBox(
                            x: Double(visionBbox.origin.x),
                            y: ourTop,  // Now y represents TOP edge in top-left coordinate system
                            width: Double(visionBbox.size.width),
                            height: visionHeight
                        )

                        let lineData = OCRLineData(
                            text: topCandidate.string,
                            pageIndex: pageIndex,
                            bbox: normalizedBBox,
                            confidence: Double(topCandidate.confidence),
                            source: config.source
                        )
                        lineDataArray.append(lineData)
                    }
                }

                let text = lines.joined(separator: "\n")
                let averageConfidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)

                // PRIVACY: Log metrics only, not text content
                PrivacyLogger.logOCRPassMetrics(passName: config.passName, lineCount: lines.count, confidence: averageConfidence)

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
            request.minimumTextHeight = config.minimumTextHeight

            PrivacyLogger.ocr.debug("OCR pass \(config.passName) configured: minTextHeight=\(config.minimumTextHeight)")

            // Perform request
            let handler = VNImageRequestHandler(cgImage: processedImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                PrivacyLogger.ocr.error("Failed to perform OCR pass: \(error.localizedDescription)")
                continuation.resume(throwing: AppError.ocrFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Merge and Deduplication

    /// Merge results from standard and sensitive passes, deduplicating overlapping lines.
    /// - Parameters:
    ///   - standardResult: Results from standard (larger text) pass
    ///   - sensitiveResult: Results from sensitive (fine text) pass
    /// - Returns: Merged OCRResult with deduplicated lines sorted by position
    private func mergeAndDeduplicateResults(
        standardResult: OCRResult,
        sensitiveResult: OCRResult
    ) -> OCRResult {
        let standardLines = standardResult.lineData ?? []
        let sensitiveLines = sensitiveResult.lineData ?? []

        PrivacyLogger.ocr.debug("Merging: Standard=\(standardLines.count) lines, Sensitive=\(sensitiveLines.count) lines")

        // Start with all standard lines (these are typically higher quality)
        var mergedLines: [OCRLineData] = standardLines

        // Track how many duplicates we find
        var duplicatesFound = 0
        var newLinesAdded = 0

        // Add sensitive lines that don't duplicate standard lines
        for sensitiveLine in sensitiveLines {
            var isDuplicate = false
            var duplicateIndex: Int?

            // Check against existing merged lines
            for (index, existingLine) in mergedLines.enumerated() {
                if sensitiveLine.isDuplicate(of: existingLine) {
                    isDuplicate = true
                    duplicateIndex = index

                    // If sensitive line has higher confidence, replace
                    // PRIVACY: Do not log actual text content
                    if sensitiveLine.confidence > existingLine.confidence {
                        mergedLines[index] = OCRLineData(
                            text: sensitiveLine.text,
                            pageIndex: sensitiveLine.pageIndex,
                            bbox: sensitiveLine.bbox,
                            confidence: sensitiveLine.confidence,
                            source: .merged
                        )
                    }
                    break
                }
            }

            if isDuplicate {
                duplicatesFound += 1
            } else {
                // This is a new line from sensitive pass (fine print captured)
                // PRIVACY: Do not log actual text content
                mergedLines.append(sensitiveLine)
                newLinesAdded += 1
            }
        }

        // Sort by position: Y (top to bottom), then X (left to right)
        // After coordinate conversion, y now represents TOP edge in top-left origin:
        //   - Smaller y = higher on page (closer to top)
        //   - Larger y = lower on page (closer to bottom)
        // So we sort ascending by y for top-to-bottom reading order.
        let sortedLines = mergedLines.sorted { line1, line2 in
            // Primary: Sort by Y (ascending - smaller y first for top-to-bottom reading)
            if abs(line1.bbox.y - line2.bbox.y) > 0.01 {
                return line1.bbox.y < line2.bbox.y
            }
            // Secondary: Sort by X (ascending - left to right)
            return line1.bbox.x < line2.bbox.x
        }

        // Combine text in reading order
        let combinedText = sortedLines.map { $0.text }.joined(separator: "\n")
        let confidences = sortedLines.map { $0.confidence }
        let averageConfidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Double(confidences.count)

        PrivacyLogger.ocr.info("Merge complete: \(duplicatesFound) duplicates removed, \(newLinesAdded) new lines added, \(sortedLines.count) total")

        return OCRResult(
            text: combinedText,
            confidence: averageConfidence,
            lineConfidences: confidences,
            lineData: sortedLines
        )
    }

    // MARK: - Enhanced Image Pre-processing

    /// Pre-processes image for optimal OCR results with full preprocessing pipeline.
    ///
    /// Pipeline:
    /// 1. Deskew (straighten) - corrects rotated/skewed scans
    /// 2. Contrast enhancement - makes text stand out from background
    /// 3. Noise reduction - removes compression artifacts
    /// 4. Sharpening - improves character edges
    ///
    /// Note: VisionKit already handles cropping and perspective correction
    /// from VNDocumentCameraViewController, so we focus on quality enhancement.
    private func preprocessImageEnhanced(_ cgImage: CGImage, stats: inout PreprocessingStats) -> CGImage {
        var ciImage = CIImage(cgImage: cgImage)

        // Step 1: Deskew (straighten) the image if needed
        if let (deskewedImage, angle) = deskewImage(ciImage) {
            ciImage = deskewedImage
            stats.deskewApplied = true
            stats.deskewAngle = angle
        }

        // Step 2: Enhance contrast (gentle - 20% increase)
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(ciImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.2, forKey: kCIInputContrastKey)
            contrastFilter.setValue(1.0, forKey: kCIInputSaturationKey) // Keep saturation neutral
            contrastFilter.setValue(0.0, forKey: kCIInputBrightnessKey) // Keep brightness neutral
            if let output = contrastFilter.outputImage {
                ciImage = output
                stats.contrastEnhanced = true
            }
        }

        // Step 3: Reduce noise (gentle - for compression artifacts)
        if let noiseFilter = CIFilter(name: "CINoiseReduction") {
            noiseFilter.setValue(ciImage, forKey: kCIInputImageKey)
            noiseFilter.setValue(0.02, forKey: "inputNoiseLevel")
            noiseFilter.setValue(0.4, forKey: "inputSharpness")
            if let output = noiseFilter.outputImage {
                ciImage = output
                stats.noiseReduced = true
            }
        }

        // Step 4: Sharpen luminance (gentle - improves text edges)
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(ciImage, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.3, forKey: kCIInputSharpnessKey) // Gentle sharpening
            if let output = sharpenFilter.outputImage {
                ciImage = output
                stats.sharpened = true
            }
        }

        // Convert back to CGImage
        let context = CIContext(options: [.useSoftwareRenderer: false])
        if let outputCGImage = context.createCGImage(ciImage, from: ciImage.extent) {
            return outputCGImage
        } else {
            PrivacyLogger.ocr.warning("Failed to convert CIImage back to CGImage, using original")
            return cgImage
        }
    }

    /// Detect and correct document skew using text line detection.
    /// Returns the deskewed image and the rotation angle applied.
    private func deskewImage(_ ciImage: CIImage) -> (CIImage, Double)? {
        // Convert to CGImage for Vision
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        // Use VNDetectTextRectanglesRequest to find text line angles
        var detectedAngles: [Double] = []

        let request = VNDetectTextRectanglesRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNTextObservation] else {
                return
            }

            for observation in observations {
                // Calculate angle from bounding box
                // If the box is rotated, we can estimate the skew
                let box = observation.boundingBox

                // For significant text boxes, estimate rotation from aspect ratio changes
                // This is a simplified heuristic - text boxes should be roughly horizontal
                if box.width > 0.1 && box.height > 0.01 {
                    // The bounding box is axis-aligned, so we can't directly measure rotation
                    // Instead, we'll use document segmentation for more accurate deskew
                }
            }
        }

        request.reportCharacterBoxes = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        // Use VNDetectDocumentSegmentationRequest for more accurate deskew detection
        if #available(iOS 15.0, *) {
            return detectDocumentSkew(ciImage)
        }

        return nil
    }

    /// Detect document skew using document segmentation (iOS 15+)
    @available(iOS 15.0, *)
    private func detectDocumentSkew(_ ciImage: CIImage) -> (CIImage, Double)? {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        var skewAngle: Double = 0.0

        let request = VNDetectDocumentSegmentationRequest { request, error in
            guard error == nil,
                  let observation = request.results?.first as? VNRectangleObservation else {
                return
            }

            // Calculate skew from the detected document corners
            let topLeft = observation.topLeft
            let topRight = observation.topRight

            // Calculate angle of top edge
            let dx = topRight.x - topLeft.x
            let dy = topRight.y - topLeft.y
            let angle = atan2(dy, dx) * 180.0 / .pi

            // Only correct if skew is significant but not too extreme
            if abs(angle) > 0.5 && abs(angle) < 15.0 {
                skewAngle = angle
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        // Apply rotation if needed
        if abs(skewAngle) > 0.5 {
            let radians = -skewAngle * .pi / 180.0
            let transform = CGAffineTransform(rotationAngle: radians)
            let rotatedImage = ciImage.transformed(by: transform)

            PrivacyLogger.ocr.debug("Deskew applied: \(String(format: "%.2f", skewAngle)) degrees")
            return (rotatedImage, skewAngle)
        }

        return nil
    }

    /// Detect and crop to document boundaries (optional enhancement).
    /// Uses VNDetectRectanglesRequest to find document edges.
    private func detectAndCropDocument(_ ciImage: CIImage) -> CIImage? {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        var croppedImage: CIImage?

        let request = VNDetectRectanglesRequest { request, error in
            guard error == nil,
                  let observation = request.results?.first as? VNRectangleObservation else {
                return
            }

            // Only crop if the detected rectangle is significantly smaller than the image
            let area = observation.boundingBox.width * observation.boundingBox.height
            if area > 0.5 && area < 0.95 {
                // Apply perspective correction using CIPerspectiveCorrection
                if let filter = CIFilter(name: "CIPerspectiveCorrection") {
                    let extent = ciImage.extent

                    // Convert normalized coordinates to image coordinates
                    let topLeft = CGPoint(
                        x: observation.topLeft.x * extent.width,
                        y: observation.topLeft.y * extent.height
                    )
                    let topRight = CGPoint(
                        x: observation.topRight.x * extent.width,
                        y: observation.topRight.y * extent.height
                    )
                    let bottomLeft = CGPoint(
                        x: observation.bottomLeft.x * extent.width,
                        y: observation.bottomLeft.y * extent.height
                    )
                    let bottomRight = CGPoint(
                        x: observation.bottomRight.x * extent.width,
                        y: observation.bottomRight.y * extent.height
                    )

                    filter.setValue(ciImage, forKey: kCIInputImageKey)
                    filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
                    filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
                    filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
                    filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

                    croppedImage = filter.outputImage
                }
            }
        }

        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.5
        request.minimumSize = 0.3
        request.maximumObservations = 1

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        return croppedImage
    }
}
