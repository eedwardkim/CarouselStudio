import CoreModels
import Foundation

/// `EmbeddingStore` persisted as one flat binary-plist file of raw Float32
/// vectors — a few hundred KB per thousand photos, loaded fully into memory
/// on first use. Deliberately not SwiftData (see DATA_MODEL.md): dense
/// vectors want a flat layout, and this file is a disposable cache, not a
/// document — corruption self-heals by starting empty and re-embedding.
///
/// Write-through: every `store` rewrites the file atomically. Fine for
/// Phase-1 corpus sizes; batching lands with the Quest Engine if profiling
/// asks for it.
public actor FileEmbeddingStore: EmbeddingStore {
    /// Separates key components; never appears in `PhotoSourceKind` raw
    /// values, PhotoKit local identifiers, or model version strings.
    private static let separator = "\u{1F}"

    private let fileURL: URL
    private var entries: [String: Data]?

    /// - Parameter fileURL: Backing file; parent directory is created on
    ///   first write. Pass a temp URL in tests.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The conventional production location:
    /// `Application Support/EmbeddingCache/embeddings-v1.plist`.
    public static func defaultFileURL() throws -> URL {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return base.appending(path: "EmbeddingCache/embeddings-v1.plist")
        } catch {
            throw PersistenceError.storageUnavailable(reason: "\(error)")
        }
    }

    // MARK: - EmbeddingStore

    public func embedding(for id: PhotoAssetID, modelVersion: String) async throws -> Embedding? {
        guard let data = try loadedEntries()[Self.key(id, modelVersion)] else { return nil }
        guard data.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            // Torn entry: treat as a miss and drop it so it gets re-embedded.
            entries?[Self.key(id, modelVersion)] = nil
            return nil
        }
        let vector = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return Embedding(vector: vector, modelVersion: modelVersion)
    }

    public func store(_ embedding: Embedding, for id: PhotoAssetID) async throws {
        var entries = try loadedEntries()
        entries[Self.key(id, embedding.modelVersion)] = embedding.vector.withUnsafeBufferPointer {
            Data(buffer: $0)
        }
        self.entries = entries
        try persist()
    }

    public func removeEmbeddings(for ids: [PhotoAssetID]) async throws {
        var entries = try loadedEntries()
        let prefixes = ids.map { Self.assetPrefix($0) }
        let before = entries.count
        entries = entries.filter { key, _ in !prefixes.contains { key.hasPrefix($0) } }
        guard entries.count != before else { return }
        self.entries = entries
        try persist()
    }

    public func compact(keepingModelVersion modelVersion: String) async throws {
        var entries = try loadedEntries()
        let suffix = Self.separator + modelVersion
        let before = entries.count
        entries = entries.filter { key, _ in key.hasSuffix(suffix) }
        guard entries.count != before else { return }
        self.entries = entries
        try persist()
    }

    // MARK: - Backing file

    private static func key(_ id: PhotoAssetID, _ modelVersion: String) -> String {
        assetPrefix(id) + modelVersion
    }

    private static func assetPrefix(_ id: PhotoAssetID) -> String {
        id.source.rawValue + separator + id.rawValue + separator
    }

    private func loadedEntries() throws -> [String: Data] {
        if let entries { return entries }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = [:]
            return [:]
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try PropertyListDecoder().decode([String: Data].self, from: data)
            entries = decoded
            return decoded
        } catch {
            // A cache that can't be read is a cache that starts over.
            entries = [:]
            return [:]
        }
    }

    private func persist() throws {
        guard let entries else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            throw PersistenceError.operationFailed(reason: "\(error)")
        }
    }
}
