import Testing
import Foundation
@testable import lfm2oniosFeature

@Test("ModelCatalog has curated entries")
func catalogEntries() {
    #expect(!ModelCatalog.all.isEmpty)
    #expect(ModelCatalog.entry(forSlug: "lfm2-350m")?.displayName.contains("LFM2") == true)
}

@Test("SelectedModel encodes and decodes via JSON")
func selectedModelCodable() throws {
    let original = SelectedModel(slug: "slug", displayName: "Name", provider: "Leap", quantizationSlug: nil, localURL: nil)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SelectedModel.self, from: data)
    #expect(decoded == original)
}

actor _Accumulator {
    private(set) var text: String = ""
    func append(_ token: String) { text += token }
}

@Test("ModelRuntimeService loads and streams simulated tokens")
@MainActor
func runtimeStreaming() async throws {
    let svc = ModelRuntimeService()

    // Create a temporary fake bundle path to satisfy file existence check
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let fakeBundle = tempDir.appendingPathComponent("dummy.bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: fakeBundle, withIntermediateDirectories: true)

    try await svc.loadModel(at: fakeBundle)

    let acc = _Accumulator()
    try await svc.streamResponse(prompt: "hello") { token in
        await acc.append(token)
    }
    let collected = await acc.text
    #expect(collected.contains("Echo:"))
}
