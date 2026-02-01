import Foundation
import os.log

// NOTE: DocumentRegion is defined in Domain/Models/KeywordModels.swift
// with 9 regions for the 3x3 grid layout analysis.

// MARK: - Layout Row

/// A horizontal grouping of OCR lines at similar Y coordinates.
/// Represents a "row" of text in the document layout.
/// Named LayoutRow to avoid conflict with LayoutRow (SwiftUI component).
struct LayoutRow: Sendable {
    /// Lines in this row, sorted left-to-right by X coordinate
    let lines: [OCRLineData]

    /// Vertical center of the row (normalized 0.0-1.0)
    let yCenter: Double

    /// Vertical range covered by this row
    let yRange: ClosedRange<Double>

    /// Combined text of all lines in row, left to right
    var combinedText: String {
        lines.sorted { $0.bbox.x < $1.bbox.x }
            .map { $0.text }
            .joined(separator: " ")
    }

    /// Leftmost X coordinate in the row
    var minX: Double {
        lines.map { $0.bbox.x }.min() ?? 0.0
    }

    /// Rightmost X coordinate in the row
    var maxX: Double {
        lines.map { $0.bbox.maxX }.max() ?? 1.0
    }

    /// Average OCR confidence for lines in this row
    var averageConfidence: Double {
        guard !lines.isEmpty else { return 0.0 }
        return lines.map { $0.confidence }.reduce(0, +) / Double(lines.count)
    }
}

// MARK: - Layout Column

/// A vertical grouping of OCR lines at similar X coordinates.
/// Represents a "column" of text in the document layout.
struct LayoutColumn: Sendable {
    /// Lines in this column, sorted top-to-bottom by Y coordinate
    let lines: [OCRLineData]

    /// Horizontal center of the column (normalized 0.0-1.0)
    let xCenter: Double

    /// Horizontal range covered by this column
    let xRange: ClosedRange<Double>

    /// Combined text of all lines in column, top to bottom
    var combinedText: String {
        lines.sorted { $0.bbox.y < $1.bbox.y }
            .map { $0.text }
            .joined(separator: "\n")
    }

    /// Topmost Y coordinate in the column
    var minY: Double {
        lines.map { $0.bbox.y }.min() ?? 0.0
    }

    /// Bottommost Y coordinate in the column
    var maxY: Double {
        lines.map { $0.bbox.maxY }.max() ?? 1.0
    }
}

// MARK: - Layout Block

/// A region-based grouping of OCR lines.
/// Represents one of the 9 regions in the document grid.
struct LayoutBlock: Sendable {
    /// The region this block represents
    let region: DocumentRegion

    /// All lines within this region
    let lines: [OCRLineData]

    /// Lines organized into horizontal rows
    let rows: [LayoutRow]

    /// Combined text of the entire block
    var combinedText: String {
        rows.map { $0.combinedText }.joined(separator: "\n")
    }

    /// Whether this block contains any text
    var isEmpty: Bool {
        lines.isEmpty
    }

    /// Number of lines in this block
    var lineCount: Int {
        lines.count
    }

    /// Average OCR confidence for this block
    var averageConfidence: Double {
        guard !lines.isEmpty else { return 0.0 }
        return lines.map { $0.confidence }.reduce(0, +) / Double(lines.count)
    }
}

// MARK: - Layout Analysis Result

/// Complete layout analysis of a document.
/// Contains rows, columns, and region-based blocks for spatial extraction.
struct LayoutAnalysis: Sendable {
    /// All lines from the document
    let allLines: [OCRLineData]

    /// Lines grouped into horizontal rows
    let rows: [LayoutRow]

    /// Lines grouped into vertical columns
    let columns: [LayoutColumn]

    /// Lines partitioned into 9-region blocks
    let blocks: [DocumentRegion: LayoutBlock]

    /// Page dimensions used for analysis (for multi-page support)
    let pageCount: Int

    /// Row grouping tolerance used
    let rowTolerance: Double

    /// Column clustering threshold used
    let columnThreshold: Double

