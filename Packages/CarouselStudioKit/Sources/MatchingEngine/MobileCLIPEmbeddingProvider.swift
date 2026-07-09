import CoreGraphics
import CoreML
import CoreModels
import Foundation

/// `EmbeddingProviding` backed by MobileCLIP's two Core ML towers.
///
/// Phase 1 ships the S0 checkpoint (smallest/fastest; 512-d output like S2).
/// Towers are loaded once at init; predictions run through Core ML, which is
/// documented thread-safe for concurrent `prediction` calls on one `MLModel`.
///
/// `@unchecked Sendable`: every stored property is immutable, and `MLModel`
/// (non-Sendable by annotation) is safe for concurrent prediction per Core ML
/// documentation.
public final class MobileCLIPEmbeddingProvider: EmbeddingProviding, @unchecked Sendable {
    public let modelVersion: String

    private let imageTower: MLModel
    private let textTower: MLModel
    private let tokenizer: CLIPTokenizer
    private let imageInputName: String
    private let imageOutputName: String
    private let textInputName: String
    private let textOutputName: String
    private let pixelsWide: Int
    private let pixelsHigh: Int
    private let imageConstraint: MLImageConstraint

    /// Loads the two towers from `.mlmodelc` (compiled, as Xcode embeds them)
    /// or `.mlpackage`/`.mlmodel` URLs (compiled here on the fly — dev/CLI
    /// convenience; apps should ship precompiled models).
    ///
    /// - Parameters:
    ///   - imageModelURL: The image tower.
    ///   - textModelURL: The text tower.
    ///   - modelVersion: Stamped into every embedding and cache key.
    ///   - configuration: Compute-unit preferences; simulator callers should
    ///     pass `.cpuOnly` (no ANE, and simulator GPU paths are flaky).
    /// - Throws: `EmbeddingError.modelUnavailable` when loading/compiling
    ///   fails or a tower's I/O doesn't look like a CLIP encoder.
    public init(
        imageModelURL: URL,
        textModelURL: URL,
        modelVersion: String = "mobileclip-s0",
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) async throws {
        do {
            self.imageTower = try await Self.loadModel(at: imageModelURL, configuration: configuration)
            self.textTower = try await Self.loadModel(at: textModelURL, configuration: configuration)
        } catch {
            throw EmbeddingError.modelUnavailable(reason: "\(error)")
        }
        do {
            self.tokenizer = try CLIPTokenizer()
        } catch {
            throw EmbeddingError.modelUnavailable(reason: "\(error)")
        }

        // Discover I/O names from the model descriptions rather than
        // hardcoding them, so a re-exported checkpoint keeps working as long
        // as its shape is (image in → vector out, tokens in → vector out).
        guard
            let imageInput = imageTower.modelDescription.inputDescriptionsByName
                .first(where: { $0.value.type == .image }),
            let constraint = imageInput.value.imageConstraint,
            let imageOutput = imageTower.modelDescription.outputDescriptionsByName
                .first(where: { $0.value.type == .multiArray })
        else {
            throw EmbeddingError.modelUnavailable(
                reason: "image tower at \(imageModelURL.lastPathComponent) is not image→vector")
        }
        guard
            let textInput = textTower.modelDescription.inputDescriptionsByName
                .first(where: { $0.value.type == .multiArray }),
            let textOutput = textTower.modelDescription.outputDescriptionsByName
                .first(where: { $0.value.type == .multiArray })
        else {
            throw EmbeddingError.modelUnavailable(
                reason: "text tower at \(textModelURL.lastPathComponent) is not tokens→vector")
        }

        self.imageInputName = imageInput.key
        self.imageOutputName = imageOutput.key
        self.textInputName = textInput.key
        self.textOutputName = textOutput.key
        self.imageConstraint = constraint
        self.pixelsWide = constraint.pixelsWide
        self.pixelsHigh = constraint.pixelsHigh
        self.modelVersion = modelVersion
    }

