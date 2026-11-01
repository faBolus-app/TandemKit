@testable import TandemAuth

/// A seeded byte stream (SplitMix64) for EC-JPAKE contexts, so a handshake with a short ZKP
/// scalar is the same on every run instead of turning up 1 time in 256.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A closure for `EcJpakeContext(role:secret:randomBytes:)`. The stream lives in the closure.
    static func bytes(seed: UInt64) -> (Int) -> [UInt8] {
        var rng = SeededRandom(seed: seed)
        var pending: [UInt8] = []
        return { count in
            while pending.count < count {
                withUnsafeBytes(of: rng.next().littleEndian) { pending.append(contentsOf: $0) }
            }
            defer { pending.removeFirst(count) }
            return Array(pending.prefix(count))
        }
    }
}

/// How an mbedTLS pump splits its round one into the 1a/1b cargos: one KeyKP each, at the
/// minimal length mbedTLS wrote. (A midpoint split would cut a KeyKP whenever one scalar is short.)
func pumpRoundOneHalves(_ round1: [UInt8]) throws -> ([UInt8], [UInt8]) {
    let first = try JpakeRound.keyKPs(round1, count: 1)[0]
    let split = 3 + first.x.count + first.v.count + first.r.count
    return (Array(round1[0..<split]), Array(round1[split...]))
}
