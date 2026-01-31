import Foundation

/// Normalized bounding box coordinates (0.0-1.0 range)
/// Represents the position and size of a text element in an image
struct BoundingBox: Codable, Sendable, Equatable {
    let x: Double      // Left edge (0.0 = left, 1.0 = right)
    let y: Double      // Top edge (0.0 = top, 1.0 = bottom)
    let width: Double  // Width as fraction of page
    let height: Double // Height as fraction of page

    /// Check if this bbox is near another bbox (for context detection)
    func isNear(_ other: BoundingBox, threshold: Double = 0.1) -> Bool {
        let verticalDistance = abs(self.y - other.y)
        return verticalDistance < threshold
    }
}
