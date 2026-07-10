import CoreGraphics
import CoreModels
import Foundation
import PhotoSources
import Testing

@testable import MatchingEngine

// Runtime behavior of the Phase-1 MatchingEngine implementations. The Core ML
// towers themselves are exercised by the MatchingSmokeCLI harness and the app;
// everything here is deliberately model-free.

// MARK: - CLIPTokenizer

@Suite("CLIPTokenizer")
struct CLIPTokenizerTests {
    private let tokenizer = try! CLIPTokenizer()

    @Test("matches OpenAI CLIP reference tokenization")
    func referenceTokenization() {
        let ids = tokenizer.encodeFull("a photo of a cat")
        #expect(ids.count == 77)
        #expect(Array(ids.prefix(7)) == [49406, 320, 1125, 539, 320, 2368, 49407])
        #expect(ids.dropFirst(7).allSatisfy { $0 == 0 })
    }

    @Test("uppercase and extra whitespace do not change tokens")
    func normalization() {
        #expect(tokenizer.encodeFull("A  Photo of a CAT") == tokenizer.encodeFull("a photo of a cat"))
    }

    @Test("overlong text truncates to the 77-token window instead of trapping")
    func truncation() {
        let ids = tokenizer.encodeFull(
            Array(repeating: "wonderful", count: 200).joined(separator: " "))
        #expect(ids.count == 77)
        #expect(ids[0] == 49406)
        #expect(ids[76] == 49407)
    }

    @Test("empty text embeds as start+end only")
    func emptyText() {
        let ids = tokenizer.encodeFull("")
        #expect(Array(ids.prefix(2)) == [49406, 49407])
        #expect(ids.dropFirst(2).allSatisfy { $0 == 0 })
    }
}

// MARK: - CosineSlotMatcher

@Suite("CosineSlotMatcher")
struct CosineSlotMatcherTests {
    private let matcher = CosineSlotMatcher()
    private let slot = Slot(position: 0, criteria: "test slot")

    private func embedding(_ vector: [Float], version: String = "test-v1") -> Embedding {
        Embedding(vector: vector, modelVersion: version)
    }

    private func id(_ name: String) -> PhotoAssetID {
        PhotoAssetID(source: .photoKit, rawValue: name)
    }

    @Test("ranks by similarity with min–max calibration to 0…1")
    func ranking() async throws {
        let corpus = [
            AssetEmbedding(assetID: id("worst"), embedding: embedding([0, 1])),
            AssetEmbedding(assetID: id("best"), embedding: embedding([1, 0])),
            AssetEmbedding(assetID: id("middle"), embedding: embedding([0.8, 0.6])),
        ]
        let ranked = try await matcher.candidates(
            in: corpus, for: slot, criteriaEmbedding: embedding([1, 0]), limit: 10)

        #expect(ranked.map(\.assetID.rawValue) == ["best", "middle", "worst"])
        #expect(ranked.first?.combinedScore == 1.0)
        #expect(ranked.last?.combinedScore == 0.0)
        #expect(ranked.allSatisfy { $0.clipScore == $0.combinedScore && $0.verdict == nil })
        #expect(ranked.allSatisfy { $0.slotID == slot.id })
    }

    @Test("equal similarities tie-break stably by asset ID")
    func tieBreak() async throws {
        let corpus = ["delta", "alpha", "charlie"].map {
            AssetEmbedding(assetID: id($0), embedding: embedding([1, 0]))
        }
        let ranked = try await matcher.candidates(
            in: corpus, for: slot, criteriaEmbedding: embedding([1, 0]), limit: 3)
        #expect(ranked.map(\.assetID.rawValue) == ["alpha", "charlie", "delta"])
        // Degenerate spread calibrates to a neutral 0.5, not a fake 1.0.
        #expect(ranked.allSatisfy { $0.combinedScore == 0.5 })
    }

