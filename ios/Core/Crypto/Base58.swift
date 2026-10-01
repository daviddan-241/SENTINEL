import Foundation

/// Base58 and Base58Check (Bitcoin alphabet, leading-zero preserving).
public enum Base58 {
    static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    static let index: [UInt8: Int] = {
        var map = [UInt8: Int]()
        for (i, c) in alphabet.enumerated() { map[c] = i }
        return map
    }()

    public static func encode(_ data: Data) -> String {
        if data.isEmpty { return "" }
        var digits: [UInt8] = [0]
        for byte in data {
            var carry = Int(byte)
            for i in 0..<digits.count {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        var out = ""
        for byte in data.prefix(while: { $0 == 0 }) { _ = byte; out.append("1") }
        for digit in digits.reversed() { out.append(Character(UnicodeScalar(alphabet[Int(digit)]))) }
        return out
    }

    public static func decode(_ string: String) -> Data? {
        if string.isEmpty { return Data() }
        var bytes: [UInt8] = [0]
        for character in string.utf8 {
            guard let value = index[character] else { return nil }
            var carry = value
            for i in 0..<bytes.count {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xff))
                carry >>= 8
            }
        }
        var out = Data()
        for character in string.prefix(while: { $0 == "1" }) { _ = character; out.append(0) }
        out.append(contentsOf: bytes.reversed().drop(while: { $0 == 0 }))
        return out
    }

    /// Base58Check with a 4-byte double-SHA256 checksum.
    public static func encodeCheck(_ payload: Data) -> String {
        let checksum = SHA256.hash(SHA256.hash(payload)).prefix(4)
        return encode(payload + checksum)
    }

    public static func decodeCheck(_ string: String) -> Data? {
        guard let raw = decode(string), raw.count >= 5 else { return nil }
        let payload = raw.prefix(raw.count - 4)
        let checksum = raw.suffix(4)
        guard SHA256.hash(SHA256.hash(payload)).prefix(4) == checksum else { return nil }
        return Data(payload)
    }
}
