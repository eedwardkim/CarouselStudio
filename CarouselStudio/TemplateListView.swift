import CoreModels
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
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationDestination(for: Template.self) { template in
                SlotMatchView(template: template)
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
}

#Preview {
    TemplateListView()
        .environment(AppServices())
}
