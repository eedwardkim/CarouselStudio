import Foundation

// Byte-pair-encoding tokenizer for CLIP-family text towers.
//
// Adapted from Hugging Face's swift-coreml-transformers (MIT, © 2019–2023
// Hugging Face) by way of Apple's MobileCLIPExplore sample app (MIT, © 2024
// Apple Inc.), rewritten for Swift 6: value type, throwing resource loading,
// algorithmic GPT-2 byte table, and silent 77-token truncation to match the
// `EmbeddingProviding` contract.

/// Tokenizes text exactly the way OpenCLIP does for MobileCLIP checkpoints:
/// lowercase → GPT-2 byte encoding → BPE merges → vocabulary lookup, wrapped
/// in start/end markers and zero-padded to `contextLength`.
struct CLIPTokenizer: Sendable {
    /// CLIP's fixed text-tower window (tokens, including start/end markers).
    let contextLength = 77

    // Assembled from pieces: the end marker spelled out verbatim trips up
    // LLM-based tooling (it is a common model stop sequence).
    private static let startMarker = "<" + "|startoftext|" + ">"
    private static let endMarker = "<" + "|endoftext|" + ">"

    private let bpeRanks: [BytePair: Int]
    private let vocabulary: [String: Int]
    private let startTokenID: Int
    private let endTokenID: Int

    enum LoadError: Error, CustomStringConvertible {
        case missingResource(String)
        case malformedResource(String)

        var description: String {
            switch self {
            case .missingResource(let name): "tokenizer resource missing: \(name)"
            case .malformedResource(let name): "tokenizer resource malformed: \(name)"
            }
        }
    }

    /// Loads the vocabulary and merge list bundled with this module.
    init() throws {
        guard let vocabURL = Bundle.module.url(forResource: "clip-vocab", withExtension: "json"),
            let mergesURL = Bundle.module.url(forResource: "clip-merges", withExtension: "txt")
        else {
            throw LoadError.missingResource("clip-vocab.json / clip-merges.txt")
        }
        try self.init(vocabURL: vocabURL, mergesURL: mergesURL)
    }

    init(vocabURL: URL, mergesURL: URL) throws {
        let vocabulary = try JSONDecoder().decode(
            [String: Int].self, from: Data(contentsOf: vocabURL))
        guard let start = vocabulary[Self.startMarker], let end = vocabulary[Self.endMarker] else {
            throw LoadError.malformedResource(vocabURL.lastPathComponent)
        }

        // First line of the merges file is a version header; every other line
        // is "tokenA tokenB", ranked by priority.
        let mergeLines = try String(contentsOf: mergesURL, encoding: .utf8)
            .split(separator: "\n")
        guard mergeLines.count > 1 else {
            throw LoadError.malformedResource(mergesURL.lastPathComponent)
        }
        var bpeRanks = [BytePair: Int](minimumCapacity: mergeLines.count)
        for (index, line) in mergeLines.dropFirst().enumerated() {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            bpeRanks[BytePair(String(parts[0]), String(parts[1]))] = index
        }

        self.vocabulary = vocabulary
        self.bpeRanks = bpeRanks
        self.startTokenID = start
        self.endTokenID = end
    }

    /// Token IDs for one prompt: `[start] + BPE(text) + [end]`, truncated
    /// silently to fit and zero-padded to exactly `contextLength` entries.
    func encodeFull(_ text: String) -> [Int32] {
        let bodyIDs = tokenize(text).compactMap { vocabulary[$0] }.prefix(contextLength - 2)
        var ids = [Int](repeating: 0, count: contextLength)
        ids[0] = startTokenID
        for (offset, id) in bodyIDs.enumerated() {
            ids[offset + 1] = id
        }
        ids[bodyIDs.count + 1] = endTokenID
        return ids.map(Int32.init)
    }

    // MARK: - BPE internals

    /// Splits lowercased text on CLIP's pre-tokenization pattern, byte-encodes
    /// each piece, then applies BPE merges.
    private func tokenize(_ text: String) -> [String] {
        let pattern =
            "'s|'t|'re|'ve|'m|'ll|'d|[\\p{L}]+|[\\p{N}]|[^\\s\\p{L}\\p{N}]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let lowered = text.lowercased()
        let matches = regex.matches(
            in: lowered, range: NSRange(lowered.startIndex..., in: lowered))

        var tokens: [String] = []
        for match in matches {
            guard let range = Range(match.range, in: lowered) else { continue }
            let byteEncoded = lowered[range].utf8.compactMap { GPT2ByteTable.encoder[$0] }
                .joined()
            tokens.append(contentsOf: bpe(byteEncoded).split(separator: " ").map(String.init))
        }
        return tokens
    }

    /// Iteratively applies the highest-priority merge until none applies.
    private func bpe(_ token: String) -> String {
        guard token.count > 1 else { return token + "</w>" }

        var word = token.map(String.init)
        word[word.count - 1] += "</w>"

        while word.count > 1 {
            let pairs = zip(word, word.dropFirst()).map { BytePair($0, $1) }
            guard
                let best = pairs.filter({ bpeRanks[$0] != nil })
                    .min(by: { bpeRanks[$0]! < bpeRanks[$1]! })
            else { break }

            var merged: [String] = []
            var index = 0
            while index < word.count {
                if index < word.count - 1, word[index] == best.a, word[index + 1] == best.b {
                    merged.append(best.a + best.b)
                    index += 2
                } else {
                    merged.append(word[index])
                    index += 1
                }
            }
            word = merged
        }
        return word.joined(separator: " ")
    }
}

private struct BytePair: Hashable {
    let a: String
    let b: String

    init(_ a: String, _ b: String) {
        self.a = a
        self.b = b
    }
}

/// GPT-2's reversible byte↔unicode table, generated algorithmically instead
/// of the usual 256-entry hardcoded map: printable/latin bytes map to
/// themselves; everything else maps to U+0100 + n in first-seen order.
private enum GPT2ByteTable {
    static let encoder: [UInt8: String] = {
        var direct = Array(UInt8(33)...UInt8(126))
        direct += Array(UInt8(161)...UInt8(172))
        direct += Array(UInt8(174)...UInt8(255))
        let directSet = Set(direct)

        var table = [UInt8: String](minimumCapacity: 256)
        for byte in direct {
            table[byte] = String(UnicodeScalar(byte))
        }
        var next = 0
        for byte in UInt8.min...UInt8.max where !directSet.contains(byte) {
            table[byte] = String(UnicodeScalar(0x100 + next)!)
            next += 1
        }
        return table
    }()
}
