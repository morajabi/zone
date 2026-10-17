import Foundation
import Testing
@testable import ZoneCore

struct BrowserPolicyTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func redirectsOnlyMatchingWebAddresses() throws {
        let session = try SessionEngine.start(list: .init(domains: ["example.org"]), minutes: 5, options: .init(), at: start)
        let policy = BrowserPolicy()
        policy.update(.init(sessions: [session]), enabled: true)
        #expect(policy.blocks("https://sub.example.org/watch?v=1", at: start))
        #expect(policy.blocks("http://EXAMPLE.ORG:8080/", at: start))
        #expect(!policy.blocks("https://example.org.evil.test/", at: start))
        #expect(!policy.blocks("https://unrelated.test/?next=example.org", at: start))
        #expect(!policy.blocks("file:///Applications/Zone.app/Contents/Resources/Blocked.html", at: start))
        #expect(!policy.blocks("data:text/html,example.org", at: start))
        #expect(!policy.blocks("about:blank", at: start))
    }

    @Test func workerSeesPauseResumeStopAndModeChangesWithoutWaitingForNextScan() throws {
        var session = try SessionEngine.start(list: .init(domains: ["example.org"]), minutes: 5,
                                            options: .init(pause: .init(minutes: 1)), at: start)
        let policy = BrowserPolicy()
        policy.update(.init(sessions: [session]), enabled: true)
        #expect(policy.blocks("https://example.org", at: start))
        try SessionEngine.pause(&session, at: start)
        policy.update(.init(sessions: [session]), enabled: true)
        #expect(!policy.blocks("https://example.org", at: start.addingTimeInterval(59)))
        #expect(policy.blocks("https://example.org", at: start.addingTimeInterval(60)))
        policy.update(.init(sessions: [session]), enabled: false)
        #expect(!policy.blocks("https://example.org", at: start.addingTimeInterval(61)))
        SessionEngine.resume(&session)
        try SessionEngine.stop(&session, at: start.addingTimeInterval(62))
        policy.update(.init(sessions: [session]), enabled: true)
        #expect(!policy.blocks("https://example.org", at: start.addingTimeInterval(63)))
    }

    @Test func expiryDoesNotWaitForUIClock() throws {
        let session = try SessionEngine.start(list: .init(domains: ["example.org"]), minutes: 1, options: .init(), at: start)
        let policy = BrowserPolicy()
        policy.update(.init(sessions: [session]), enabled: true)
        #expect(policy.blocks("https://example.org", at: start.addingTimeInterval(59)))
        #expect(!policy.blocks("https://example.org", at: start.addingTimeInterval(60)))
    }
}
