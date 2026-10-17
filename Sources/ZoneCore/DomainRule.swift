import Foundation

public enum DomainRule {
    /// Whole domains only; paths are rejected rather than silently broadening a block.
    public static func normalize(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("*.") { value.removeFirst(2) }
        let candidate = value.contains("://") ? value : "https://" + value
        guard let url = URLComponents(string: candidate),
              ["http", "https"].contains(url.scheme), url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              var host = URL(string: candidate)?.host?.lowercased() else { throw ZoneError.invalidDomain(input) }
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard host.utf8.count <= 253, labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                      && label.unicodeScalars.allSatisfy { allowed.contains($0) }
              }), !labels.allSatisfy({ Int($0) != nil }) else { throw ZoneError.invalidDomain(input) }
        return host
    }

    public static func matches(host: String, domain: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == domain || host.hasSuffix("." + domain)
    }

    public static func parseList(_ text: String) throws -> [String] {
        let entries = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
        return try Set(entries.filter { !$0.isEmpty }.map(normalize)).sorted()
    }
}
