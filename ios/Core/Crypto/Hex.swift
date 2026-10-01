import Foundation

public extension Data {
    /// Lowercase hex, no separators.
    var hexString: String {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        out.reserveCapacity(count * 2)
        for b in self {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Parses hex, ignoring spaces, colons and dashes. Fails on odd length or bad digits.
    init?(hex: String) {
        let cleaned = hex.lowercased().filter { !" \t\n:-".contains($0) }
        if cleaned.hasPrefix("0x") { return nil }          // callers strip prefixes explicitly
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}

public enum Hex {
    /// Strips an optional 0x/0X prefix and validates the rest is hex of the expected length.
    public static func bytes(_ string: String, expectingBytes: Int? = nil) -> Data? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("0x") { s = String(s.dropFirst(2)) }
        guard let data = Data(hex: s) else { return nil }
        if let expected = expectingBytes, data.count != expected { return nil }
        return data
    }
}
