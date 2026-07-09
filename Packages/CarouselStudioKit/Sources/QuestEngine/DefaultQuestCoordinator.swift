import CoreModels
import Foundation
import MatchingEngine
import os
import PhotoSources
import TemplateEngine

/// Long-running quest coordinator that observes photo-library and template
/// changes, keeps per-template matches fresh via incremental updates, and
/// publishes coverage reports to subscribers.
public actor DefaultQuestCoordinator: QuestCoordinating {
    private let observer: any PhotoLibraryObserving
    private let templateStore: any TemplateStore
    private let matcher: any TemplateMatching
    private let policy: any CoveragePolicy
    private let reportStore: any QuestReportStore
    private let logger = Logger(subsystem: "com.edwardkim.CarouselStudio", category: "quest")

    /// Latest known match per template, seeded lazily on the first observation
    /// or manual refresh.
    private var latestMatches: [Template.ID: TemplateMatch] = [:]

    /// Continuations for the reports() stream.
    private var reportContinuations: [UUID: AsyncStream<QuestReport>.Continuation] = [:]

    /// Active observation tasks.
    private var libraryTask: Task<Void, Never>?
    private var templateTask: Task<Void, Never>?
    private var active = false

    public init(
        observer: any PhotoLibraryObserving,
        templateStore: any TemplateStore,
        matcher: any TemplateMatching,
        policy: any CoveragePolicy,
        reportStore: any QuestReportStore
    ) {
        self.observer = observer
        self.templateStore = templateStore
        self.matcher = matcher
        self.policy = policy
        self.reportStore = reportStore
    }

    // MARK: - QuestCoordinating

    public func activate() async {
        guard !active else { return }
        active = true

        libraryTask = Task { [weak self] in
            guard let self else { return }
            await self.runLibraryLoop()
        }

        templateTask = Task { [weak self] in
            guard let self else { return }
            await self.runTemplateLoop()
        }
    }

    public func deactivate() async {
        active = false

        libraryTask?.cancel()
        templateTask?.cancel()

        libraryTask = nil
        templateTask = nil
    }

    public func refresh(templateID: Template.ID?) async throws {
        if let id = templateID {
            guard let template = try await templateStore.template(withID: id) else { return }
            let result = try await matcher.match(template, options: .default)
            latestMatches[id] = result
            let report = buildReport(for: template, from: result, trigger: .manual)
            try await reportStore.save(report)
            publishReport(report)
            logReportSaved(for: template, report: report)
        } else {
            let templates = try await templateStore.allTemplates()
            for template in templates {
                let result = try await matcher.match(template, options: .default)
                latestMatches[template.id] = result
                let report = buildReport(for: template, from: result, trigger: .manual)
                try await reportStore.save(report)
                publishReport(report)
                logReportSaved(for: template, report: report)
            }
        }
    }

    nonisolated public func reports() -> AsyncStream<QuestReport> {
        let streamID = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: streamID) }
            }

            Task {
                await self.addContinuation(continuation, id: streamID)

                // Replay the latest known report for every template, then
                // continue with live updates.
                do {
                    let templates = try await self.templateStore.allTemplates()
                    for template in templates {
                        if let report = try? await self.reportStore.latestReport(for: template.id) {
                            continuation.yield(report)
                        }
                    }
                } catch {
                    // Replay failure is non-fatal; live updates still work.
                }
            }
        }
    }

    // MARK: - Private helpers

    private func addContinuation(_ continuation: AsyncStream<QuestReport>.Continuation, id: UUID) {
        reportContinuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        reportContinuations.removeValue(forKey: id)
    }

    private func runLibraryLoop() async {
        for await change in observer.changes() {
            guard !Task.isCancelled else { break }
            do {
                let templates = try await templateStore.allTemplates()
                for template in templates {
                    guard !Task.isCancelled else { return }
                    do {
                        let existing = latestMatches[template.id]
                        let updated: TemplateMatch
                        if let existing {
                            updated = try await matcher.update(existing, applying: change, for: template, options: .default)
                        } else {
                            updated = try await matcher.match(template, options: .default)
                        }
                        latestMatches[template.id] = updated
                        let report = buildReport(for: template, from: updated, trigger: .libraryChange)
                        try await reportStore.save(report)
                        publishReport(report)
                        logReportSaved(for: template, report: report)
                    } catch {
                        logger.error("quest library loop error for template \(template.id): \(error)")
                    }
                }
            } catch {
                logger.error("quest library loop failed to fetch templates: \(error)")
            }
        }
    }

    private func runTemplateLoop() async {
        for await change in templateStore.changes() {
            guard !Task.isCancelled else { break }
            switch change {
            case .saved(let id):
                do {
                    guard let template = try await templateStore.template(withID: id) else { continue }
                    let result = try await matcher.match(template, options: .default)
                    latestMatches[id] = result
                    let report = buildReport(for: template, from: result, trigger: .templateChange)
                    try await reportStore.save(report)
                    publishReport(report)
                    logReportSaved(for: template, report: report)
                } catch {
                    logger.error("quest template loop error for saved \(id): \(error)")
                }
            case .deleted(let id):
                latestMatches.removeValue(forKey: id)
                do {
                    try await reportStore.deleteReports(for: id)
                } catch {
                    logger.error("quest failed to delete reports for \(id): \(error)")
                }
            }
        }
    }

    private func buildReport(for template: Template, from match: TemplateMatch, trigger: QuestTrigger) -> QuestReport {
        let coverage = template.slots.sorted { $0.position < $1.position }.map { slot in
            policy.coverage(for: slot, candidates: match.candidatesBySlot[slot.id] ?? [])
        }
        return QuestReport(id: UUID(), templateID: template.id, generatedAt: Date(), trigger: trigger, coverage: coverage)
    }

    private func publishReport(_ report: QuestReport) {
        for continuation in reportContinuations.values {
            continuation.yield(report)
        }
    }

    private func logReportSaved(for template: Template, report: QuestReport) {
        let coverageSummary = report.coverage.map { "\($0.slotID):\($0.level.rawValue)" }.joined(separator: ",")
        logger.notice("quest report saved: templateID=\(template.id) coverage=\(coverageSummary, privacy: .public)")
    }
}
