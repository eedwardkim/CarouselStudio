import CoreModels
import Foundation
import TemplateEngine
import Testing

@Suite struct TemplateValidationTests {
    private let validator = DefaultTemplateValidator()

    private func makeSlot(position: Int, criteria: String = "a nice photo") -> Slot {
        Slot(position: position, criteria: criteria)
    }

    private func makeTemplate(
        name: String = "My Template",
        slots: [Slot] = [Slot(position: 0, criteria: "a nice photo")]
    ) -> Template {
        Template(name: name, format: .carousel, slots: slots)
    }

    @Test func fullyValidTemplateReturnsNoIssues() {
        #expect(validator.validate(makeTemplate()).isEmpty)
    }

    @Test func emptyNameInIsolation() {
        let issues = validator.validate(makeTemplate(name: "   "))
        #expect(
            issues == [
                TemplateValidationIssue(
                    kind: .emptyName,
                    message: "Template name must not be empty."
                )
            ]
        )
    }

    @Test func noSlotsInIsolation() {
        let issues = validator.validate(makeTemplate(slots: []))
        #expect(
            issues == [
                TemplateValidationIssue(
                    kind: .noSlots,
                    message: "A template must have at least one slot."
                )
            ]
        )
    }

    @Test func emptyCriteriaInIsolation() {
        let slot = makeSlot(position: 0, criteria: "   ")
        let issues = validator.validate(makeTemplate(slots: [slot]))
        #expect(
            issues == [
                TemplateValidationIssue(
                    kind: .emptyCriteria(slot.id),
                    message: "Slot 1 criteria must not be empty."
                )
            ]
        )
    }

    @Test func criteriaTooLongInIsolation() {
        let criteria = Array(repeating: "word", count: 78).joined(separator: " ")
        let slot = makeSlot(position: 0, criteria: criteria)
        let issues = validator.validate(makeTemplate(slots: [slot]))
        #expect(
            issues == [
                TemplateValidationIssue(
                    kind: .criteriaTooLong(slot.id),
                    message: "Slot 1 criteria is too long (exceeds 77 tokens)."
                )
            ]
        )
    }

    @Test func duplicatePositionsInIsolation() {
        let slot1 = makeSlot(position: 0, criteria: "first")
        let slot2 = makeSlot(position: 0, criteria: "second")
        let issues = validator.validate(makeTemplate(slots: [slot1, slot2]))
        #expect(
            issues == [
                TemplateValidationIssue(
                    kind: .duplicatePositions,
                    message: "Slot positions must be unique."
                )
            ]
        )
    }

    // NOTE: `.noSlots` cannot coexist with `.duplicatePositions` or per-slot
    // issues (those require at least one slot), so the combined case below
    // exercises all four coexisting issue kinds. The `.noSlots` kind is covered
    // by its own isolation test above.
    @Test func allApplicableIssueKindsCombined() {
        let emptyCriteriaSlot = makeSlot(position: 0, criteria: "   ")
        let tooLongCriteria = Array(repeating: "word", count: 78).joined(separator: " ")
        let tooLongSlot = makeSlot(position: 0, criteria: tooLongCriteria)
        let issues = validator.validate(makeTemplate(name: "", slots: [emptyCriteriaSlot, tooLongSlot]))

        #expect(
            issues == [
                TemplateValidationIssue(
                    kind: .emptyName,
                    message: "Template name must not be empty."
                ),
                TemplateValidationIssue(
                    kind: .duplicatePositions,
                    message: "Slot positions must be unique."
                ),
                TemplateValidationIssue(
                    kind: .emptyCriteria(emptyCriteriaSlot.id),
                    message: "Slot 1 criteria must not be empty."
                ),
                TemplateValidationIssue(
                    kind: .criteriaTooLong(tooLongSlot.id),
                    message: "Slot 1 criteria is too long (exceeds 77 tokens)."
                ),
            ]
        )
    }
}
