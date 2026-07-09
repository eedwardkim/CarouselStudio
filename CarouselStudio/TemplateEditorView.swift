import CoreModels
import SwiftUI
import TemplateEngine

/// Sheet for creating a new template. Validates inline before saving to the
/// shared template store.
struct TemplateEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var slots: [EditableSlot] = [EditableSlot()]
    @State private var saveError: PersistenceError?
    @State private var showSaveError = false

    struct EditableSlot: Identifiable {
        let id = UUID()
        var criteria: String = ""
        var judgment: SlotJudgment = .objective
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Template name", text: $name)
                    if let issue = validationIssues.first(where: { $0.kind == .emptyName }) {
                        Text(issue.message)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if let issue = validationIssues.first(where: { $0.kind == .noSlots }) {
                    Section {
                        Text(issue.message)
                            .foregroundStyle(.red)
                    }
                }

                if let issue = validationIssues.first(where: { $0.kind == .duplicatePositions }) {
                    Section {
                        Text(issue.message)
                            .foregroundStyle(.red)
                    }
                }

                Section("Slots") {
                    ForEach($slots) { $slot in
                        SlotEditorRow(
                            slot: $slot,
                            position: slots.firstIndex(where: { $0.id == slot.id }).map { $0 + 1 } ?? 1,
                            issues: slotIssues(for: slot.id)
                        )
                    }
                    .onDelete(perform: deleteSlots)

                    Button {
                        slots.append(EditableSlot())
                    } label: {
                        Label("Add Slot", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("New Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(!validationIssues.isEmpty)
                }
            }
            .alert("Save Failed", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError?.localizedDescription ?? "An unknown error occurred.")
            }
        }
    }

    private func deleteSlots(at offsets: IndexSet) {
        slots.remove(atOffsets: offsets)
    }

    private func slotIssues(for slotID: EditableSlot.ID) -> [TemplateValidationIssue] {
        validationIssues.filter { issue in
            switch issue.kind {
            case .emptyCriteria(let id), .criteriaTooLong(let id):
                return id == slotID
            default:
                return false
            }
        }
    }

    private var validationIssues: [TemplateValidationIssue] {
        let template = buildTemplate()
        return DefaultTemplateValidator().validate(template)
    }

    private func buildTemplate() -> Template {
        let coreSlots = slots.enumerated().map { i, s in
            Slot(id: s.id, position: i, criteria: s.criteria, judgment: s.judgment)
        }
        return Template(name: name, format: .carousel, slots: coreSlots)
    }

    private func save() async {
        let template = buildTemplate()
        do {
            try await services.templateStore.save(template)
            dismiss()
        } catch let error as PersistenceError {
            saveError = error
            showSaveError = true
        } catch {
            saveError = .operationFailed(reason: error.localizedDescription)
            showSaveError = true
        }
    }
}

private struct SlotEditorRow: View {
    @Binding var slot: TemplateEditorView.EditableSlot
    let position: Int
    let issues: [TemplateValidationIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Slot \(position)")
                .font(.headline)
            TextField("Describe this photo…", text: $slot.criteria)
            Picker("Type", selection: $slot.judgment) {
                Text("Objective").tag(SlotJudgment.objective)
                Text("Subjective").tag(SlotJudgment.subjective)
            }
            .pickerStyle(.segmented)
            ForEach(issues, id: \.self) { issue in
                Text(issue.message)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}

#Preview {
    TemplateEditorView()
        .environment(AppServices())
}
