import CoreModels
import SwiftUI
import TemplateEngine

/// Phase-1 entry screen: pick a starter template to match against your
/// library. Template CRUD arrives with the SwiftData-backed store; for now
/// the compiled-in starter catalog is the whole gallery.
struct TemplateListView: View {
    @Environment(AppServices.self) private var services
    @State private var path = NavigationPath()
    @State private var didAttemptAutoOpen = false

    var body: some View {
        NavigationStack(path: $path) {
            List(services.starterTemplates.starterTemplates()) { template in
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
            .navigationTitle("Templates")
            .navigationDestination(for: Template.self) { template in
                SlotMatchView(template: template)
            }
            .task {
                // Dev hook for CLI-driven smoke runs: `SIMCTL_CHILD_AUTO_OPEN_TEMPLATE=1
                // simctl launch …` jumps straight into the first template.
                // Only attempt once so returning to the list does not re-push
                // the first template on top of the user's navigation stack.
                guard !didAttemptAutoOpen else { return }
                didAttemptAutoOpen = true
                if ProcessInfo.processInfo.environment["AUTO_OPEN_TEMPLATE"] == "1",
                    let first = services.starterTemplates.starterTemplates().first,
                    path.isEmpty
                {
                    path.append(first)
                }
            }
        }
    }
}

#Preview {
    TemplateListView()
        .environment(AppServices())
}
