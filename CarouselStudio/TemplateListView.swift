import CoreModels
import SwiftUI
import TemplateEngine
import QuestEngine

/// Phase-1 entry screen: browse the template gallery, now backed by the
/// SwiftData template store, and create new templates from the toolbar.
struct TemplateListView: View {
    @Environment(AppServices.self) private var services
    @State private var path = NavigationPath()
    @State private var didAttemptAutoOpen = false
    @State private var templates: [Template] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var showingEditor = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    ProgressView()
                } else if let error = loadError {
                    ContentUnavailableView(
                        "Failed to load templates",
                        systemImage: "exclamationmark.triangle"
                    )
                } else {
                    List(templates) { template in
                        NavigationLink(value: template) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(.headline)
                                Text(
                                    "\(template.format == .carousel ? "Carousel" : "Story") · \(template.slots.count) slots"
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                if let report = services.latestReports[template.id] {
                                    Text(coverageSummary(for: report))
                                        .font(.caption)
                                        .foregroundStyle(coverageColor(for: report))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .refreshable {
                        try? await services.questCoordinator?.refresh(templateID: nil)
                        await loadTemplates()
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationDestination(for: Template.self) { template in
                SlotMatchView(template: template)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") {
                        showingEditor = true
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                TemplateEditorView()
                    .environment(services)
            }
            .task {
                await services.seedStartersIfNeeded()
                await loadTemplates()

                // Dev hook for CLI-driven smoke runs: `SIMCTL_CHILD_AUTO_OPEN_TEMPLATE=1`
                // Only attempt once so returning to the list does not re-push
                // the first template on top of the user's navigation stack.
                guard !didAttemptAutoOpen else { return }
                didAttemptAutoOpen = true
                if ProcessInfo.processInfo.environment["AUTO_OPEN_TEMPLATE"] == "1",
                    let first = templates.first,
                    path.isEmpty
                {
                    path.append(first)
                }
            }
            .task {
                await observeChanges()
            }
        }
    }

    private func loadTemplates() async {
        isLoading = true
        do {
            templates = try await services.templateStore.allTemplates()
            loadError = nil
        } catch {
            loadError = error
        }
        isLoading = false
    }

    private func observeChanges() async {
        for await _ in services.templateStore.changes() {
            await loadTemplates()
        }
    }

    private func coverageSummary(for report: QuestReport) -> String {
        let noneCount = report.coverage.filter { $0.level == .none }.count
        let scarceCount = report.coverage.filter { $0.level == .scarce }.count
        if noneCount > 0 {
            return "⚠ \(noneCount) slot\(noneCount == 1 ? "" : "s") need photos"
        } else if scarceCount > 0 {
            return "→ \(scarceCount) slot\(scarceCount == 1 ? "" : "s") could use more photos"
        } else {
            return "✓ All slots covered"
        }
    }

    private func coverageColor(for report: QuestReport) -> Color {
        let noneCount = report.coverage.filter { $0.level == .none }.count
        let scarceCount = report.coverage.filter { $0.level == .scarce }.count
        if noneCount > 0 { return .orange }
        if scarceCount > 0 { return .secondary }
        return .green
    }
}

#Preview {
    TemplateListView()
        .environment(AppServices())
}