    // MARK: - Convenience Accessors

    /// Get block for a specific region
    func block(for region: DocumentRegion) -> LayoutBlock? {
        blocks[region]
    }

    /// Get all lines in a region
    func lines(in region: DocumentRegion) -> [OCRLineData] {
        blocks[region]?.lines ?? []
    }

    /// Get lines near a specific Y coordinate (within tolerance)
    func lines(nearY y: Double, tolerance: Double = 0.02) -> [OCRLineData] {
        allLines.filter { abs($0.bbox.centerY - y) < tolerance }
    }

    /// Get lines in the same row as a reference line
    func linesInSameRow(as line: OCRLineData, tolerance: Double = 0.02) -> [OCRLineData] {
        allLines.filter { $0.bbox.isOnSameRow(as: line.bbox, tolerance: tolerance) }
    }

    /// Get lines below a reference line (within vertical distance)
    func linesBelow(_ line: OCRLineData, maxDistance: Double = 0.05) -> [OCRLineData] {
        allLines.filter { other in
            let yDistance = other.bbox.y - line.bbox.maxY
            return yDistance > 0 && yDistance < maxDistance
        }.sorted { $0.bbox.y < $1.bbox.y }
    }

    /// Get lines to the right of a reference line (same row)
    func linesToRight(of line: OCRLineData, tolerance: Double = 0.02) -> [OCRLineData] {
        linesInSameRow(as: line, tolerance: tolerance)
            .filter { $0.bbox.x > line.bbox.maxX }
            .sorted { $0.bbox.x < $1.bbox.x }
    }

    /// Get lines in the same column as a reference line
    func linesInSameColumn(as line: OCRLineData, tolerance: Double = 0.05) -> [OCRLineData] {
        allLines.filter { $0.bbox.isOnSameColumn(as: line.bbox, tolerance: tolerance) }
    }

    /// Find the row containing a specific line
    func row(containing line: OCRLineData) -> LayoutRow? {
        rows.first { row in
            row.lines.contains { $0.text == line.text && $0.bbox == line.bbox }
        }
    }

    /// Determine which region a line belongs to
    func region(for line: OCRLineData) -> DocumentRegion {
        let x = line.bbox.centerX
        let y = line.bbox.centerY

        let xRegion: Int
        if x < 0.33 {
            xRegion = 0 // Left
        } else if x < 0.67 {
            xRegion = 1 // Center
        } else {
            xRegion = 2 // Right
        }

        let yRegion: Int
        if y < 0.33 {
            yRegion = 0 // Top
        } else if y < 0.67 {
            yRegion = 1 // Middle
        } else {
            yRegion = 2 // Bottom
        }

        let regionIndex = yRegion * 3 + xRegion
        return DocumentRegion.allCases[regionIndex]
    }
}

// MARK: - Layout Analyzer

/// Analyzes document spatial structure for layout-first parsing.
/// Groups OCR lines into rows, columns, and regional blocks.
///
/// **COORDINATE SYSTEM ASSUMPTION:**
/// This analyzer assumes a **top-left origin** coordinate system:
/// - Y = 0.0 is the TOP of the page
/// - Y = 1.0 is the BOTTOM of the page
/// - Smaller Y values = higher on page (toward top)
/// - Larger Y values = lower on page (toward bottom)
///
/// The coordinate conversion from Vision's bottom-left origin happens
/// in `AppleVisionOCRService` before lines reach this analyzer.
/// All BoundingBox coordinates here are already normalized to top-left origin.
final class LayoutAnalyzer: Sendable {

    private let logger = Logger(subsystem: "com.dueasy.app", category: "LayoutAnalyzer")

    /// Default row grouping tolerance (normalized Y distance)
    static let defaultRowTolerance: Double = 0.02

    /// Default column threshold for K-means clustering
    static let defaultColumnThreshold: Double = 0.15

    /// Region boundary thresholds (divide document into thirds)
    static let regionThresholdLow: Double = 0.33
    static let regionThresholdHigh: Double = 0.67

