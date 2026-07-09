import CoreModels

/// Persistent image-embedding cache keyed by (asset, model version). This is
/// what makes rescans cheap: only new or modified photos get re-embedded, so
/// the Quest Engine's incremental updates touch a handful of images, not 50k.
///
/// A cache miss is `nil`, never an error — thrown errors are storage faults
/// (`PersistenceError`). Expect a few hundred KB of dense float vectors per
/// thousand photos; the production store is a flat binary/SQLite layout, not
/// SwiftData.
public protocol EmbeddingStore: Sendable {
    /// The cached embedding, or `nil` on a miss (including when only other
    /// model versions are cached for this asset).
    /// - Throws: `PersistenceError`.
    func embedding(for id: PhotoAssetID, modelVersion: String) async throws -> Embedding?

    /// Insert-or-replace under the key `(id, embedding.modelVersion)`.
    /// - Throws: `PersistenceError`.
    func store(_ embedding: Embedding, for id: PhotoAssetID) async throws

    /// Drops every cached version for these assets. Called when assets are
    /// deleted, or modified in place (stale embeddings). Idempotent — unknown
    /// IDs are ignored.
    /// - Throws: `PersistenceError`.
    func removeEmbeddings(for ids: [PhotoAssetID]) async throws

    /// Drops every embedding not produced by `modelVersion` — run after a
    /// model upgrade to reclaim space. Idempotent.
    /// - Throws: `PersistenceError`.
    func compact(keepingModelVersion modelVersion: String) async throws
}
