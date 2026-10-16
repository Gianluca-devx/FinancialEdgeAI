//
//  AdapterInfo.swift
//  FinancialEdgeAI
//
//  Created by Gianluca Pascarella on 16/10/2026.
//
import CryptoKit
import Foundation

/// What identifies a LoRA adapter in a report: its name, its size and the hashes of its two files, so a result
/// can always be tied to the exact weights that produced it. Pure: it only reads the folder.
///
/// An adapter folder is what `mlx_lm.lora` writes: `adapter_config.json` and `adapters.safetensors`.
nonisolated struct AdapterInfo: Codable, Equatable, Sendable {
    let name: String
    /// The rank of the two thin matrices (8 means 8 columns of A and 8 rows of B).
    let rank: Int
    /// How many layers carry an adapter (the last ones of the model).
    let layers: Int
    let scale: Double
    /// SHA-256 of `adapter_config.json` and of `adapters.safetensors`.
    let configHash: String
    let weightsHash: String

    static let configFileName = "adapter_config.json"
    static let weightsFileName = "adapters.safetensors"

    enum ReadError: Error, Equatable, LocalizedError {
        case missingFile(String)
        case invalidConfiguration(String)

        var errorDescription: String? {
            switch self {
            case .missingFile(let path):
                "The adapter file \(path) is missing. Copy the adapter folder to the app's Documents/Adapters."
            case .invalidConfiguration(let reason):
                "The adapter configuration cannot be read: \(reason)"
            }
        }
    }

    /// Reads the configuration of the adapter in `directory` and hashes its files.
    static func read(directory: URL, name: String) throws -> AdapterInfo {
        struct Configuration: Decodable {
            struct Parameters: Decodable {
                let rank: Int
                let scale: Double
            }
            let numLayers: Int
            let loraParameters: Parameters

            enum CodingKeys: String, CodingKey {
                case numLayers = "num_layers"
                case loraParameters = "lora_parameters"
            }
        }

        let configURL = directory.appending(path: configFileName)
        let weightsURL = directory.appending(path: weightsFileName)
        for url in [configURL, weightsURL] where !FileManager.default.fileExists(atPath: url.path) {
            throw ReadError.missingFile("\(name)/\(url.lastPathComponent)")
        }

        let configData = try Data(contentsOf: configURL)
        let configuration: Configuration
        do {
            configuration = try JSONDecoder().decode(Configuration.self, from: configData)
        } catch {
            throw ReadError.invalidConfiguration(error.localizedDescription)
        }
        guard configuration.loraParameters.rank > 0, configuration.numLayers > 0 else {
            throw ReadError.invalidConfiguration("the rank and the number of layers must be positive")
        }

        return AdapterInfo(
            name: name,
            rank: configuration.loraParameters.rank,
            layers: configuration.numLayers,
            scale: configuration.loraParameters.scale,
            configHash: hash(of: configData),
            weightsHash: hash(of: try Data(contentsOf: weightsURL, options: .mappedIfSafe)))
    }

    /// For the screen: "lora-v1 (rank 8, 16 layers)".
    var summary: String {
        "\(name) (rank \(rank), \(layers) layers)"
    }

    private static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
