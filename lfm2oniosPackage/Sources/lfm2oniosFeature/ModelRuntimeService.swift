import Foundation

@preconcurrency import LeapSDK

public enum ModelRuntimeError: Error, Sendable {
    case invalidURL
    case fileMissing
    case notLoaded
    case cancelled
    case leapSDKUnavailable
    case underlying(String)
}

/// Actor responsible for managing model lifecycle and generating responses.
/// Requires real model files - no simulation fallback.
public actor ModelRuntimeService {
    private var loadedURL: URL?
    private var modelRunner: ModelRunner?
    private var conversation: Conversation?

    public init() {}

    /// Load a model bundle from a local URL. Safe to call repeatedly; it will no-op if already loaded for the same URL.
    /// Throws an error if the model cannot be loaded - no simulation fallback.
    public func loadModel(at url: URL) async throws {
        print("runtime: { event: \"load:entry\", url: \"\(url.absoluteString)\", urlPath: \"\(url.path)\", currentLoaded: \"\(loadedURL?.absoluteString ?? "none")\" }")
        
        if loadedURL == url { 
            print("runtime: { event: \"load:skipped\", reason: \"alreadyLoaded\" }")
            return 
        }
        
        print("runtime: { event: \"load:start\", url: \"\(url.absoluteString)\" }")
        
        let fm = FileManager.default
        var isDir: ObjCBool = false
        
        // Log basic file system info
        print("runtime: { event: \"load:checkingPath\", path: \"\(url.path)\", exists: \(fm.fileExists(atPath: url.path)) }")
        
        // Verify the bundle exists and is a directory
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            print("runtime: { event: \"load:failed\", error: \"bundleMissing\", path: \"\(url.path)\", exists: \(fm.fileExists(atPath: url.path)), isDirectory: \(isDir.boolValue) }")
            throw ModelRuntimeError.fileMissing
        }
        
        print("runtime: { event: \"load:bundleExists\", path: \"\(url.path)\", isDirectory: true }")
        
        // Verify the bundle contains required files
        let bundleContents: [String]
        do {
            bundleContents = try fm.contentsOfDirectory(atPath: url.path)
            print("runtime: { event: \"load:bundleContents\", fileCount: \(bundleContents.count), files: \(bundleContents.prefix(10)) }")
        } catch {
            print("runtime: { event: \"load:failed\", error: \"cannotReadBundle\", path: \"\(url.path)\", underlyingError: \"\(String(describing: error))\" }")
            throw ModelRuntimeError.fileMissing
        }
        
        guard !bundleContents.isEmpty else {
            print("runtime: { event: \"load:failed\", error: \"emptyBundle\", path: \"\(url.path)\" }")
            throw ModelRuntimeError.fileMissing
        }
        
        print("runtime: { event: \"load:bundleVerified\", files: \(bundleContents.count) }")
        
        // Use the original URL directly - LeapSDK should handle spaces in paths
        let loadURL = url
        
        // Log warning if path contains spaces
        if url.path.contains(" ") {
            print("runtime: { event: \"load:warning\", message: \"Path contains spaces which may cause issues\", path: \"\(url.path)\" }")
        }
        
        // Check if LeapSDK is available
        #if canImport(LeapSDK)
        print("runtime: { event: \"load:leapSDKCheck\", available: true }")
        
        // Check LeapSDK version and capabilities
        if LeapIntegration.isSDKAvailable {
            let version = LeapIntegration.sdkVersionString() ?? "unknown"
            print("runtime: { event: \"load:leapSDKVersion\", version: \"\(version)\", isAvailable: true }")
        } else {
            print("runtime: { event: \"load:leapSDKVersion\", version: \"unavailable\", isAvailable: false }")
        }
        #else
        print("runtime: { event: \"load:leapSDKCheck\", available: false }")
        throw ModelRuntimeError.leapSDKUnavailable
        #endif
        
        // Additional file checks before loading - check actual model files
        let modelFiles = ["model.pte", "model.pte.enc", "config.yaml", "tokenizer.json", "tokenizer_config.json", "chat_template.jinja"]
        for file in modelFiles {
            let filePath = url.appendingPathComponent(file)
            let exists = fm.fileExists(atPath: filePath.path)
            if exists {
                if let attrs = try? fm.attributesOfItem(atPath: filePath.path),
                   let size = attrs[.size] as? Int {
                    print("runtime: { event: \"load:modelFile\", file: \"\(file)\", exists: true, size: \(size) }")
                } else {
                    print("runtime: { event: \"load:modelFile\", file: \"\(file)\", exists: true, size: \"unknown\" }")
                }
            } else {
                print("runtime: { event: \"load:modelFile\", file: \"\(file)\", exists: false }")
            }
        }
        
        
        // Try to read config.yaml to understand model requirements
        let configPath = loadURL.appendingPathComponent("config.yaml")
        if let configData = try? Data(contentsOf: configPath),
           let configString = String(data: configData, encoding: .utf8) {
            print("runtime: { event: \"load:config\", content: \"\(configString.replacingOccurrences(of: "\n", with: "\\n"))\" }")
        }
        
        // Validate model file integrity before loading
        let modelPath = loadURL.appendingPathComponent("model.pte")
        guard fm.fileExists(atPath: modelPath.path) else {
            print("runtime: { event: \"load:failed\", error: \"modelFileNotFound\", path: \"\(modelPath.path)\" }")
            throw ModelRuntimeError.fileMissing
        }
        
        // Check model file size and basic validation
        do {
            let attributes = try fm.attributesOfItem(atPath: modelPath.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("runtime: { event: \"load:modelValidation\", size: \(fileSize), path: \"\(modelPath.path)\" }")
            
            // Model file should be at least 1MB for a valid model
            guard fileSize > 1024 * 1024 else {
                print("runtime: { event: \"load:failed\", error: \"modelFileTooSmall\", size: \(fileSize) }")
                throw ModelRuntimeError.underlying("Model file is too small to be valid")
            }
            
            // Read first 32 bytes to validate format
            if let fileHandle = try? FileHandle(forReadingFrom: modelPath) {
                defer { try? fileHandle.close() }
                let headerData = fileHandle.readData(ofLength: 32)
                let headerHex = headerData.map { String(format: "%02hhx", $0) }.joined()
                let headerString = String(data: headerData, encoding: .ascii) ?? ""
                print("runtime: { event: \"load:modelHeader\", headerBytes: \(headerData.count), headerHex: \"\(headerHex)\", ascii: \"\(headerString)\" }")
            }
        } catch {
            print("runtime: { event: \"load:validationFailed\", error: \"\(error)\" }")
            throw ModelRuntimeError.fileMissing
        }
        
        // Load the model with LeapSDK - no fallback
        do {
            print("runtime: { event: \"load:callingLeapLoad\", url: \"\(loadURL.absoluteString)\", path: \"\(loadURL.path)\" }")
            
            let runner = try await Leap.load(url: loadURL)
            
            print("runtime: { event: \"load:leapLoadSucceeded\", runner: \"\(String(describing: runner))\", runnerType: \"\(type(of: runner))\" }")
            
            self.modelRunner = runner
            // Start with empty history; system prompts can be added later
            self.conversation = Conversation(modelRunner: runner, history: [])
            loadedURL = url
            print("runtime: { event: \"load:success\", finalUrl: \"\(url.absoluteString)\" }")
        } catch {
            let errorDescription = String(describing: error)
            let errorType = String(describing: type(of: error))
            print("runtime: { event: \"load:failed\", error: \"\(errorDescription)\", errorType: \"\(errorType)\", localizedDescription: \"\(error.localizedDescription)\" }")
            
            // Try to get more error details
            if let nsError = error as NSError? {
                print("runtime: { event: \"load:failedNSError\", domain: \"\(nsError.domain)\", code: \(nsError.code), userInfo: \"\(nsError.userInfo)\" }")
            }
            
            // Check for specific error types
            if errorDescription.contains("Executorch Error 34") {
                print("runtime: { event: \"load:executorchError34\", hint: \"Model file format may be incompatible or corrupted\" }")
                throw ModelRuntimeError.underlying("Model file format is incompatible. Error 34 typically indicates the model file cannot be parsed by the executorch backend.")
            } else if errorDescription.contains("loadError") {
                throw ModelRuntimeError.underlying("Failed to load model. The model file may be corrupted or in an unsupported format.")
            }
            
            throw ModelRuntimeError.underlying(errorDescription)
        }
    }

    /// Streams a response for the given prompt. Calls `onToken` as partial text chunks arrive.
    /// Requires a real loaded model - no simulation fallback.
    public func streamResponse(
        prompt: String,
        onToken: @Sendable @escaping (String) async -> Void
    ) async throws {
        guard loadedURL != nil else { 
            print("runtime: { event: \"stream:error\", reason: \"noModelLoaded\" }")
            throw ModelRuntimeError.notLoaded 
        }
        
        guard let conversation else {
            print("runtime: { event: \"stream:error\", reason: \"noConversation\" }")
            throw ModelRuntimeError.notLoaded
        }

        print("runtime: { event: \"stream:start\" }")

        var tokenCount = 0
        let userMessage = ChatMessage(role: .user, content: [.text(prompt)])
        
        do {
            for try await response in conversation.generateResponse(message: userMessage) {
                try Task.checkCancellation()
                switch response {
                case .chunk(let text):
                    tokenCount += 1
                    await onToken(text)
                case .reasoningChunk(_):
                    // Ignore in UI for now; could surface in a dev HUD
                    continue
                case .functionCall(_):
                    // Function calling not implemented in MVP; continue
                    continue
                case .complete(let usage, let reason):
                    print("runtime: { event: \"stream:complete\", tokens: \(tokenCount), finishReason: \"\(reason)\", usage: \(String(describing: usage)) }")
                @unknown default:
                    break
                }
            }
        } catch {
            print("runtime: { event: \"stream:error\", error: \"\(String(describing: error))\" }")
            throw ModelRuntimeError.underlying(String(describing: error))
        }
    }
}
