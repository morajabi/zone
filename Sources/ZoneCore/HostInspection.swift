import Foundation

/// Inspects only HTTP headers / TLS ClientHello metadata, never decrypting HTTPS.
public enum HostInspection {
    public enum Result: Equatable, Sendable {
        case host(String)
        case needsMore
        case unknown
    }

    public static let maximumBytes = 65_536

    public static func inspect(_ data: Data) -> Result {
        let bytes = Array(data.prefix(maximumBytes))
        guard !bytes.isEmpty else { return .needsMore }
        if bytes[0] == 22 { return tls(bytes) }
        guard let header = String(bytes: bytes, encoding: .utf8) else { return .unknown }
        let methods = ["GET ", "POST ", "HEAD ", "PUT ", "DELETE ", "OPTIONS ", "PATCH ", "CONNECT "]
        guard methods.contains(where: { header.hasPrefix($0) || $0.hasPrefix(header) }) else { return .unknown }
        guard let end = header.range(of: "\r\n\r\n") else {
            return bytes.count < maximumBytes ? .needsMore : .unknown
        }
        for line in header[..<end.lowerBound].components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "host" else { continue }
            let authority = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard let host = URLComponents(string: "http://" + authority)?.host else { return .unknown }
            return .host(host.lowercased())
        }
        return .unknown
    }

    private static func tls(_ bytes: [UInt8]) -> Result {
        var handshake: [UInt8] = []
        var record = 0
        while record < bytes.count {
            guard record + 5 <= bytes.count else { return incomplete(bytes.count) }
            guard bytes[record] == 22, bytes[record + 1] == 3 else { return .unknown }
            let length = int16(bytes, record + 3)
            guard length > 0, record + 5 + length <= maximumBytes else { return .unknown }
            guard record + 5 + length <= bytes.count else { return incomplete(bytes.count) }
            handshake += bytes[(record + 5)..<(record + 5 + length)]
            if handshake.count >= 4 {
                guard handshake[0] == 1 else { return .unknown }
                let size = Int(handshake[1]) << 16 | Int(handshake[2]) << 8 | Int(handshake[3])
                guard size + 4 <= maximumBytes else { return .unknown }
                if handshake.count >= size + 4 { return clientHello(Array(handshake.prefix(size + 4))) }
            }
            record += 5 + length
        }
        return incomplete(bytes.count)
    }

    private static func clientHello(_ bytes: [UInt8]) -> Result {
        // Handshake header, legacy version, random.
        var cursor = 38
        guard cursor < bytes.count else { return .unknown }
        let sessionLength = Int(bytes[cursor])
        cursor += 1 + sessionLength
        guard cursor + 2 <= bytes.count else { return .unknown }
        let cipherLength = int16(bytes, cursor)
        cursor += 2 + cipherLength
        guard cursor < bytes.count else { return .unknown }
        let compressionLength = Int(bytes[cursor])
        cursor += 1 + compressionLength
        guard cursor + 2 <= bytes.count else { return .unknown }
        let extensionsLength = int16(bytes, cursor)
        cursor += 2
        let end = cursor + extensionsLength
        guard end <= bytes.count else { return .unknown }
        var name: String?
        while cursor + 4 <= end {
            let kind = int16(bytes, cursor)
            let length = int16(bytes, cursor + 2)
            cursor += 4
            guard cursor + length <= end else { return .unknown }
            // An ECH outer hostname is not proof of the site's actual hostname.
            if kind == 0xfe0d { return .unknown }
            if kind == 0, length >= 5 {
                let namesEnd = cursor + 2 + int16(bytes, cursor)
                guard namesEnd <= cursor + length else { return .unknown }
                var position = cursor + 2
                while position + 3 <= namesEnd {
                    let nameType = bytes[position]
                    let nameLength = int16(bytes, position + 1)
                    position += 3
                    guard position + nameLength <= namesEnd else { return .unknown }
                    if nameType == 0, nameLength > 0 {
                        name = String(bytes: bytes[position..<(position + nameLength)], encoding: .utf8)?.lowercased()
                    }
                    position += nameLength
                }
            }
            cursor += length
        }
        guard cursor == end, let name else { return .unknown }
        return .host(name)
    }

    private static func int16(_ bytes: [UInt8], _ index: Int) -> Int {
        Int(bytes[index]) << 8 | Int(bytes[index + 1])
    }

    private static func incomplete(_ count: Int) -> Result { count < maximumBytes ? .needsMore : .unknown }
}
