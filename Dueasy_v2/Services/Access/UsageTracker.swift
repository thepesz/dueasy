import Foundation

// MARK: - Deprecated: UsageTracker

/// This file is no longer used in the simplified local-first architecture.
///
/// ## Migration Notes
///
/// Client-side usage tracking has been removed. The backend (Firebase Functions)
/// is now the single source of truth for cloud extraction quota.
///
/// See: `AccessManager.updateQuotaFromBackend(_:)` for the replacement.
/// See: `CloudQuota` in `AppAccessState.swift` for the new quota model.
///
/// This file is retained temporarily for reference during migration.
/// It can be safely deleted from the project.

// Intentionally empty - all usage tracking is now backend-authoritative.
