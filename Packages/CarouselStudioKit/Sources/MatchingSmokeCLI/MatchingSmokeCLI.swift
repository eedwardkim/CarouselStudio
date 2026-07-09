import CoreGraphics
import CoreModels
import Foundation
import MatchingEngine
import TemplateEngine

// Command-line smoke test for the Phase-1 matching pipeline. Run with:
//
//     swift run MatchingSmokeCLI /path/to/mobileclip_s0_image.mlpackage \
//                                /path/to/mobileclip_s0_text.mlpackage
//
// Verifies, with the real Core ML towers: (1) text↔text semantic sanity,
// (2) image↔text retrieval on synthetic images, (3) the full
// corpus→SlotMatching ranking path, (4) FileEmbeddingStore round-trips.
// Exits non-zero on the first failed check.

@main
struct MatchingSmokeCLI {
    static func main() async {
        do {
            try await run()
            print("\nALL CHECKS PASSED")
        } catch {
            print("\nSMOKE TEST FAILED: \(error)")
            exit(1)
        }
    }

    struct CheckFailure: Error, CustomStringConvertible {
        let description: String
    }

    static func check(_ condition: Bool, _ label: String) throws {
        print(condition ? "  PASS  \(label)" : "  FAIL  \(label)")
        if !condition { throw CheckFailure(description: label) }
    }

    static func run() async throws {
        let arguments = CommandLine.arguments
        let imageURL = URL(
            filePath: arguments.count > 1
                ? arguments[1] : "/tmp/mobileclip/mobileclip_s0_image.mlpackage")
        let textURL = URL(
            filePath: arguments.count > 2
                ? arguments[2] : "/tmp/mobileclip/mobileclip_s0_text.mlpackage")

        print("Loading MobileCLIP-S0 towers (compiles on first run)…")
        let provider = try await MobileCLIPEmbeddingProvider(
            imageModelURL: imageURL, textModelURL: textURL)
        print("Loaded. modelVersion=\(provider.modelVersion)")

        // 1. Text tower + tokenizer sanity.
        print("\n[1] Text↔text semantics")
        let dog = try await provider.embedding(for: "a photo of a dog")
        let puppy = try await provider.embedding(for: "a photo of a cute puppy")
        let invoice = try await provider.embedding(for: "a scanned invoice document with a table")
        try check(dog.vector.count == 512, "embedding dimension is 512 (got \(dog.vector.count))")
        let norm = dog.vector.map { Double($0) * Double($0) }.reduce(0, +).squareRoot()
        try check(abs(norm - 1) < 1e-3, "embedding is unit-norm (|v|=\(norm))")
        let dogPuppy = dot(dog, puppy)
        let dogInvoice = dot(dog, invoice)
        print("  cos(dog, puppy)   = \(dogPuppy)")
        print("  cos(dog, invoice) = \(dogInvoice)")
        try check(dogPuppy > dogInvoice + 0.05, "related prompts beat unrelated prompts")

        let repeated = try await provider.embedding(for: "a photo of a dog")
        try check(repeated.vector == dog.vector, "text tower is deterministic")

        // 2. Image tower: synthetic color fields vs color prompts.
        print("\n[2] Image↔text retrieval on synthetic images")
        let redImage = try solidImage(r: 0.85, g: 0.10, b: 0.10)
        let blueImage = try solidImage(r: 0.10, g: 0.15, b: 0.85)
        let greenImage = try solidImage(r: 0.10, g: 0.75, b: 0.15)
        let redEmb = try await provider.embedding(for: redImage)
        let blueEmb = try await provider.embedding(for: blueImage)
        let greenEmb = try await provider.embedding(for: greenImage)

        let redText = try await provider.embedding(for: "a plain red image")
        let blueText = try await provider.embedding(for: "a plain blue image")
        let greenText = try await provider.embedding(for: "a plain green image")

        for (label, image, expected) in [
            ("red", redEmb, 0), ("blue", blueEmb, 1), ("green", greenEmb, 2),
        ] {
            let scores = [dot(image, redText), dot(image, blueText), dot(image, greenText)]
            let winner = scores.firstIndex(of: scores.max()!)!
            print("  \(label) image → [red: \(scores[0]), blue: \(scores[1]), green: \(scores[2])]")
            try check(winner == expected, "\(label) image retrieves the \(label) prompt")
        }

        // 3. Full ranking path through SlotMatching.
        print("\n[3] CosineSlotMatcher ranking")
        let corpus = [
            AssetEmbedding(assetID: fakeID("red-photo"), embedding: redEmb),
            AssetEmbedding(assetID: fakeID("blue-photo"), embedding: blueEmb),
            AssetEmbedding(assetID: fakeID("green-photo"), embedding: greenEmb),
        ]
        let template = BuiltInStarterTemplates().starterTemplates()[0]
        let slot = Slot(position: 0, criteria: "a plain blue image")
        let matcher = CosineSlotMatcher()
        let ranked = try await matcher.candidates(
            in: corpus, for: slot, criteriaEmbedding: blueText, limit: 3)
        for (rank, candidate) in ranked.enumerated() {
            print(
                "  #\(rank + 1) \(candidate.assetID.rawValue) score=\(candidate.combinedScore)")
        }
        try check(ranked.count == 3, "matcher returns full shortlist")
        try check(ranked[0].assetID.rawValue == "blue-photo", "blue photo ranks first for blue slot")
        try check(ranked[0].combinedScore == 1.0, "top candidate calibrates to 1.0")
        try check(ranked[2].combinedScore == 0.0, "bottom candidate calibrates to 0.0")
        try check(
            ranked == (try await matcher.candidates(
                in: corpus, for: slot, criteriaEmbedding: blueText, limit: 3)),
            "ranking is deterministic")

        // 4. Embedding store round-trip.
        print("\n[4] FileEmbeddingStore round-trip")
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "smoke-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let store = FileEmbeddingStore(fileURL: storeURL)
        try await store.store(redEmb, for: fakeID("red-photo"))
        let missBeforeStore = try await store.embedding(
            for: fakeID("blue-photo"), modelVersion: provider.modelVersion)
        try check(missBeforeStore == nil, "unknown asset is a cache miss")
        let reloaded = FileEmbeddingStore(fileURL: storeURL)
        let hit = try await reloaded.embedding(
            for: fakeID("red-photo"), modelVersion: provider.modelVersion)
        try check(hit?.vector == redEmb.vector, "stored embedding survives reload byte-for-byte")
        try await reloaded.removeEmbeddings(for: [fakeID("red-photo")])
        let missAfterRemove = try await reloaded.embedding(
            for: fakeID("red-photo"), modelVersion: provider.modelVersion)
        try check(missAfterRemove == nil, "removeEmbeddings drops the entry")

        _ = template
    }

    static func dot(_ a: Embedding, _ b: Embedding) -> Double {
        zip(a.vector, b.vector).reduce(0) { $0 + Double($1.0) * Double($1.1) }
    }

    static func fakeID(_ name: String) -> PhotoAssetID {
        PhotoAssetID(source: .photoKit, rawValue: name)
    }

    /// A 640×480 solid-color bitmap — deliberately non-square to exercise the
    /// provider's center-crop path.
    static func solidImage(r: CGFloat, g: CGFloat, b: CGFloat) throws -> CGImage {
        guard
            let context = CGContext(
                data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else {
            throw CheckFailure(description: "could not create CGContext")
        }
        context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        guard let image = context.makeImage() else {
            throw CheckFailure(description: "could not render solid image")
        }
        return image
    }
}
