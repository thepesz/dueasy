import Foundation

// MARK: - Navigation Value Types

/// Lightweight value type for NavigationLink to document detail.
///
/// ## Why This Exists
/// Using `FinanceDocument` (a SwiftData `@Model` class) directly with `NavigationLink(value:)`
/// can cause navigation failures due to several issues:
///
/// 1. **Reference Type Issues**: SwiftData `@Model` classes are reference types with complex
///    identity semantics tied to the model context.
///
/// 2. **Orphan Instances**: Creating a temporary `FinanceDocument` instance just for navigation
///    creates an object not in the model context, which can cause unpredictable behavior.
///
/// 3. **Hashable Complexity**: `@Model`'s synthesized Hashable conformance may compare internal
///    state that differs between fresh instances and persisted ones.
///
/// ## Solution
/// This simple value type holds just the document ID needed for navigation.
/// The destination view (`DocumentDetailView`) fetches the actual document from SwiftData.
///
/// ## Usage
/// ```swift
/// // In source view
/// NavigationLink(value: DocumentNavigationValue(documentId: document.id)) {
///     DocumentRow(document: document)
/// }
///
/// // In parent view
/// .navigationDestination(for: DocumentNavigationValue.self) { navValue in
///     DocumentDetailView(documentId: navValue.documentId)
/// }
/// ```
public struct DocumentNavigationValue: Hashable, Sendable {
    /// The UUID of the document to navigate to
    public let documentId: UUID

    /// Creates a navigation value for the specified document ID.
    /// - Parameter documentId: The UUID of the document to navigate to.
    public init(documentId: UUID) {
        self.documentId = documentId
    }
}
