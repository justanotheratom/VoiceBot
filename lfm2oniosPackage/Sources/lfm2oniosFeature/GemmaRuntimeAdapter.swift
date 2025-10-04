import Foundation
import MLXLMCommon

// MARK: - Gemma runtime tuning knobs

/// Upper bound for tokens Gemma generates per response regardless of context budget.
private let gemmaMaxResponseTokens: Int = 256

/// Total number of prompt echoes tolerated before we assume repetition.
private let gemmaPromptEchoThreshold: Int = 3

/// Minimum identical trailing lines needed before we stop the stream for repetition.
private let gemmaDuplicateLineThreshold: Int = 4

/// Maximum number of sentences allowed in a single Gemma response.
private let gemmaMaxSentencesPerResponse: Int = 3

/// Hard ceiling on character count for any Gemma response.
private let gemmaMaxResponseCharacters: Int = 1_200

/// Temperature applied to MLX sampling for Gemma to keep answers focused.
private let gemmaSamplingTemperature: Float = 0.35

/// Top-p nucleus sampling cutoff for Gemma generation.
private let gemmaSamplingTopP: Float = 0.85

/// Penalty factor to discourage Gemma from repeating recent tokens.
private let gemmaRepetitionPenalty: Float = 1.15

/// Sliding window size (in tokens) used by the repetition penalty processor.
private let gemmaRepetitionContextSize: Int = 128

/// Stop sequences emitted by Gemma chat template that should terminate generation.
private let gemmaStopSequences: [String] = ["<end_of_turn>", "<start_of_turn>"]

