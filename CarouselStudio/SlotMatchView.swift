import CoreModels
import MatchingEngine
import PhotoSources
import SwiftUI

/// Matches the whole template once, then lets the user pick a slot and swipe
/// through its ranked candidates (best first).
struct SlotMatchView: View {
    @Environment(AppServices.self) private var services
    @State private var session: MatchSession?
    @State private var selectedSlotIndex = 0
    @State private var pageIndex = 0

    let template: Template

    private var orderedSlots: [Slot] {
        template.slots.sorted { $0.position < $1.position }
    }

    var body: some View {
        Group {
            if let session {
                content(for: session)
            } else {
                Color.clear
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if session == nil {
                let newSession = MatchSession(template: template, services: services)
                session = newSession
                newSession.start()
            }
        }
    }

    @ViewBuilder
    private func content(for session: MatchSession) -> some View {
        switch session.phase {
        case .idle, .requestingAccess:
            ProgressView("Requesting photo access…")
        case .accessDenied:
            ContentUnavailableView {
                Label("No Photo Access", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text("CarouselStudio matches photos on this device. Allow access in Settings.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        case .loadingModel:
            ProgressView("Loading MobileCLIP…")
        case .scanning(let progress):
            VStack(spacing: 12) {
                if progress.total > 0 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .padding(.horizontal, 40)
                    Text("Scanning photos \(progress.completed)/\(progress.total)")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Scanning photos…")
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Matching Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { session.retry() }
            }
        case .ranked:
            rankedContent(for: session)
        }
    }

    @ViewBuilder
    private func rankedContent(for session: MatchSession) -> some View {
        let slots = orderedSlots
        let slot = slots[min(selectedSlotIndex, slots.count - 1)]
        let candidates = session.candidates(for: slot)

        VStack(spacing: 0) {
            Picker("Slot", selection: $selectedSlotIndex) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    Text("Slot \(slot.position + 1)").tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Text(slot.criteria)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 8)

            if candidates.isEmpty {
                ContentUnavailableView(
                    "No Candidates",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Nothing in your library matches this slot yet.")
                )
            } else {
                TabView(selection: $pageIndex) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { rank, candidate in
                        CandidateCard(candidate: candidate, rank: rank)
                            .tag(rank)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .onChange(of: selectedSlotIndex) {
            pageIndex = 0
        }
    }
}

/// One swipeable candidate: photo, rank badge, and calibrated score.
private struct CandidateCard: View {
    @Environment(AppServices.self) private var services
    @State private var image: CGImage?
    @State private var loadFailed = false

    let candidate: SlotCandidate
    let rank: Int

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if loadFailed {
                    Label("Couldn't load photo", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text("#\(rank + 1)")
                    .font(.title3.bold())
                Spacer()
                Text("match \(Int((candidate.combinedScore * 100).rounded()))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding()
        .task(id: candidate.assetID) {
            image = nil
            loadFailed = false
            do {
                image = try await services.photoSource.image(
                    for: candidate.assetID, variant: .display)
            } catch {
                loadFailed = true
            }
        }
    }
}
