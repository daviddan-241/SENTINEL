import Foundation

/// Minimal fixed-width 256-bit unsigned integer used by the secp256k1 field and scalar
/// arithmetic. Four 64-bit limbs, little-endian (l0 = least significant).
///
/// Only the operations the wallet needs are implemented, and each one is covered by the
/// test suite through the BIP-32 and address vectors.
public struct UInt256: Equatable, Comparable, Sendable {
    public var l0: UInt64, l1: UInt64, l2: UInt64, l3: UInt64

    public init(l0: UInt64, l1: UInt64, l2: UInt64, l3: UInt64) {
        self.l0 = l0; self.l1 = l1; self.l2 = l2; self.l3 = l3
    }

    public init(_ value: UInt64) { self.init(l0: value, l1: 0, l2: 0, l3: 0) }

    /// Big-endian 32 bytes (the way keys and field elements are serialised).
    public init(_ data: Data) {
        precondition(data.count == 32, "UInt256 needs exactly 32 bytes")
        let bytes = [UInt8](data)
        func limb(_ offset: Int) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<8 { v = (v << 8) | UInt64(bytes[offset + i]) }
            return v
        }
        self.init(l0: limb(24), l1: limb(16), l2: limb(8), l3: limb(0))
    }

    public var data: Data {
        var out = Data()
        for limb in [l3, l2, l1, l0] {
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8((limb >> UInt64(shift)) & 0xff))
            }
        }
        return out
    }

    public var hexString: String { data.hexString }

    public var isZero: Bool { l0 == 0 && l1 == 0 && l2 == 0 && l3 == 0 }

    public var isOdd: Bool { l0 & 1 == 1 }

    public static func < (a: UInt256, b: UInt256) -> Bool {
        if a.l3 != b.l3 { return a.l3 < b.l3 }
        if a.l2 != b.l2 { return a.l2 < b.l2 }
        if a.l1 != b.l1 { return a.l1 < b.l1 }
        return a.l0 < b.l0
    }

    public func bit(_ index: Int) -> Bool {
        precondition((0..<256).contains(index))
        let limb: UInt64
        switch index / 64 {
        case 0: limb = l0
        case 1: limb = l1
        case 2: limb = l2
        default: limb = l3
        }
        return (limb >> UInt64(index % 64)) & 1 == 1
    }

    /// Wrapping addition returning the carry out of the top limb.
    public func adding(_ other: UInt256) -> (value: UInt256, carry: UInt64) {
        var out = UInt64(0), carry: UInt64 = 0
        var result = [UInt64](repeating: 0, count: 4)
        for (i, pair) in [(l0, other.l0), (l1, other.l1), (l2, other.l2), (l3, other.l3)].enumerated() {
            let (s1, c1) = pair.0.addingReportingOverflow(pair.1)
            let (s2, c2) = s1.addingReportingOverflow(carry)
            result[i] = s2
            carry = (c1 ? 1 : 0) + (c2 ? 1 : 0)
        }
        out = carry
        return (UInt256(l0: result[0], l1: result[1], l2: result[2], l3: result[3]), out)
    }

    /// Wrapping subtraction returning the borrow out of the top limb.
    public func subtracting(_ other: UInt256) -> (value: UInt256, borrow: UInt64) {
        var result = [UInt64](repeating: 0, count: 4)
        var borrow: UInt64 = 0
        for (i, pair) in [(l0, other.l0), (l1, other.l1), (l2, other.l2), (l3, other.l3)].enumerated() {
            let (d1, b1) = pair.0.subtractingReportingOverflow(pair.1)
            let (d2, b2) = d1.subtractingReportingOverflow(borrow)
            result[i] = d2
            borrow = (b1 ? 1 : 0) + (b2 ? 1 : 0)
        }
        return (UInt256(l0: result[0], l1: result[1], l2: result[2], l3: result[3]), borrow)
    }

    /// 256×256 → 512 bit product.
    public func multipliedFullWidth(by other: UInt256) -> (high: UInt256, low: UInt256) {
        let a = [l0, l1, l2, l3]
        let b = [other.l0, other.l1, other.l2, other.l3]
        var r = [UInt64](repeating: 0, count: 8)

        for i in 0..<4 {
            var carry: UInt64 = 0
            for j in 0..<4 {
                let (high, low) = a[i].multipliedFullWidth(by: b[j])
                let (s1, c1) = r[i + j].addingReportingOverflow(low)
                let (s2, c2) = s1.addingReportingOverflow(carry)
                r[i + j] = s2
                carry = high &+ (c1 ? 1 : 0) &+ (c2 ? 1 : 0)
            }
            var k = i + 4
            while carry != 0 && k < 8 {
                let (s, overflow) = r[k].addingReportingOverflow(carry)
                r[k] = s
                carry = overflow ? 1 : 0
                k += 1
            }
        }
        return (UInt256(l0: r[4], l1: r[5], l2: r[6], l3: r[7]),
                UInt256(l0: r[0], l1: r[1], l2: r[2], l3: r[3]))
    }

    /// Multiplies by a single limb, returning the 5th limb as the carry.
    public func multiplied(by limb: UInt64) -> (value: UInt256, carry: UInt64) {
        var result = [UInt64](repeating: 0, count: 4)
        var carry: UInt64 = 0
        for (i, l) in [l0, l1, l2, l3].enumerated() {
            let (high, low) = l.multipliedFullWidth(by: limb)
            let (sum, overflow) = low.addingReportingOverflow(carry)
            result[i] = sum
            carry = high &+ (overflow ? 1 : 0)
        }
        return (UInt256(l0: result[0], l1: result[1], l2: result[2], l3: result[3]), carry)
    }
}
