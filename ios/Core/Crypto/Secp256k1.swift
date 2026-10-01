import Foundation

/// secp256k1 — the curve Bitcoin, Ethereum, Solana's bridge tokens and every EVM chain use
/// for account keys.
///
/// Scope: public key derivation only (point multiplication, compression, x-only lifting and
/// the BIP-341 taproot tweak). There is no signing code in this app, so no nonce handling or
/// ECDSA is implemented at all.
///
/// The arithmetic is straightforward double-and-add over Jacobian coordinates with a
/// pseudo-Mersenne reduction for the field prime. It is *not* constant time: the inputs are
/// a recovery phrase the owner typed into their own unlocked device, the operation happens
/// once per import, and no attacker-controlled data drives the loop. Anything stronger
/// belongs in the Secure Enclave, which cannot do secp256k1 either.
public enum Secp256k1 {
    /// p = 2^256 − 2^32 − 977
    public static let p = UInt256(l0: 0xFFFFFFFEFFFFFC2F, l1: 0xFFFFFFFFFFFFFFFF,
                                  l2: 0xFFFFFFFFFFFFFFFF, l3: 0xFFFFFFFFFFFFFFFF)
    /// the curve order n
    public static let n = UInt256(l0: 0xBFD25E8CD0364141, l1: 0xBAAEDCE6AF48A03B,
                                  l2: 0xFFFFFFFFFFFFFFFE, l3: 0xFFFFFFFFFFFFFFFF)
    /// 2^256 mod p
    static let reductionConstant: UInt64 = 0x1000003D1

    public static let gx = UInt256(l0: 0x59F2815B16F81798, l1: 0x029BFCDB2DCE28D9,
                                   l2: 0x55A06295CE870B07, l3: 0x79BE667EF9DCBBAC)
    public static let gy = UInt256(l0: 0x9C47D08FFB10D4B8, l1: 0xFD17B448A6855419,
                                   l2: 0x5DA4FBFC0E1108A8, l3: 0x483ADA7726A3C465)

    public struct Point: Equatable, Sendable {
        public let x: UInt256
        public let y: UInt256
    }

    public static let generator = Point(x: gx, y: gy)

    // MARK: field arithmetic (mod p)

    static func addModP(_ a: UInt256, _ b: UInt256) -> UInt256 {
        let (sum, carry) = a.adding(b)
        if carry == 0 && sum < p { return sum }
        // sum + carry·2^256 ≡ sum + carry·c  (mod p)
        let (folded, foldCarry) = sum.adding(UInt256(carry &* reductionConstant))
        if foldCarry != 0 || folded >= p {
            let (again, _) = folded.subtracting(p)
            return again < p ? again : again.subtracting(p).value
        }
        return folded
    }

    static func subModP(_ a: UInt256, _ b: UInt256) -> UInt256 {
        let (difference, borrow) = a.subtracting(b)
        if borrow == 0 { return difference }
        return difference.adding(p).value
    }

    static func mulModP(_ a: UInt256, _ b: UInt256) -> UInt256 {
        let (high, low) = a.multipliedFullWidth(by: b)
        return reduce512(high: high, low: low)
    }

    static func sqrModP(_ a: UInt256) -> UInt256 { mulModP(a, a) }

    /// Reduces a 512-bit value modulo p = 2^256 − c, using 2^256 ≡ c (mod p).
    static func reduce512(high: UInt256, low: UInt256) -> UInt256 {
        var value = low
        var excess = high
        var guardCounter = 0
        while !excess.isZero {
            // value += excess·c ; the multiply overflows into at most one extra limb
            let (product, carry) = excess.multiplied(by: reductionConstant)
            let (sum, overflow) = value.adding(product)
            value = sum
            // the new excess is the multiply carry plus the addition overflow
            excess = UInt256(carry &+ (overflow != 0 ? 1 : 0))
            guardCounter += 1
            if guardCounter > 8 { break }        // cannot happen for valid inputs; keeps the loop bounded
        }
        while value >= p {
            value = value.subtracting(p).value
        }
        return value
    }

    /// Modular exponentiation by a 256-bit exponent.
    public static func power(_ base: UInt256, _ exponent: UInt256) -> UInt256 {
        var result = UInt256(1)
        var accumulator = base
        for bit in 0..<256 {
            if exponent.bit(bit) { result = mulModP(result, accumulator) }
            accumulator = sqrModP(accumulator)
        }
        return result
    }

    public static func inverse(_ a: UInt256) -> UInt256 {
        // p is prime, so a^(p−2) is the inverse
        power(a, p.subtracting(UInt256(2)).value)
    }

    /// BIP-340 lift_x: the curve point with this x coordinate and an even y.
    public static func liftX(_ x: UInt256) -> Point? {
        guard x < p else { return nil }
        // y² = x³ + 7
        let ySquared = addModP(mulModP(sqrModP(x), x), UInt256(7))
        // p ≡ 3 (mod 4), so the square root is pow(y², (p+1)/4)
        let exponent = p.adding(UInt256(1)).value
        let shifted = UInt256(l0: exponent.l0 >> 2 | exponent.l1 << 62,
                              l1: exponent.l1 >> 2 | exponent.l2 << 62,
                              l2: exponent.l2 >> 2 | exponent.l3 << 62,
                              l3: exponent.l3 >> 2)
        let y = power(ySquared, shifted)
        guard sqrModP(y) == ySquared else { return nil }
        return Point(x: x, y: y.isOdd ? subModP(p, y) : y)
    }

    // MARK: scalar arithmetic (mod n)

