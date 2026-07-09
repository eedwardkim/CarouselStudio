import CoreModels
import Foundation
import MatchingEngine
import PhotoSources

/// Drives one template's matching pass and holds its results for the UI.
@MainActor
@Observable
final class MatchSession {
    enum Phase: Equatable {
        case idle
        case requestingAccess
        case accessDenied
        case loadingModel
        case scanning(MatchProgress)
        case ranked
        case failed(String)
    }

    let template: Template
    private(set) var phase: Phase = .idle
    private(set) var match: TemplateMatch?

    private let services: AppServices
    private var task: Task<Void, Never>?

    init(template: Template, services: AppServices) {
        self.template = template
        self.services = services
    }

    /// Ranked candidates for one slot, best first (empty until `ranked`).
    func candidates(for slot: Slot) -> [SlotCandidate] {
        match?.candidatesBySlot[slot.id] ?? []
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    func retry() {
        task?.cancel()
        task = Task { await run() }
    }

    private func run() async {
        match = nil
        phase = .requestingAccess
        let access = await services.photoSource.requestAccess()
        guard access == .full || access == .limited else {
            phase = .accessDenied
            return
        }

        phase = .loadingModel
        do {
            let matcher = try await services.templateMatcher { [weak self] progress in
                self?.phase = .scanning(progress)
            }
            phase = .scanning(MatchProgress(completed: 0, total: 0))
            let result = try await matcher.match(template, options: .default)
            match = result
            phase = .ranked
            logSummary(of: result)
        } catch is CancellationError {
            // Superseded by a retry or dismissal; keep quiet.
        } catch {
            phase = .failed("\(error)")
            AppServices.logger.error("match failed: \(String(describing: error))")
        }
    }

    /// Console evidence that ranking actually happened — greppable in the
    /// simulator log during development.
    private func logSummary(of result: TemplateMatch) {
        for slot in template.slots.sorted(by: { $0.position < $1.position }) {
            let ranked = result.candidatesBySlot[slot.id] ?? []
            let top = ranked.prefix(3)
                .map { candidate in
                    let suffix = candidate.assetID.rawValue.prefix(8)
                    return String(format: "%@… %.3f", String(suffix), candidate.combinedScore)
                }
                .joined(separator: ", ")
            AppServices.logger.notice(
                "slot \(slot.position, privacy: .public) '\(slot.criteria, privacy: .public)': \(ranked.count, privacy: .public) candidates [\(top, privacy: .public)]"
            )
        }
    }
}
