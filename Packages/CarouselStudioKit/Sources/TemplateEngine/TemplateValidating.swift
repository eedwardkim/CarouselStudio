import CoreModels

/// Structural checks run before a template is saved or matched. Pure and
/// deterministic; never touches storage.
public protocol TemplateValidating: Sendable {
    /// Empty result means the template is valid.
    ///
    /// All issues are found in one pass — nothing short-circuits — so the UI
    /// can annotate every field at once. Issues come back in a stable order:
    /// template-level first, then per-slot in position order.
    func validate(_ template: Template) -> [TemplateValidationIssue]
}

public struct TemplateValidationIssue: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case emptyName
        case noSlots
        case emptyCriteria(Slot.ID)
        /// CLIP text encoders truncate at 77 tokens; overly long criteria
        /// silently lose matching signal, so we surface it to the user.
        case criteriaTooLong(Slot.ID)
        case duplicatePositions
    }

    public var kind: Kind
    /// Human-readable, ready for display.
    public var message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}
