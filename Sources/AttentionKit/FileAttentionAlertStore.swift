import Foundation

public actor FileAttentionAlertStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(
        directory: URL,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func save(_ alert: AttentionAlert) async throws {
        try ensureDirectoryExists()

        let fileURL = directory.appending(path: "\(alert.createdAt.timeIntervalSince1970)-\(alert.id.uuidString).json")
        let data = try encoder.encode(alert)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadAll() async throws -> [AttentionAlert] {
        guard fileManager.fileExists(atPath: directory.path()) else {
            return []
        }

        return try fileManager
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                let data = try Data(contentsOf: url)
                return try decoder.decode(AttentionAlert.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func delete(ids: [UUID]) async throws {
        guard !ids.isEmpty, fileManager.fileExists(atPath: directory.path()) else {
            return
        }

        let idSet = Set(ids)
        let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

        for url in fileURLs where url.pathExtension == "json" {
            let data = try Data(contentsOf: url)
            let alert = try decoder.decode(AttentionAlert.self, from: data)
            if idSet.contains(alert.id) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func ensureDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: directory.path()) else {
            return
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
