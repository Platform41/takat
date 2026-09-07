import Foundation

enum UsageCache {
    static let schemaVersion = 1
    static let fileName = "usage-cache.json"

    struct Payload: Codable, Sendable {
        let schema: Int
        let snapshots: [ProviderID: UsageSnapshot]
        let lastUpdated: [ProviderID: Date]
    }

    static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func load(from directory: URL) -> Payload? {
        let url = fileURL(in: directory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        guard payload.schema == schemaVersion else { return nil }
        return payload
    }

    static func save(_ payload: Payload, to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL(in: directory), options: .atomic)
        } catch {
            // Best-effort caching: ignore write failures.
        }
    }
}
