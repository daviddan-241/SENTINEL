import Foundation

/// Keccak-256 as used by Ethereum (the original Keccak padding 0x01, not SHA-3's 0x06).
public enum Keccak256 {
    static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    /// ρ rotation offsets, indexed by lane = x + 5y. Lane (0, 0) stays put.
    static let rotationOffsets: [Int] = [
        // y = 0     y = 1     y = 2     y = 3     y = 4
        0, 1, 62, 28, 27,          // x = 0
        36, 44, 6, 55, 20,         // x = 1
        3, 10, 43, 25, 39,         // x = 2
        41, 45, 15, 21, 8,         // x = 3
        18, 2, 61, 56, 14,         // x = 4
    ]

    static let permutation: [Int] = [
        10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4,
        15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1,
    ]

    /// 32-byte digest.
    public static func hash(_ message: Data) -> Data {
        let rate = 136                    // 1088 bits
        var state = [UInt64](repeating: 0, count: 25)

        var padded = Data(message)        // re-base: Data slices keep their start index
        padded.append(0x01)               // Keccak padding
        while padded.count % rate != rate - 1 { padded.append(0) }
        padded.append(0x80)

        var offset = 0
        while offset < padded.count {
            for i in 0..<(rate / 8) {
                let o = offset + i * 8
                var lane: UInt64 = 0
                for j in 0..<8 { lane |= UInt64(padded[o + j]) << (8 * UInt64(j)) }
                state[i] ^= lane
            }
            permute(&state)
            offset += rate
        }

        var out = Data()
        for i in 0..<4 {                   // 4 lanes = 32 bytes
            for j in 0..<8 { out.append(UInt8((state[i] >> (8 * UInt64(j))) & 0xff)) }
        }
        return out
    }

    static func permute(_ a: inout [UInt64]) {
        var c = [UInt64](repeating: 0, count: 5)
        var d = [UInt64](repeating: 0, count: 5)
        var b = [UInt64](repeating: 0, count: 25)

        for round in 0..<24 {
            for x in 0..<5 {
                c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
            }
            for x in 0..<5 {
                d[x] = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1)
            }
            for x in 0..<5 {
                for y in 0..<5 { a[x + 5 * y] ^= d[x] }
            }

            for x in 0..<5 {
                for y in 0..<5 {
                    let index = x + 5 * y
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(a[index], rotationOffsets[index])
                }
            }

            for x in 0..<5 {
                for y in 0..<5 { a[x + 5 * y] = b[x + 5 * y] ^ ((~b[(x + 1) % 5 + 5 * y]) & b[(x + 2) % 5 + 5 * y]) }
            }

            a[0] ^= roundConstants[round]
        }
    }

    @inline(__always) static func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
        n == 0 ? x : (x << UInt64(n)) | (x >> UInt64(64 - n))
    }
}