    private static func loadModel(
        at url: URL, configuration: MLModelConfiguration
    ) async throws -> MLModel {
        switch url.pathExtension {
        case "mlmodelc":
            return try MLModel(contentsOf: url, configuration: configuration)
        default:
            let compiled = try await MLModel.compileModel(at: url)
            return try MLModel(contentsOf: compiled, configuration: configuration)
        }
    }

    // MARK: - EmbeddingProviding

    public func embedding(for image: CGImage) async throws -> Embedding {
        guard image.width > 0, image.height > 0 else {
            throw EmbeddingError.imageEncodingFailed(reason: "zero-sized bitmap")
        }
        guard let prepared = image.centerCroppedAndScaled(width: pixelsWide, height: pixelsHigh)
        else {
            throw EmbeddingError.imageEncodingFailed(reason: "unsupported pixel format")
        }

        let vector: [Float]
        do {
            let value = try MLFeatureValue(cgImage: prepared, constraint: imageConstraint)
            let inputs = try MLDictionaryFeatureProvider(dictionary: [imageInputName: value])
            let outputs = try await imageTower.prediction(from: inputs)
            vector = try Self.vector(from: outputs, named: imageOutputName)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EmbeddingError.imageEncodingFailed(reason: "\(error)")
        }
        guard let normalized = vector.l2Normalized() else {
            throw EmbeddingError.imageEncodingFailed(reason: "degenerate zero-norm embedding")
        }
        return Embedding(vector: normalized, modelVersion: modelVersion)
    }

    public func embedding(for text: String) async throws -> Embedding {
        let vector: [Float]
        do {
            let tokens = tokenizer.encodeFull(text)
            let array = try MLMultiArray(shape: [1, NSNumber(value: tokens.count)], dataType: .int32)
            for (index, token) in tokens.enumerated() {
                array[index] = NSNumber(value: token)
            }
            let inputs = try MLDictionaryFeatureProvider(dictionary: [textInputName: array])
            let outputs = try await textTower.prediction(from: inputs)
            vector = try Self.vector(from: outputs, named: textOutputName)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw EmbeddingError.textEncodingFailed(reason: "\(error)")
        }
        guard let normalized = vector.l2Normalized() else {
            throw EmbeddingError.textEncodingFailed(reason: "degenerate zero-norm embedding")
        }
        return Embedding(vector: normalized, modelVersion: modelVersion)
    }

    // MARK: - Output handling

    private static func vector(from outputs: MLFeatureProvider, named name: String) throws -> [Float] {
        guard let array = outputs.featureValue(for: name)?.multiArrayValue else {
            throw EmbeddingError.modelUnavailable(reason: "tower produced no output \(name)")
        }
        // `converting:` handles Float16/Float32/Double outputs uniformly.
        return MLShapedArray<Float>(converting: array).scalars
    }
}

extension [Float] {
    /// The unit-norm copy of this vector, or `nil` when the norm is ~0.
    fileprivate func l2Normalized() -> [Float]? {
        let norm = map { $0 * $0 }.reduce(0, +).squareRoot()
        guard norm > .ulpOfOne else { return nil }
        return map { $0 / norm }
    }
}

extension CGImage {
    /// Center-crops to square then scales to exactly `width`×`height` in sRGB,
    /// mirroring OpenCLIP's resize+center-crop preprocessing closely enough
    /// for retrieval. Returns `nil` for bitmaps CoreGraphics can't redraw.
    fileprivate func centerCroppedAndScaled(width: Int, height: Int) -> CGImage? {
        let side = Swift.min(self.width, self.height)
        let cropRect = CGRect(
            x: (self.width - side) / 2,
            y: (self.height - side) / 2,
            width: side,
            height: side
        )
        guard let squared = (self.width == self.height) ? self : cropping(to: cropRect),
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(squared, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