    // MARK: - Main Analysis

    /// Analyze document layout from OCR line data.
    /// - Parameters:
    ///   - lines: OCR line data with bounding boxes
    ///   - rowTolerance: Y-distance tolerance for row grouping (default 0.02)
    ///   - columnThreshold: X-distance threshold for column detection (default 0.15)
    /// - Returns: Complete layout analysis with rows, columns, and blocks
    func analyzeLayout(
        lines: [OCRLineData],
        rowTolerance: Double = defaultRowTolerance,
        columnThreshold: Double = defaultColumnThreshold
    ) -> LayoutAnalysis {
        guard !lines.isEmpty else {
            logger.debug("No lines to analyze")
            return LayoutAnalysis(
                allLines: [],
                rows: [],
                columns: [],
                blocks: [:],
                pageCount: 0,
                rowTolerance: rowTolerance,
                columnThreshold: columnThreshold
            )
        }

        logger.info("Analyzing layout for \(lines.count) lines")

        // Step 1: Group lines into rows
        let rows = groupIntoRows(lines: lines, tolerance: rowTolerance)
        logger.debug("Grouped into \(rows.count) rows")

        // Step 2: Detect columns
        let columns = detectColumns(lines: lines, threshold: columnThreshold)
        logger.debug("Detected \(columns.count) columns")

        // Step 3: Partition into regional blocks
        let blocks = partitionIntoBlocks(lines: lines, rows: rows)
        logger.debug("Partitioned into \(blocks.count) non-empty blocks")

        // Log block distribution
        for (region, block) in blocks.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if !block.isEmpty {
                logger.debug("Block \(region.rawValue): \(block.lineCount) lines")
            }
        }

        // Determine page count
        let pageCount = (lines.map { $0.pageIndex }.max() ?? 0) + 1

