//
//  AdapterInfoTests.swift
//  FinancialEdgeAITests
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import CryptoKit
import Foundation
import Testing

struct AdapterInfoTests {

    /// The relevant part of the `adapter_config.json` that `mlx_lm.lora` writes for `Scripts/lora/lora-v1.yaml`.
    private static let configuration = """
    {
        "adapter_path": "adapters/lora-v1",
        "batch_size": 4,
        "fine_tune_type": "lora",
        "iters": 300,
        "learning_rate": 0.0001,
        "lora_parameters": {"rank": 8, "scale": 20.0, "dropout": 0.0},
        "mask_prompt": true,
        "model": "mlx-community/Qwen3-4B-4bit",
        "num_layers": 16,
        "seed": 1
    }
    """

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A folder like the one `mlx_lm.lora` writes. A nil file is left out.
    private func folder(configuration: String? = AdapterInfoTests.configuration, weights: Data? = Data("abc".utf8)) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "adapter-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let configuration {
            try Data(configuration.utf8).write(to: url.appending(path: AdapterInfo.configFileName))
        }
        if let weights {
            try weights.write(to: url.appending(path: AdapterInfo.weightsFileName))
        }
        return url
    }

    @Test func readsTheConfigurationAndHashesBothFiles() throws {
        let url = try folder()
        let info = try AdapterInfo.read(directory: url, name: "lora-v1")
        #expect(info.name == "lora-v1")
        #expect(info.rank == 8)
        #expect(info.layers == 16)
        #expect(info.scale == 20)
        #expect(info.weightsHash == sha256(Data("abc".utf8)))
        #expect(info.weightsHash == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(info.configHash == sha256(Data(Self.configuration.utf8)))
        #expect(info.summary == "lora-v1 (rank 8, 16 layers)")
    }

    @Test func aChangedWeightsFileChangesItsHashOnly() throws {
        let first = try AdapterInfo.read(directory: folder(), name: "a")
        let second = try AdapterInfo.read(directory: folder(weights: Data("abd".utf8)), name: "a")
        #expect(first.weightsHash != second.weightsHash)
        #expect(first.configHash == second.configHash)
    }

    @Test func aMissingWeightsFileIsReportedWithItsName() throws {
        let url = try folder(weights: nil)
        #expect(throws: AdapterInfo.ReadError.missingFile("lora-v1/adapters.safetensors")) {
            try AdapterInfo.read(directory: url, name: "lora-v1")
        }
    }

    @Test func aMissingConfigurationIsReportedWithItsName() throws {
        let url = try folder(configuration: nil)
        #expect(throws: AdapterInfo.ReadError.missingFile("lora-v1/adapter_config.json")) {
            try AdapterInfo.read(directory: url, name: "lora-v1")
        }
    }

    @Test func aFolderThatDoesNotExistIsReported() {
        let url = FileManager.default.temporaryDirectory.appending(path: "no-such-adapter-\(UUID().uuidString)")
        #expect(throws: AdapterInfo.ReadError.missingFile("nope/adapter_config.json")) {
            try AdapterInfo.read(directory: url, name: "nope")
        }
    }

    @Test func aConfigurationThatIsNotJSONIsRejected() throws {
        let url = try folder(configuration: "not json")
        #expect {
            try AdapterInfo.read(directory: url, name: "x")
        } throws: { error in
            if case AdapterInfo.ReadError.invalidConfiguration = error { return true }
            return false
        }
    }

    @Test func aConfigurationWithoutTheLoRAParametersIsRejected() throws {
        let url = try folder(configuration: #"{"num_layers": 16}"#)
        #expect {
            try AdapterInfo.read(directory: url, name: "x")
        } throws: { error in
            if case AdapterInfo.ReadError.invalidConfiguration = error { return true }
            return false
        }
    }

    @Test func aRankOfZeroIsRejected() throws {
        let zero = Self.configuration.replacingOccurrences(of: "\"rank\": 8", with: "\"rank\": 0")
        let url = try folder(configuration: zero)
        #expect(throws: AdapterInfo.ReadError.invalidConfiguration("the rank and the number of layers must be positive")) {
            try AdapterInfo.read(directory: url, name: "x")
        }
    }

    // MARK: - The report

    private func metadata(adapter: AdapterInfo?) -> EvaluationReport.Metadata {
        EvaluationReport.Metadata(
            date: "2026-10-16T00:00:00Z", model: "m", device: "d", system: "s", temperature: 0.2, maxTokens: 384,
            runs: 3, seeds: [1, 2, 3], examples: 30, promptHash: "p", testSetHash: "t", schemaHash: "s",
            tier: "core", keys: ["revenue"], adapter: adapter, modelLoadSeconds: nil)
    }

    private func encoded(_ metadata: EvaluationReport.Metadata) throws -> [String: Any] {
        let data = try JSONEncoder().encode(metadata)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func aReportWithoutAnAdapterHasNoAdapterKey() throws {
        let json = try encoded(metadata(adapter: nil))
        #expect(json["adapter"] == nil)
        #expect(json["tier"] as? String == "core")
    }

    @Test func aReportWithAnAdapterRecordsItsNameSizeAndHashes() throws {
        let info = try AdapterInfo.read(directory: folder(), name: "lora-v1")
        let json = try encoded(metadata(adapter: info))
        let adapter = try #require(json["adapter"] as? [String: Any])
        #expect(adapter["name"] as? String == "lora-v1")
        #expect(adapter["rank"] as? Int == 8)
        #expect(adapter["layers"] as? Int == 16)
        #expect(adapter["weightsHash"] as? String == info.weightsHash)
        #expect(adapter["configHash"] as? String == info.configHash)
    }
}
