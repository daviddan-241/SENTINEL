import Foundation
/// Cryptographically secure random bytes — the only randomness the app ever uses.
public enum RandomBytes {
    public static func bytes(_ count: Int) -> Data {
        var out = Data(count: count)
        let status = out.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            #if canImport(Security)
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
            #else
            // swift-crypto / Swift System on Linux expose getrandom(2) through SystemRandomNumberGenerator.
            var generator = SystemRandomNumberGenerator()
            let raw = UnsafeMutableRawBufferPointer(start: base, count: count)
            var index = 0
            while index < count {
                let value = generator.next()
                withUnsafeBytes(of: value.bigEndian) { word in
                    let take = Swift.min(8, count - index)
                    raw[index..<(index + take)].copyBytes(from: word.prefix(take))
                }
                index += 8
            }
            return 0
            #endif
        }
        precondition(status == 0, "the system random number generator failed")
        return out
    }
}
