import CoreModels
import QuestEngine
import SwiftUI
import TemplateEngine

/// Phase-1 entry screen: browse the template gallery, now backed by the
/// SwiftData template store, and create new templates from the toolbar.
struct TemplateListView: View {
    @Environment(AppServices.self) private var services
    @State private var path = NavigationPath()
    @State private var didAttemptAutoOpen = false
    @State private var templates: [Template] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var templateToDelete: Template? = nil
    @State private var deleteError: String? = nil
    @State private var showingEditor = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if loadError != nil {
                    ContentUnavailableView(
                        "Failed to load templates",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.white)
                } else {
                    List {
                        ForEach(templates) { template in
                            NavigationLink(value: template) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.name)
                                        .font(.headline)
                                        .foregroundStyle(.white)
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
                            .listRowBackground(Color.black)
                        }
                        .onDelete { offsets in
                            if let index = offsets.first {
                                templateToDelete = templates[index]
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        try? await services.questCoordinator?.refresh(templateID: nil)
                        await loadTemplates()
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .background(Color.black)
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
            .alert("Delete Template?", isPresented: Binding(
                get: { templateToDelete != nil },
                set: { if !$0 { templateToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    Task { await confirmDelete() }
                }
                Button("Cancel", role: .cancel) {
                    templateToDelete = nil
                }
            } message: {
                if let t = templateToDelete {
                    Text("\"\(t.name)\" will be permanently deleted.")
                }
            }
            .alert("Delete Failed", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                if let msg = deleteError { Text(msg) }
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

    private func confirmDelete() async {
        guard let template = templateToDelete else { return }
        templateToDelete = nil
        do {
            try await services.templateStore.deleteTemplate(withID: template.id)
            await loadTemplates()
        } catch {
            deleteError = error.localizedDescription
        }
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