        return LayoutAnalysis(
            allLines: lines,
            rows: rows,
            columns: columns,
            blocks: blocks,
            pageCount: pageCount,
            rowTolerance: rowTolerance,
            columnThreshold: columnThreshold
        )
    }

    // MARK: - Row Grouping

    /// Group lines into horizontal rows based on Y coordinate similarity.
    /// - Parameters:
    ///   - lines: OCR lines to group
    ///   - tolerance: Maximum Y-distance between lines in the same row
    /// - Returns: Array of LayoutRow, sorted top to bottom
    func groupIntoRows(lines: [OCRLineData], tolerance: Double = defaultRowTolerance) -> [LayoutRow] {
        guard !lines.isEmpty else { return [] }

        // Sort lines by Y coordinate (top to bottom)
        let sortedLines = lines.sorted { $0.bbox.centerY < $1.bbox.centerY }

        var rows: [LayoutRow] = []
        var currentRowLines: [OCRLineData] = []
        var currentRowYCenter: Double = sortedLines[0].bbox.centerY

        for line in sortedLines {
            let lineYCenter = line.bbox.centerY

            if abs(lineYCenter - currentRowYCenter) <= tolerance {
                // Same row
                currentRowLines.append(line)
            } else {
                // New row - save current row
                if !currentRowLines.isEmpty {
                    let row = createRow(from: currentRowLines)
                    rows.append(row)
                }
                // Start new row
                currentRowLines = [line]
                currentRowYCenter = lineYCenter
            }
        }

        // Don't forget the last row
        if !currentRowLines.isEmpty {
            let row = createRow(from: currentRowLines)
            rows.append(row)
        }

        return rows
    }

    private func createRow(from lines: [OCRLineData]) -> LayoutRow {
        let sortedLines = lines.sorted { $0.bbox.x < $1.bbox.x }
        let yCenters = sortedLines.map { $0.bbox.centerY }
        let yCenter = yCenters.reduce(0, +) / Double(yCenters.count)

        let minY = sortedLines.map { $0.bbox.y }.min() ?? 0.0
        let maxY = sortedLines.map { $0.bbox.maxY }.max() ?? 1.0

        return LayoutRow(
            lines: sortedLines,
            yCenter: yCenter,
            yRange: minY...maxY
        )
    }

    // MARK: - Column Detection

    /// Detect vertical columns using clustering on X coordinates.
    /// - Parameters:
    ///   - lines: OCR lines to analyze
    ///   - threshold: Minimum X-distance between columns
    /// - Returns: Array of LayoutColumn, sorted left to right
    func detectColumns(lines: [OCRLineData], threshold: Double = defaultColumnThreshold) -> [LayoutColumn] {
        guard !lines.isEmpty else { return [] }

        // Extract X centers and sort
        let xCenters = lines.map { ($0, $0.bbox.centerX) }
            .sorted { $0.1 < $1.1 }

        // Simple clustering: group lines with similar X centers
        var columns: [[OCRLineData]] = []
        var currentColumn: [OCRLineData] = []
        var currentXCenter: Double = xCenters[0].1

        for (line, xCenter) in xCenters {
            if abs(xCenter - currentXCenter) <= threshold {
                currentColumn.append(line)
                // Update running average
                currentXCenter = currentColumn.map { $0.bbox.centerX }.reduce(0, +) / Double(currentColumn.count)
            } else {
                if !currentColumn.isEmpty {
                    columns.append(currentColumn)
                }
                currentColumn = [line]
                currentXCenter = xCenter
            }
        }

        // Don't forget the last column
        if !currentColumn.isEmpty {
            columns.append(currentColumn)
        }

        // Convert to LayoutColumn
        return columns.map { columnLines in
            let sortedLines = columnLines.sorted { $0.bbox.y < $1.bbox.y }
            let xCenters = sortedLines.map { $0.bbox.centerX }
            let xCenter = xCenters.reduce(0, +) / Double(xCenters.count)

            let minX = sortedLines.map { $0.bbox.x }.min() ?? 0.0
            let maxX = sortedLines.map { $0.bbox.maxX }.max() ?? 1.0

            return LayoutColumn(
                lines: sortedLines,
                xCenter: xCenter,
                xRange: minX...maxX
            )
        }.sorted { $0.xCenter < $1.xCenter }
    }

    // MARK: - Block Partitioning

    /// Partition lines into 9 regional blocks based on position.
    /// - Parameters:
    ///   - lines: OCR lines to partition
    ///   - rows: Pre-computed rows for within-block organization
    /// - Returns: Dictionary mapping regions to blocks
    func partitionIntoBlocks(lines: [OCRLineData], rows: [LayoutRow]) -> [DocumentRegion: LayoutBlock] {
        var regionLines: [DocumentRegion: [OCRLineData]] = [:]

        // Initialize all regions
        for region in DocumentRegion.allCases {
            regionLines[region] = []
        }

        // Assign lines to regions
        for line in lines {
            let region = determineRegion(for: line)
            regionLines[region, default: []].append(line)
        }

        // Create blocks with internal row structure
        var blocks: [DocumentRegion: LayoutBlock] = [:]

        for (region, linesInRegion) in regionLines {
            let rowsInBlock = groupIntoRows(lines: linesInRegion, tolerance: Self.defaultRowTolerance)
            blocks[region] = LayoutBlock(
                region: region,
                lines: linesInRegion,
                rows: rowsInBlock
            )
        }

        return blocks
    }

    private func determineRegion(for line: OCRLineData) -> DocumentRegion {
        let x = line.bbox.centerX
        let y = line.bbox.centerY

        let xIndex: Int
        if x < Self.regionThresholdLow {
            xIndex = 0
        } else if x < Self.regionThresholdHigh {
            xIndex = 1
        } else {
            xIndex = 2
        }

        let yIndex: Int
        if y < Self.regionThresholdLow {
            yIndex = 0
        } else if y < Self.regionThresholdHigh {
            yIndex = 1
        } else {
            yIndex = 2
        }

        // Map to region: row-major order
        let allRegions = DocumentRegion.allCases
        let index = yIndex * 3 + xIndex
        return allRegions[index]
    }
}
