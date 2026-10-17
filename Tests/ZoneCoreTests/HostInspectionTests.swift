import Foundation
import Testing
@testable import ZoneCore

struct HostInspectionTests {
    @Test func httpAndPartialHeaders() {
        #expect(HostInspection.inspect(Data("GET / HTTP/1.1\r\nHost: Example.COM:443\r\n\r\n".utf8)) == .host("example.com"))
        #expect(HostInspection.inspect(Data("GET / HTTP/1.1\r\nHost: ex".utf8)) == .needsMore)
        #expect(HostInspection.inspect(Data("SSH-2.0-example".utf8)) == .unknown)
    }

    @Test func tlsClientHelloAndFragments() {
        let hello = clientHello(host: "video.example.com")
        #expect(HostInspection.inspect(hello) == .host("video.example.com"))
        for count in 0..<hello.count { #expect(HostInspection.inspect(hello.prefix(count)) == .needsMore) }
        let handshake = Array(hello.dropFirst(5))
        let split = Data(record(Array(handshake.prefix(20))) + record(Array(handshake.dropFirst(20))))
        #expect(HostInspection.inspect(split) == .host("video.example.com"))
    }

    @Test func encryptedClientHelloCannotBeMistakenForRealHost() {
        #expect(HostInspection.inspect(clientHello(host: "public.example.com", ech: true)) == .unknown)
    }

    @Test func malformedDataIsBoundedAndDoesNotCrash() {
        #expect(HostInspection.inspect(Data([22, 3, 3, 255, 255])) == .unknown)
        for length in 1...512 {
            var bytes = [UInt8](repeating: 255, count: length)
            bytes[0] = 22
            _ = HostInspection.inspect(Data(bytes))
        }
        #expect(HostInspection.inspect(Data(repeating: 65, count: 100_000)) == .unknown)
    }

    private func word(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 255), UInt8(value & 255)] }
    private func record(_ body: [UInt8]) -> [UInt8] { [22, 3, 3] + word(body.count) + body }
    private func clientHello(host: String, ech: Bool = false) -> Data {
        let name = Array(host.utf8)
        let serverName = word(name.count + 3) + [0] + word(name.count) + name
        var extensions = [UInt8(0), 0] + word(serverName.count) + serverName
        if ech { extensions += [0xfe, 0x0d, 0, 1, 0] }
        let body = [UInt8(3), 3] + [UInt8](repeating: 0, count: 32) + [0, 0, 2, 0x13, 1, 1, 0] + word(extensions.count) + extensions
        let handshake = [UInt8(1), 0] + word(body.count) + body
        return Data(record(handshake))
    }
}