    @Test("shortlist honors the limit")
    func limit() async throws {
        let corpus = (0..<10).map {
            AssetEmbedding(assetID: id("asset-\($0)"), embedding: embedding([1, Float($0) / 10]))
        }
        let ranked = try await matcher.candidates(
            in: corpus, for: slot, criteriaEmbedding: embedding([1, 0]), limit: 3)
        #expect(ranked.count == 3)
    }

    @Test("empty corpus yields an empty shortlist")
    func emptyCorpus() async throws {
        let ranked = try await matcher.candidates(
            in: [], for: slot, criteriaEmbedding: embedding([1, 0]), limit: 5)
        #expect(ranked.isEmpty)
    }

    @Test("mixing model versions throws mismatchedEmbeddingSpace")
    func versionMismatch() async throws {
        let corpus = [
            AssetEmbedding(assetID: id("a"), embedding: embedding([1, 0], version: "other-v9"))
        ]
        await #expect(throws: SlotMatchingError.mismatchedEmbeddingSpace(
            expected: "test-v1", found: "other-v9")
        ) {
            try await matcher.candidates(
                in: corpus, for: slot, criteriaEmbedding: embedding([1, 0]), limit: 1)
        }
    }

    @Test("wrong vector length throws dimensionMismatch")
    func dimensionMismatch() async throws {
        let corpus = [
            AssetEmbedding(assetID: id("a"), embedding: embedding([1, 0, 0]))
        ]
        await #expect(throws: SlotMatchingError.dimensionMismatch(expected: 2, found: 3)) {
            try await matcher.candidates(
                in: corpus, for: slot, criteriaEmbedding: embedding([1, 0]), limit: 1)
        }
    }
}

// MARK: - FileEmbeddingStore

@Suite("FileEmbeddingStore")
struct FileEmbeddingStoreTests {
    private func makeStore() -> (FileEmbeddingStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "embeddings-test-\(UUID().uuidString).plist")
        return (FileEmbeddingStore(fileURL: url), url)
    }

    private func id(_ name: String) -> PhotoAssetID {
        PhotoAssetID(source: .photoKit, rawValue: name)
    }

    @Test("miss returns nil, hit round-trips exactly, including across reloads")
    func roundTrip() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try await store.embedding(for: id("x"), modelVersion: "v1") == nil)

        let embedding = Embedding(vector: [0.25, -1, .pi, 42], modelVersion: "v1")
        try await store.store(embedding, for: id("x"))
        #expect(try await store.embedding(for: id("x"), modelVersion: "v1") == embedding)
        // Other model versions for the same asset are still misses.
        #expect(try await store.embedding(for: id("x"), modelVersion: "v2") == nil)

        let reloaded = FileEmbeddingStore(fileURL: url)
        #expect(try await reloaded.embedding(for: id("x"), modelVersion: "v1") == embedding)
    }

    @Test("removeEmbeddings drops every version for the asset and is idempotent")
    func removal() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try await store.store(Embedding(vector: [1], modelVersion: "v1"), for: id("x"))
        try await store.store(Embedding(vector: [2], modelVersion: "v2"), for: id("x"))
        try await store.store(Embedding(vector: [3], modelVersion: "v1"), for: id("y"))

        try await store.removeEmbeddings(for: [id("x"), id("never-existed")])
        #expect(try await store.embedding(for: id("x"), modelVersion: "v1") == nil)
        #expect(try await store.embedding(for: id("x"), modelVersion: "v2") == nil)
        #expect(try await store.embedding(for: id("y"), modelVersion: "v1") != nil)

        try await store.removeEmbeddings(for: [id("x")])  // idempotent
    }

    @Test("compact keeps only the given model version")
    func compaction() async throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }

        try await store.store(Embedding(vector: [1], modelVersion: "old"), for: id("x"))
        try await store.store(Embedding(vector: [2], modelVersion: "new"), for: id("x"))
        try await store.compact(keepingModelVersion: "new")

        #expect(try await store.embedding(for: id("x"), modelVersion: "old") == nil)
        #expect(try await store.embedding(for: id("x"), modelVersion: "new") != nil)
    }

    @Test("corrupt backing file self-heals as an empty cache")
    func corruptFile() async throws {
        let (_, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a plist".utf8).write(to: url)

        let store = FileEmbeddingStore(fileURL: url)
        #expect(try await store.embedding(for: id("x"), modelVersion: "v1") == nil)
        try await store.store(Embedding(vector: [1], modelVersion: "v1"), for: id("x"))
        #expect(try await store.embedding(for: id("x"), modelVersion: "v1") != nil)
    }
}

