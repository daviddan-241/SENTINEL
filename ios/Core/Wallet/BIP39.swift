import Foundation

/// BIP-39 mnemonics: validation against the official word list and seed derivation.
public enum BIP39 {
    public enum ValidationResult: Equatable {
        case valid
        case empty
        case wrongWordCount(Int)
        case unknownWords([String])
        case checksumFailed

        public var isValid: Bool { self == .valid }

        public var explanation: String {
            switch self {
            case .valid: return "Every word is in the BIP-39 list and the checksum matches."
            case .empty: return "No words entered."
            case .wrongWordCount(let count):
                return "A recovery phrase has 12, 15, 18, 21 or 24 words — this one has \(count)."
            case .unknownWords(let words):
                return "Not in the 2,048-word list: " + words.prefix(4).joined(separator: ", ")
            case .checksumFailed:
                return "All words are real, but the checksum fails — usually two words swapped or one written down wrong."
            }
        }
    }

    public static let allowedWordCounts = [12, 15, 18, 21, 24]

    /// Splits free text into candidate words: whitespace, commas, semicolons and numbered
    /// lists ("1. abandon") are all tolerated.
    public static func normalise(_ phrase: String) -> [String] {
        phrase.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789'").inverted)
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
    }

    public static func validate(_ phrase: String) -> ValidationResult {
        let words = normalise(phrase)
        if words.isEmpty { return .empty }
        guard allowedWordCounts.contains(words.count) else { return .wrongWordCount(words.count) }

        var indices = [Int]()
        indices.reserveCapacity(words.count)
        var unknown = [String]()
        for word in words {
            if let index = BIP39Wordlist.indexOf[word] { indices.append(index) } else { unknown.append(word) }
        }
        if !unknown.isEmpty { return .unknownWords(unknown) }

        // entropy || checksum, packed into 11-bit groups
        var bits = ""
        bits.reserveCapacity(indices.count * 11)
        for index in indices {
            bits += String(index, radix: 2).leftPadded(to: 11, with: "0")
        }
        let checksumLength = bits.count / 33          // CS = ENT / 32, i.e. one bit per 33
        let entropyBits = bits.count - checksumLength
        let entropy = String(bits.prefix(entropyBits))
        let checksum = String(bits.suffix(checksumLength))

        guard let entropyBytes = Data(binaryString: entropy) else { return .checksumFailed }
        // The checksum is the leading CS bits of SHA-256(entropy), compared bit for bit.
        let digest = SHA256.hash(entropyBytes)
        var expected = ""
        expected.reserveCapacity(checksumLength)
        for bit in 0..<checksumLength {
            let byte = digest[bit / 8]
            let set = (byte >> UInt8(7 - bit % 8)) & 1
            expected.append(set == 1 ? "1" : "0")
        }
        return expected == checksum ? .valid : .checksumFailed
    }

    /// PBKDF2-HMAC-SHA512, 2,048 rounds — the standard seed stretch.
    public static func seed(phrase: String, passphrase: String = "") -> Data {
        let normalisedPhrase = normalise(phrase).joined(separator: " ")
        let salt = Data(("mnemonic" + passphrase).utf8)
        return PBKDF2.derive(algorithm: .sha512,
                             password: Data(normalisedPhrase.utf8),
                             salt: salt,
                             iterations: 2048,
                             keyLength: 64)
    }

    /// Suggests the closest list words for a misspelled input (used by the import screen).
    public static func suggestions(for word: String, limit: Int = 3) -> [String] {
        let target = word.lowercased()
        guard !target.isEmpty else { return [] }
        var scored = [(String, Int)]()
        for candidate in BIP39Wordlist.words {
            let distance = levenshtein(target, candidate)
            let prefixBonus = (candidate.hasPrefix(String(target.prefix(2))) ? -1 : 0)
            scored.append((candidate, distance + prefixBonus))
        }
        scored.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
        return scored.prefix(limit).map(\.0)
    }

    /// Words on the same 11-bit index neighbourhood — handy when a word looks unfamiliar.
    public static func neighbours(of index: Int, span: Int = 1) -> [String] {
        let lower = max(0, index - span), upper = min(BIP39Wordlist.count - 1, index + span)
        return (lower...upper).map { BIP39Wordlist.words[$0] }
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[y.count]
    }
}

extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        count >= length ? self : String(repeating: String(character), count: length - count) + self
    }
}

extension Data {
    /// Builds bytes from a string of "0"/"1" characters.
    init?(binaryString: String) {
        guard binaryString.count % 8 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = binaryString.startIndex
        while index < binaryString.endIndex {
            let next = binaryString.index(index, offsetBy: 8)
            guard let byte = UInt8(binaryString[index..<next], radix: 2) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
