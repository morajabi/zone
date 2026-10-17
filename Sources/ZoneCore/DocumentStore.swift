import Foundation

public struct DocumentStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> ZoneDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return ZoneDocument() }
        let document = try JSONDecoder().decode(ZoneDocument.self, from: Data(contentsOf: url))
        guard document.version == 1 else { throw ZoneError.unsupportedVersion }
        return document
    }

    public func save(_ document: ZoneDocument) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
