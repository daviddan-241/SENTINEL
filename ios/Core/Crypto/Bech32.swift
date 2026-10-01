import Foundation

/// Bech32 / Bech32m (BIP-173, BIP-350) — SegWit addresses.
public enum Bech32 {
    public enum Variant { case bech32, bech32m }

    static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    static let charsetIndex: [Character: UInt8] = {
        var map = [Character: UInt8]()
        for (i, c) in charset.enumerated() { map[c] = UInt8(i) }
        return map
    }()

    static func polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for value in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(value)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 { chk ^= generators[i] }
        }
        return chk
    }

    static func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    public static func encode(hrp: String, data: [UInt8], variant: Variant) -> String {
        let constant: UInt32 = variant == .bech32 ? 1 : 0x2bc830a3
        var values = hrpExpand(hrp) + data
        let checksumLength = 6
        let polymodValue = polymod(values + [0, 0, 0, 0, 0, 0]) ^ constant
        var checksum = [UInt8]()
        for i in 0..<checksumLength {
            checksum.append(UInt8((polymodValue >> UInt32(5 * (5 - i))) & 31))
        }
        values = data + checksum
        var out = hrp + "1"
        for value in values { out.append(charset[Int(value)]) }
        return out
    }

    public struct Decoded {
        public let hrp: String
        public let data: [UInt8]
        public let variant: Variant
    }

    public static func decode(_ string: String) -> Decoded? {
        let lower = string.lowercased()
        guard lower == string || string.uppercased() == string else { return nil }   // no mixed case
        guard let separator = lower.lastIndex(of: "1") else { return nil }
        let hrp = String(lower[lower.startIndex..<separator])
        guard (1...83).contains(hrp.count),
              hrp.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else { return nil }
        let dataPart = String(lower[lower.index(after: separator)...])
        guard dataPart.count >= 6 else { return nil }

        var values = [UInt8]()
        for character in dataPart {
            guard let value = charsetIndex[character] else { return nil }
            values.append(value)
        }
        let check = polymod(hrpExpand(hrp) + values)
        let variant: Variant
        switch check {
        case 1: variant = .bech32
        case 0x2bc830a3: variant = .bech32m
        default: return nil
        }
        return Decoded(hrp: hrp, data: Array(values.dropLast(6)), variant: variant)
    }

    public static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var accumulator = 0, bits = 0
        var out = [UInt8]()
        let maxValue = (1 << to) - 1
        for value in data {
            if Int(value) >> from != 0 { return nil }
            accumulator = (accumulator << from) | Int(value)
            bits += from
            while bits >= to {
                bits -= to
                out.append(UInt8((accumulator >> bits) & maxValue))
            }
        }
        if pad {
            if bits > 0 { out.append(UInt8((accumulator << (to - bits)) & maxValue)) }
        } else if bits >= from || ((accumulator << (to - bits)) & maxValue) != 0 {
            return nil
        }
        return out
    }

    /// hrp1q… / hrp1p… for a given witness version and program.
    public static func encodeSegwit(hrp: String, version: UInt8, program: Data) -> String {
        let variant: Variant = version == 0 ? .bech32 : .bech32m
        guard let converted = convertBits([UInt8](program), from: 8, to: 5, pad: true) else { return "" }
        return encode(hrp: hrp, data: [version] + converted, variant: variant)
    }

    public static func decodeSegwit(_ address: String) -> (hrp: String, version: UInt8, program: Data)? {
        // BIP-173 caps a segwit address at 90 characters; anything longer is not one.
        guard address.count <= 90 else { return nil }
        guard let decoded = decode(address), !decoded.data.isEmpty else { return nil }
        let version = decoded.data[0]
        guard version <= 16 else { return nil }
        guard let program = convertBits(Array(decoded.data.dropFirst()), from: 5, to: 8, pad: false) else { return nil }
        guard (2...40).contains(program.count) else { return nil }
        if version == 0 && program.count != 20 && program.count != 32 { return nil }
        if version == 0 && decoded.variant != .bech32 { return nil }
        if version > 0 && decoded.variant != .bech32m { return nil }
        return (decoded.hrp, version, Data(program))
    }
}
