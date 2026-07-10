import CoreModels
import MatchingEngine
import PhotoSources
import SwiftUI

/// Matches the whole template once, then lets the user pick a slot and swipe
/// through its ranked candidates (best first).
struct SlotMatchView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var session: MatchSession?
    @State private var selectedSlotIndex = 0
    @State private var pageIndex = 0

    let template: Template

    private var orderedSlots: [Slot] {
        template.slots.sorted { $0.position < $1.position }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            Group {
                if let session {
                    content(for: session)
                } else {
                    Color.clear
                }
            }

            // Custom nav bar overlay
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.12), in: Circle())
                }

                Spacer()

                Text(template.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                // Placeholder for symmetry
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .toolbar(.hidden, for: .navigationBar)
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
            centeredStatus {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Text("Requesting photo access…")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.6))
                }
            }
        case .accessDenied:
            centeredStatus {
                VStack(spacing: 20) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(white: 0.4))
                    Text("No Photo Access")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("CarouselStudio matches photos on this device.\nAllow access in Settings.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.55))
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.18), in: Capsule())
                }
            }
        case .loadingModel:
            centeredStatus {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Text("Loading MobileCLIP…")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.6))
                }
            }
        case .scanning(let progress):
            centeredStatus {
                VStack(spacing: 20) {
                    if progress.total > 0 {
                        VStack(spacing: 12) {
                            ProgressView(value: Double(progress.completed), total: Double(progress.total))
                                .tint(Color(red: 0.89, green: 0.16, blue: 0.49))
                                .padding(.horizontal, 40)
                            Text("Scanning \(progress.completed) / \(progress.total)")
                                .font(.system(size: 14).monospacedDigit())
                                .foregroundStyle(Color(white: 0.55))
                        }
                    } else {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.4)
                        Text("Scanning photos…")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(white: 0.6))
                    }
                }
            }
        case .failed(let message):
            centeredStatus {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(white: 0.4))
                    Text("Matching Failed")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Retry") { session.retry() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(white: 0.18), in: Capsule())
                }
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
            // Spacing for nav bar
            Spacer().frame(height: 60)

            // Slot chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { index, s in
                        Button {
                            selectedSlotIndex = index
                        } label: {
                            Text("Slot \(s.position + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selectedSlotIndex == index ? .black : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    selectedSlotIndex == index
                                        ? Color.white
                                        : Color(white: 0.18),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.18), value: selectedSlotIndex)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 10)

            // Criteria description
            Text(slot.criteria)
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .lineLimit(2)

            // Candidate pager
            if candidates.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(white: 0.3))
                    Text("No matches found")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(white: 0.5))
                    Text("Nothing in your library matched this slot.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.35))
                }
                Spacer()
            } else {
                TabView(selection: $pageIndex) {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { rank, candidate in
                        CandidateCard(candidate: candidate, rank: rank)
                            .tag(rank)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Custom dot indicator
                HStack(spacing: 5) {
                    ForEach(0..<min(candidates.count, 8), id: \.self) { i in
                        Circle()
                            .fill(i == pageIndex ? Color.white : Color(white: 0.35))
                            .frame(width: i == pageIndex ? 6 : 4, height: i == pageIndex ? 6 : 4)
                            .animation(.easeInOut(duration: 0.15), value: pageIndex)
                    }
                    if candidates.count > 8 {
                        Text("+\(candidates.count - 8)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.35))
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .onChange(of: selectedSlotIndex) {
            pageIndex = 0
        }
    }

    @ViewBuilder
    private func centeredStatus<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// One swipeable candidate: full-bleed photo with rank and score overlaid.
private struct CandidateCard: View {
    @Environment(AppServices.self) private var services
    @State private var image: CGImage?
    @State private var loadFailed = false

    let candidate: SlotCandidate
    let rank: Int

    private var scorePercent: Int {
        Int((candidate.combinedScore * 100).rounded())
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Photo
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.1))
                .overlay {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else if loadFailed {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 28))
                            Text("Couldn't load")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(Color(white: 0.35))
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }

            // Bottom gradient + info overlay
            VStack(alignment: .leading, spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Match")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(white: 0.55))
                        Text("\(scorePercent)%")
                            .font(.system(size: 28, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    // Rank badge
                    Text("#\(rank + 1)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white, in: Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
                .background(Color.black.opacity(0.72))
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
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
