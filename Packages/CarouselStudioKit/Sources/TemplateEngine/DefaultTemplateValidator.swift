import CoreModels

/// The default structural validator for `Template` values.
///
/// Performs every check in a single pass and returns every issue found, ordered
/// as template-level issues first, then per-slot issues in position order.
public struct DefaultTemplateValidator: TemplateValidating {
    public init() {}

    public func validate(_ template: Template) -> [TemplateValidationIssue] {
        var issues: [TemplateValidationIssue] = []

        // 1. Empty name.
        if template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                TemplateValidationIssue(
                    kind: .emptyName,
                    message: "Template name must not be empty."
                )
            )
        }

        // 2. No slots.
        if template.slots.isEmpty {
            issues.append(
                TemplateValidationIssue(
                    kind: .noSlots,
                    message: "A template must have at least one slot."
                )
            )
        }

        // Work in position order for the remaining checks.
        let sortedSlots = template.slots.sorted { $0.position < $1.position }

        // 3. Duplicate positions (one issue total).
        var seenPositions = Set<Int>()
        var hasDuplicatePositions = false
        for slot in sortedSlots {
            if !seenPositions.insert(slot.position).inserted {
                hasDuplicatePositions = true
            }
        }
        if hasDuplicatePositions {
            issues.append(
                TemplateValidationIssue(
                    kind: .duplicatePositions,
                    message: "Slot positions must be unique."
                )
            )
        }

        // 4. Per-slot criteria checks, in position order; emptyCriteria first.
        for slot in sortedSlots {
            let trimmedCriteria = slot.criteria.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCriteria.isEmpty {
                issues.append(
                    TemplateValidationIssue(
                        kind: .emptyCriteria(slot.id),
                        message: "Slot \(slot.position + 1) criteria must not be empty."
                    )
                )
            }

            let tokenCount = slot.criteria.split(separator: " ").count
            if tokenCount > 77 {
                issues.append(
                    TemplateValidationIssue(
                        kind: .criteriaTooLong(slot.id),
                        message: "Slot \(slot.position + 1) criteria is too long (exceeds 77 tokens)."
                    )
                )
            }
        }

        return issues
    }
}