final actor GemmaRuntimeAdapter: ModelRuntimeAdapting {
    private var inferenceService: GemmaInferenceService?
    private var modelDirectory: URL?

    func loadModel(at url: URL, entry: ModelCatalogEntry) async throws {
        guard entry.runtime == .mlx else {
            throw ModelRuntimeError.underlying("Unsupported runtime kind for Gemma adapter")
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ModelRuntimeError.fileMissing
        }

        guard let metadata = entry.gemmaMetadata else {
            throw ModelRuntimeError.underlying("Missing Gemma metadata for entry \(entry.slug)")
        }

        let primaryPath = url.appendingPathComponent(metadata.primaryFilePath)
        guard fm.fileExists(atPath: primaryPath.path) else {
            throw ModelRuntimeError.underlying("Gemma primary file missing at \(primaryPath.path)")
        }

        inferenceService = GemmaInferenceService(modelDirectory: url)
        modelDirectory = url
    }

    func unload() async {
        inferenceService = nil
        modelDirectory = nil
    }

    func resetConversation() async {
        // Stateless; nothing to reset.
    }

    func streamResponse(
        prompt: String,
        conversation: [ChatMessageModel],
        tokenLimit: Int,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws {
        guard let inferenceService else {
            throw ModelRuntimeError.notLoaded
        }

        // Ensure the latest user message matches the prompt; if not, append it.
        var conversationForModel = conversation
        if conversationForModel.last?.role != .user || conversationForModel.last?.content != prompt {
            conversationForModel.append(ChatMessageModel(role: .user, content: prompt))
        }

        let rolesSummary = conversationForModel.map { $0.role.rawValue }.joined(separator: ",")
        AppLogger.runtime().log(event: "gemma:conversation", data: [
            "roles": rolesSummary,
            "count": conversationForModel.count
        ])

        let generationParameters = makeGenerationParameters(limit: tokenLimit)
        var repetitionGuard = RepetitionGuard(prompt: prompt)
        var stopScanner = StopSequenceScanner(stopSequences: gemmaStopSequences)

        let stream = try await inferenceService.tokenStream(
            conversation: conversationForModel,
            maxTokens: tokenLimit,
            parameters: generationParameters
        )

        for try await token in stream {
            try Task.checkCancellation()

            let (emittable, didHitStop) = stopScanner.consume(token)

            if !emittable.isEmpty {
                let decision = repetitionGuard.register(emittable)
                await onToken(emittable)

                if case let .stop(reason, repeats, sample) = decision {
                    let sanitizedSample = sanitizeForLog(sample)
                    AppLogger.runtime().log(event: "gemma:repeatGuard", data: [
                        "reason": reason,
                        "repeats": repeats,
                        "sample": sanitizedSample
                    ], level: .error)
                    break
                }
            }

            if didHitStop {
                break
            }
        }
    }

    func preload() async throws {
        let maybeService = inferenceService as GemmaInferenceService?
        guard let service = maybeService else {
            throw ModelRuntimeError.notLoaded
        }

        try await service.preloadModel()
    }

    private func makeGenerationParameters(limit: Int) -> GenerateParameters {
        let cappedLimit = min(max(limit, 1), gemmaMaxResponseTokens)
        return GenerateParameters(
            maxTokens: cappedLimit,
            temperature: gemmaSamplingTemperature,
            topP: gemmaSamplingTopP,
            repetitionPenalty: gemmaRepetitionPenalty,
            repetitionContextSize: gemmaRepetitionContextSize
        )
    }

    private func sanitizeForLog(_ value: String) -> String {
        let withoutNewlines = value.replacingOccurrences(of: "\n", with: " ")
        return withoutNewlines.replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct RepetitionGuard {
    enum Decision {
        case `continue`
        case stop(reason: String, repeats: Int, sample: String)
    }

    private let normalizedPrompt: String
    private var generated: String = ""
    private var normalizedGenerated: String = ""

    init(prompt: String) {
        self.normalizedPrompt = RepetitionGuard.normalize(prompt)
    }

    mutating func register(_ token: String) -> Decision {
        generated.append(token)
        normalizedGenerated = RepetitionGuard.normalize(generated)

        if !normalizedPrompt.isEmpty {
            let occurrences = normalizedGenerated.components(separatedBy: normalizedPrompt).count - 1
            if occurrences >= gemmaPromptEchoThreshold {
                return .stop(
                    reason: "promptRepeat",
                    repeats: occurrences,
                    sample: recentSample()
                )
            }
        }

        let lines = generated
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let last = lines.last {
            let duplicateCount = lines.reversed().prefix(while: { $0 == last }).count
            if last.count >= 8, duplicateCount >= gemmaDuplicateLineThreshold {
                return .stop(
                    reason: "lineRepeat",
                    repeats: duplicateCount,
                    sample: last
                )
            }
        }

        let sentenceCount = generated
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        if sentenceCount >= gemmaMaxSentencesPerResponse, generated.count > 80 {
            return .stop(
                reason: "sentenceLimit",
                repeats: sentenceCount,
                sample: recentSample()
            )
        }

        if generated.count >= gemmaMaxResponseCharacters {
            return .stop(
                reason: "lengthLimit",
                repeats: generated.count,
                sample: recentSample()
            )
        }

        return .continue
    }

    private func recentSample() -> String {
        let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 160 {
            return trimmed
        } else {
            return String(trimmed.suffix(160))
        }
    }

    private static func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let scalars = text.lowercased().unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars))
        return cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

private struct StopSequenceScanner {
    private let stopSequences: [String]
    private let maxStopLength: Int
    private var tail: String = ""

    init(stopSequences: [String]) {
        self.stopSequences = stopSequences
        self.maxStopLength = stopSequences.map { $0.count }.max() ?? 0
    }

    mutating func consume(_ chunk: String) -> (String, Bool) {
        guard !stopSequences.isEmpty else { return (chunk, false) }

        let combined = tail + chunk

        var earliestRange: Range<String.Index>? = nil
        for stop in stopSequences {
            if let range = combined.range(of: stop) {
                if earliestRange == nil || range.lowerBound < earliestRange!.lowerBound {
                    earliestRange = range
                }
            }
        }

        if let matchRange = earliestRange {
            let emission = String(combined[..<matchRange.lowerBound])
            tail = ""
            return (emission, true)
        }

        if maxStopLength <= 1 {
            tail = ""
            return (combined, false)
        }

        let keepLength = min(maxStopLength - 1, combined.count)
        if keepLength <= 0 {
            tail = ""
            return (combined, false)
        }

        let cutIndex = combined.index(combined.endIndex, offsetBy: -keepLength)
        let emission = String(combined[..<cutIndex])
        tail = String(combined[cutIndex...])
        return (emission, false)
    }
}