    public static func addModN(_ a: UInt256, _ b: UInt256) -> UInt256 {
        let (sum, carry) = a.adding(b)
        if carry == 0 && sum < n { return sum }
        let (difference, borrow) = sum.subtracting(n)
        if carry == 1 || borrow == 1 {
            // a + b ≥ 2^256 > n, so subtracting n is the right move; the wrap is handled above
            return difference
        }
        return difference
    }

    // MARK: point arithmetic (Jacobian coordinates)

    struct Jacobian {
        var x: UInt256, y: UInt256, z: UInt256
        static let infinity = Jacobian(x: .init(1), y: .init(1), z: .init(0))
        var isInfinity: Bool { z.isZero }
    }

    static func double(_ point: Jacobian) -> Jacobian {
        if point.isInfinity || point.y.isZero { return .infinity }
        let ySquared = sqrModP(point.y)
        let s = mulModP(UInt256(4), mulModP(point.x, ySquared))
        let m = mulModP(UInt256(3), sqrModP(point.x))            // a = 0 for secp256k1
        let xPrime = subModP(sqrModP(m), mulModP(UInt256(2), s))
        let yFourth = sqrModP(ySquared)
        let yPrime = subModP(mulModP(m, subModP(s, xPrime)), mulModP(UInt256(8), yFourth))
        let zPrime = mulModP(UInt256(2), mulModP(point.y, point.z))
        return Jacobian(x: xPrime, y: yPrime, z: zPrime)
    }

    static func add(_ first: Jacobian, _ second: Jacobian) -> Jacobian {
        if first.isInfinity { return second }
        if second.isInfinity { return first }
        let z1Squared = sqrModP(first.z), z2Squared = sqrModP(second.z)
        let u1 = mulModP(first.x, z2Squared), u2 = mulModP(second.x, z1Squared)
        let s1 = mulModP(first.y, mulModP(second.z, z2Squared))
        let s2 = mulModP(second.y, mulModP(first.z, z1Squared))

        if u1 == u2 {
            if s1 != s2 { return .infinity }        // P + (−P)
            return double(first)                    // P + P
        }
        let h = subModP(u2, u1)
        let r = subModP(s2, s1)
        let hSquared = sqrModP(h), hCubed = mulModP(h, hSquared)
        let u1hSquared = mulModP(u1, hSquared)
        let x3 = subModP(subModP(sqrModP(r), hCubed), mulModP(UInt256(2), u1hSquared))
        let y3 = subModP(mulModP(r, subModP(u1hSquared, x3)), mulModP(s1, hCubed))
        let z3 = mulModP(h, mulModP(first.z, second.z))
        return Jacobian(x: x3, y: y3, z: z3)
    }

    static func toAffine(_ point: Jacobian) -> Point? {
        if point.isInfinity { return nil }
        let zInverse = inverse(point.z)
        let zInverseSquared = sqrModP(zInverse)
        let x = mulModP(point.x, zInverseSquared)
        let y = mulModP(point.y, mulModP(zInverseSquared, zInverse))
        return Point(x: x, y: y)
    }

    /// k·G — the only multiplication this app performs.
    public static func multiplyGenerator(_ scalar: UInt256) -> Point? {
        if scalar.isZero || !(scalar < n) { return nil }
        var accumulator = Jacobian.infinity
        var addend = Jacobian(x: gx, y: gy, z: UInt256(1))
        for bit in 0..<256 {
            if scalar.bit(bit) { accumulator = add(accumulator, addend) }
            addend = double(addend)
        }
        return toAffine(accumulator)
    }

    // MARK: serialisation

    public static func compressed(_ point: Point) -> Data {
        var out = Data([point.y.isOdd ? 0x03 : 0x02])
        out.append(point.x.data)
        return out
    }

    public static func uncompressed(_ point: Point) -> Data {
        var out = Data([0x04])
        out.append(point.x.data)
        out.append(point.y.data)
        return out
    }

    public static func xonly(_ point: Point) -> Data { point.x.data }

    public static func parseCompressed(_ data: Data) -> Point? {
        guard data.count == 33, let prefix = data.first, prefix == 2 || prefix == 3 else { return nil }
        guard let point = liftX(UInt256(data.dropFirst())) else { return nil }
        let wantsOdd = prefix == 3
        if point.y.isOdd != wantsOdd { return Point(x: point.x, y: subModP(p, point.y)) }
        return point
    }

    /// BIP-86 key-path taproot: tweak the even-y lift of the x-only internal key.
    public static func taprootOutputKey(internalKey: Point) -> Point? {
        let internalX = xonly(internalKey)
        guard let evenPoint = liftX(UInt256(internalX)) else { return nil }
        let tweak = TaggedHash.tapTweak(internalX)
        let tweakScalar = UInt256(tweak)
        guard tweakScalar < n, let tweakPoint = multiplyGenerator(tweakScalar) else { return nil }
        let sum = add(Jacobian(x: evenPoint.x, y: evenPoint.y, z: UInt256(1)),
                      Jacobian(x: tweakPoint.x, y: tweakPoint.y, z: UInt256(1)))
        return toAffine(sum)
    }
}

/// BIP-340 tagged hashes.
public enum TaggedHash {
    public static func compute(_ tag: String, _ message: Data) -> Data {
        let tagHash = SHA256.hash(Data(tag.utf8))
        return SHA256.hash(tagHash + tagHash + message)
    }

    public static func tapTweak(_ internalKey: Data) -> Data { compute("TapTweak", internalKey) }
}
