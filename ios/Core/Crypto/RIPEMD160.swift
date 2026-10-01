import Foundation

/// RIPEMD-160 (ISO/IEC 10118-3), needed for Bitcoin's HASH160 = RIPEMD160(SHA256(x)).
public enum RIPEMD160 {
    static let r1: [Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
                            7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
                            3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
                            1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
                            4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13]
    static let r2: [Int] = [5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
                            6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
                            15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
                            8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
                            12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11]
    static let s1: [UInt32] = [11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
                               7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
                               11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
                               11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
                               9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6]
    static let s2: [UInt32] = [8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
                               9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
                               9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
                               15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
                               8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11]
    static let k1: [UInt32] = [0x00000000, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xa953fd4e]
    static let k2: [UInt32] = [0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0x7a6d76e9, 0x00000000]

    public static func hash(_ message: Data) -> Data {
        var h: [UInt32] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0]
        var padded = [UInt8](Data(message))
        let bitLength = UInt64(message.count) * 8
        padded.append(0x80)
        while padded.count % 64 != 56 { padded.append(0) }
        for shift in stride(from: 0, through: 56, by: 8) {
            padded.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var x = [UInt32](repeating: 0, count: 16)
        var offset = 0
        while offset < padded.count {
            for i in 0..<16 {
                let o = offset + i * 4
                x[i] = UInt32(padded[o]) | UInt32(padded[o + 1]) << 8
                     | UInt32(padded[o + 2]) << 16 | UInt32(padded[o + 3]) << 24
            }
            var (al, bl, cl, dl, el) = (h[0], h[1], h[2], h[3], h[4])
            var (ar, br, cr, dr, er) = (h[0], h[1], h[2], h[3], h[4])

            for j in 0..<80 {
                let round = j / 16
                var t = al &+ f(round, bl, cl, dl) &+ x[r1[j]] &+ k1[round]
                t = rotl(t, s1[j]) &+ el
                al = el; el = dl; dl = rotl(cl, 10); cl = bl; bl = t

                t = ar &+ f(4 - round, br, cr, dr) &+ x[r2[j]] &+ k2[round]
                t = rotl(t, s2[j]) &+ er
                ar = er; er = dr; dr = rotl(cr, 10); cr = br; br = t
            }
            let t = h[1] &+ cl &+ dr
            h[1] = h[2] &+ dl &+ er
            h[2] = h[3] &+ el &+ ar
            h[3] = h[4] &+ al &+ br
            h[4] = h[0] &+ bl &+ cr
            h[0] = t
            offset += 64
        }

        var out = Data()
        for word in h {
            out.append(UInt8(word & 0xff)); out.append(UInt8((word >> 8) & 0xff))
            out.append(UInt8((word >> 16) & 0xff)); out.append(UInt8((word >> 24) & 0xff))
        }
        return out
    }

    @inline(__always) static func f(_ round: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch round {
        case 0: return x ^ y ^ z
        case 1: return (x & y) | (~x & z)
        case 2: return (x | ~y) ^ z
        case 3: return (x & z) | (y & ~z)
        default: return x ^ (y | ~z)
        }
    }

    @inline(__always) static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }
}