// MARK: - DefaultTemplateMatcher

/// Serves canned assets; `image(for:)` fails for IDs listed in `broken`
/// (simulating deleted/offloaded photos) and otherwise returns a 1×1 bitmap.
private struct FakePhotoSource: PhotoSource {
    let kind: PhotoSourceKind = .photoKit
    var assetIDs: [String]
    var broken: Set<String> = []

    func requestAccess() async -> PhotoAccessStatus { .full }

    func assets(matching query: AssetQuery) -> AsyncThrowingStream<PhotoAsset, Error> {
        AsyncThrowingStream { continuation in
            for raw in assetIDs {
                continuation.yield(
                    PhotoAsset(
                        id: PhotoAssetID(source: .photoKit, rawValue: raw),
                        pixelWidth: 1, pixelHeight: 1))
            }
            continuation.finish()
        }
    }

    func image(for id: PhotoAssetID, variant: ImageVariant) async throws -> CGImage {
        guard !broken.contains(id.rawValue) else {
            throw PhotoSourceError.resourceUnavailable(id)
        }
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return context.makeImage()!
    }
}

/// A photo library whose contents can change between matching passes,
/// simulating inserts/edits arriving through `PhotoLibraryObserving`.
private final class MutablePhotoLibrary: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String]

    init(_ ids: [String]) { self.ids = ids }

    var assetIDs: [String] {
        get { lock.withLock { ids } }
        set { lock.withLock { ids = newValue } }
    }
}

/// A `PhotoSource` view over a `MutablePhotoLibrary`; each call serves the
/// library's current contents via a throwaway `FakePhotoSource` snapshot.
private struct EvolvingPhotoSource: PhotoSource {
    let kind: PhotoSourceKind = .photoKit
    let library: MutablePhotoLibrary

    private var snapshot: FakePhotoSource { FakePhotoSource(assetIDs: library.assetIDs) }

    func requestAccess() async -> PhotoAccessStatus { .full }

    func assets(matching query: AssetQuery) -> AsyncThrowingStream<PhotoAsset, Error> {
        snapshot.assets(matching: query)
    }

    func image(for id: PhotoAssetID, variant: ImageVariant) async throws -> CGImage {
        try await snapshot.image(for: id, variant: variant)
    }
}

/// Deterministic 2-d "model": every image embeds to [1, 0]; text embeds to
/// [0.6, 0.8]. Counts image-tower calls so tests can prove cache hits.
private actor CountingEmbedder: EmbeddingProviding {
    nonisolated let modelVersion = "fake-v1"
    private(set) var imageCalls = 0

    nonisolated func embedding(for image: CGImage) async throws -> Embedding {
        await increment()
        return Embedding(vector: [1, 0], modelVersion: modelVersion)
    }

    nonisolated func embedding(for text: String) async throws -> Embedding {
        Embedding(vector: [0.6, 0.8], modelVersion: modelVersion)
    }

    private func increment() { imageCalls += 1 }
    func callCount() -> Int { imageCalls }
}

@Suite("DefaultTemplateMatcher")
struct DefaultTemplateMatcherTests {
    private let template = Template(
        name: "T", format: .carousel,
        slots: [
            Slot(position: 0, criteria: "first"),
            Slot(position: 1, criteria: "second"),
        ])

