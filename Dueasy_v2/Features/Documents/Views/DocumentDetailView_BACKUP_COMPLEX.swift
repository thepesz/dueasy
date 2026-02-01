// ============================================================================
// BACKUP OF COMPLEX DOCUMENT DETAIL VIEW
// ============================================================================
// This file is intentionally commented out. It contains the original complex
// implementation that was causing scroll issues. Keep for reference only.
// ============================================================================

/*
import SwiftUI

/// Document detail view showing all fields and actions.
///
/// ARCHITECTURE NOTE: This view uses UUID-based navigation to avoid SwiftData object
/// invalidation issues. The ViewModel fetches a fresh document reference on each load.
///
/// LAYOUT FIX: Uses a unique viewIdentity that changes on each navigation to force
/// a complete view hierarchy rebuild. This prevents stale safe area insets from
/// corrupting ScrollView layout after sheet dismissals.
struct DocumentDetailView_Complex: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let documentId: UUID

    @State private var viewModel: DocumentDetailViewModel?
    @State private var showingEditSheet = false
    @State private var appeared = false

    /// Unique identity for the content view to force complete rebuild on each navigation.
    /// This prevents stale safe area insets from corrupting ScrollView layout.
    @State private var viewIdentity = UUID()

    var body: some View {
        let _ = print("📋 DocumentDetailView body evaluated - documentId: \(documentId), viewIdentity: \(viewIdentity)")
        Group {
            if let viewModel = viewModel, let doc = viewModel.document {
                let _ = print("📋 Showing content view with loaded document")
                contentView(viewModel: viewModel, document: doc)
                    // CRITICAL: Force complete view rebuild with unique identity
                    // This ensures fresh safe area calculations after sheet dismissals
                    .id(viewIdentity)
            } else {
                let _ = print("📋 Showing loading view - viewModel: \(viewModel != nil), document: \(viewModel?.document != nil)")
                LoadingView(L10n.Common.loading.localized)
                    .gradientBackground(style: .list)
            }
        }
        .navigationTitle(viewModel?.document?.title.isEmpty ?? true ? L10n.Detail.title.localized : (viewModel?.document?.title ?? L10n.Detail.title.localized))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Generate new identity on each appear to force fresh layout
            // This handles the case where the view is reused after sheet dismissal
            print("📋 DocumentDetailView onAppear - generating new viewIdentity")
            viewIdentity = UUID()
        }
        .task(id: documentId) {
            // Task is re-run when documentId changes, ensuring fresh data
            print("📋 DocumentDetailView .task started for documentId: \(documentId)")

            // Reset animation state for fresh appearance
            appeared = false

            // Generate new identity to force complete view rebuild
            viewIdentity = UUID()

            setupViewModel()
            print("📋 Calling loadDocument...")
            await viewModel?.loadDocument()
            print("📋 loadDocument completed - document loaded: \(viewModel?.document != nil)")

            // CRITICAL: Use a small delay before triggering appearance animation.
            // This ensures the ScrollView has completed its initial layout pass
            // before we start the opacity animation. Without this delay, the
            // animation can interfere with safe area calculations.
            try? await Task.sleep(for: .milliseconds(50))

            // Trigger appearance animation after document loads
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.3)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
        .onChange(of: viewModel?.shouldDismiss ?? false) { _, shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func contentView(viewModel: DocumentDetailViewModel, document: FinanceDocument) -> some View {
        // LAYOUT FIX: Wrap ScrollView in a container that explicitly handles safe areas.
        // This prevents safe area corruption after sheet dismissals in NavigationStack.
        //
        // The issue: After a sheet is presented and dismissed from a NavigationStack,
        // ScrollView's safe area calculations can become corrupted, causing content
        // to appear "stuck under the header".
        //
        // Solution: Use a simple ZStack with explicit background and let the ScrollView
        // use .safeAreaPadding() for consistent content positioning.
        ZStack {
            // Background that fills the entire area
            GradientBackgroundFixed()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Header with status
                    // CRITICAL FIX: Use ONLY opacity animations, NO offset animations.
                    // Offset animations inside ScrollView interfere with content positioning
                    // and cause the "scroll returns under header" bug after SwiftData inserts.
                    headerSection(document: document)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3), value: appeared)

                    // Amount section
                    amountSection(document: document)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.05), value: appeared)

                    // Details section
                    detailsSection(document: document)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.1), value: appeared)

                    // Calendar section
                    calendarSection(document: document)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.15), value: appeared)

                    // Actions section
                    actionsSection(viewModel: viewModel, document: document)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.2), value: appeared)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label(L10n.Common.edit.localized, systemImage: "pencil")
                    }

                    if document.status == .scheduled {
                        Button {
                            Task {
                                await viewModel.markAsPaid()
                            }
                        } label: {
                            Label(L10n.Detail.markAsPaid.localized, systemImage: "checkmark.circle")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteDocument()
                        }
                    } label: {
                        Label(L10n.Common.delete.localized, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let doc = viewModel.document {
                DocumentEditView(document: doc)
                    .environment(environment)
            }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.error {
                ErrorBanner(error: error, onDismiss: { viewModel.clearError() })
                    .padding()
            }
        }
        .loadingOverlay(isLoading: viewModel.isLoading, message: L10n.Detail.deleting.localized)
    }

    // ... sections omitted for brevity ...
}
*/
