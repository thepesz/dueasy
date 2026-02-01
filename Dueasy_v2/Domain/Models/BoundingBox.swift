import Foundation

/// Normalized bounding box coordinates (0.0-1.0 range)
/// Represents the position and size of a text element in an image.
///
/// **COORDINATE SYSTEM (Top-Left Origin):**
/// This struct uses a **top-left origin** coordinate system:
/// - Origin (0,0) is at the **top-left** corner of the page
/// - X increases left-to-right (0.0 = left edge, 1.0 = right edge)
/// - Y increases top-to-bottom (0.0 = top edge, 1.0 = bottom edge)
///
/// **IMPORTANT - Vision Framework Conversion:**
/// Apple's Vision Framework uses a **bottom-left origin** (like Core Graphics):
/// - Origin (0,0) is at the **bottom-left** corner
/// - Y increases bottom-to-top
///
/// The conversion happens in `AppleVisionOCRService.performOCRPass()` where:
/// ```
/// // Vision: y is bottom edge, y + height is top edge
/// // Ours: y should be top edge in top-left system
/// let ourTop = 1.0 - (visionBottom + visionHeight)
/// ```
///
/// All code outside AppleVisionOCRService can safely assume top-left origin.
struct BoundingBox: Codable, Sendable, Equatable {
    let x: Double      // Left edge (0.0 = left, 1.0 = right)
    let y: Double      // Top edge (0.0 = top, 1.0 = bottom) - ALREADY CONVERTED from Vision
    let width: Double  // Width as fraction of page
    let height: Double // Height as fraction of page

    /// Right edge coordinate
    var maxX: Double { x + width }

    /// Bottom edge coordinate (y + height, where larger y = lower on page)
    var maxY: Double { y + height }

    /// Center X coordinate
    var centerX: Double { x + width / 2 }

    /// Center Y coordinate
    var centerY: Double { y + height / 2 }

    /// Area of the bounding box (for overlap calculations)
    var area: Double { width * height }

    /// Check if this bbox is near another bbox (for context detection)
    func isNear(_ other: BoundingBox, threshold: Double = 0.1) -> Bool {
        let verticalDistance = abs(self.y - other.y)
        return verticalDistance < threshold
    }

    /// Calculate overlap ratio with another bounding box.
    /// Returns a value between 0.0 (no overlap) and 1.0 (complete overlap).
    /// The ratio is calculated as: intersection area / smaller box area
    /// This ensures we detect when a smaller box is contained within a larger one.
    func overlapRatio(with other: BoundingBox) -> Double {
        // Calculate intersection
        let intersectMinX = max(self.x, other.x)
        let intersectMinY = max(self.y, other.y)
        let intersectMaxX = min(self.maxX, other.maxX)
        let intersectMaxY = min(self.maxY, other.maxY)

        // Check if there's no intersection
        if intersectMinX >= intersectMaxX || intersectMinY >= intersectMaxY {
            return 0.0
        }

        // Calculate intersection area
        let intersectionWidth = intersectMaxX - intersectMinX
        let intersectionHeight = intersectMaxY - intersectMinY
        let intersectionArea = intersectionWidth * intersectionHeight

        // Use the smaller box's area as denominator to detect containment
        let smallerArea = min(self.area, other.area)

        // Guard against zero area
        guard smallerArea > 0 else { return 0.0 }

        return intersectionArea / smallerArea
    }

    /// Check if this bbox overlaps with another beyond a threshold.
    /// Used for deduplication in 2-pass OCR.
    /// - Parameters:
    ///   - other: Another bounding box to compare
    ///   - threshold: Minimum overlap ratio (0.0-1.0) to consider as overlapping. Default 0.8 (80%)
    /// - Returns: True if overlap exceeds threshold
    func overlaps(with other: BoundingBox, threshold: Double = 0.8) -> Bool {
        return overlapRatio(with: other) >= threshold
    }

    /// Check if this bounding box is vertically aligned with another (same row).
    /// Useful for detecting text that's on the same line.
    func isOnSameRow(as other: BoundingBox, tolerance: Double = 0.02) -> Bool {
        // Check if the vertical centers are close
        return abs(self.centerY - other.centerY) < tolerance
    }

    /// Check if this bounding box is horizontally aligned with another (same column).
    /// Useful for detecting text that's in the same column.
    func isOnSameColumn(as other: BoundingBox, tolerance: Double = 0.02) -> Bool {
        // Check if the horizontal centers are close
        return abs(self.centerX - other.centerX) < tolerance
    }
}