    private func makeMatcher(
        source: FakePhotoSource, embedder: CountingEmbedder
    ) -> (DefaultTemplateMatcher, URL) {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "matcher-test-\(UUID().uuidString).plist")
        let matcher = DefaultTemplateMatcher(
            photoSource: source,
            embedder: embedder,
            embeddingStore: FileEmbeddingStore(fileURL: url),
            slotMatcher: CosineSlotMatcher()
        )
        return (matcher, url)
    }

    @Test("produces a key for every slot and skips per-asset failures")
    func shapeAndSkips() async throws {
        let source = FakePhotoSource(assetIDs: ["ok-1", "ok-2", "gone"], broken: ["gone"])
        let embedder = CountingEmbedder()
        let (matcher, url) = makeMatcher(source: source, embedder: embedder)
        defer { try? FileManager.default.removeItem(at: url) }

        let match = try await matcher.match(template, options: .default)

        #expect(match.templateID == template.id)
        #expect(match.candidatesBySlot.count == 2)
        for slot in template.slots {
            let candidates = try #require(match.candidatesBySlot[slot.id])
            #expect(candidates.count == 2)  // "gone" skipped, never thrown
            #expect(!candidates.contains { $0.assetID.rawValue == "gone" })
        }
    }

    @Test("second pass serves embeddings from the cache")
    func cacheReuse() async throws {
        let source = FakePhotoSource(assetIDs: ["a", "b"])
        let embedder = CountingEmbedder()
        let (matcher, url) = makeMatcher(source: source, embedder: embedder)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await matcher.match(template, options: .default)
        #expect(await embedder.callCount() == 2)
        _ = try await matcher.match(template, options: .default)
        #expect(await embedder.callCount() == 2)  // no re-embedding
    }

    @Test("update purges modified assets so they re-embed")
    func updateReEmbeds() async throws {
        let source = FakePhotoSource(assetIDs: ["a", "b"])
        let embedder = CountingEmbedder()
        let (matcher, url) = makeMatcher(source: source, embedder: embedder)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try await matcher.match(template, options: .default)
        let change = PhotoLibraryChange(
            modified: [PhotoAssetID(source: .photoKit, rawValue: "a")])
        let updated = try await matcher.update(
            first, applying: change, for: template, options: .default)

        #expect(await embedder.callCount() == 3)  // a re-embedded, b cached
        #expect(updated.candidatesBySlot.count == 2)
    }

    @Test("update re-embeds only inserted and modified assets, never the whole corpus")
    func updateEmbedsOnlyTheChange() async throws {
        let library = MutablePhotoLibrary(["a", "b", "c"])
        let source = EvolvingPhotoSource(library: library)
        let embedder = CountingEmbedder()
        let url = FileManager.default.temporaryDirectory
            .appending(path: "matcher-test-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let matcher = DefaultTemplateMatcher(
            photoSource: source,
            embedder: embedder,
            embeddingStore: FileEmbeddingStore(fileURL: url),
            slotMatcher: CosineSlotMatcher()
        )

        let first = try await matcher.match(template, options: .default)
        #expect(await embedder.callCount() == 3)

        // The library gains one photo and one existing photo is edited.
        library.assetIDs = ["a", "b", "c", "d"]
        let change = PhotoLibraryChange(
            inserted: [PhotoAssetID(source: .photoKit, rawValue: "d")],
            modified: [PhotoAssetID(source: .photoKit, rawValue: "b")])
        let updated = try await matcher.update(
            first, applying: change, for: template, options: .default)

        // Exactly the changed assets hit the image tower: "d" (new) and "b"
        // (stale embedding). "a" and "c" must be served from the cache — the
        // quest loop's per-change budget depends on this.
        #expect(await embedder.callCount() == 5)
        for slot in template.slots {
            let candidates = try #require(updated.candidatesBySlot[slot.id])
            #expect(candidates.count == 4)
        }
    }

    @Test("slotless template matches to an empty result, not an error")
    func slotlessTemplate() async throws {
        let source = FakePhotoSource(assetIDs: ["a"])
        let embedder = CountingEmbedder()
        let (matcher, url) = makeMatcher(source: source, embedder: embedder)
        defer { try? FileManager.default.removeItem(at: url) }

        let empty = Template(name: "Empty", format: .story)
        let match = try await matcher.match(empty, options: .default)
        #expect(match.candidatesBySlot.isEmpty)
    }
}
