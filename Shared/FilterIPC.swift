import Foundation

@objc protocol ZoneFilterIPC {
    func replacePolicy(_ data: Data, reply: @escaping (String?) -> Void)
    func status(reply: @escaping (String) -> Void)
}

enum FilterIdentity {
    static var bundleID: String { identifier("ZoneFilterBundleIdentifier") ?? "dev.example.Zone.filter" }
    static var appBundleID: String { identifier("ZoneAppBundleIdentifier") ?? "dev.example.Zone" }

    static var teamID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ZoneTeamIdentifier") as? String,
              value.count == 10, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return value
    }

    static var machService: String? { identifier("ZoneMachService") }

    private static func identifier(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return nil }
        return value
    }

    static func requirement(identifier: String, team: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}
