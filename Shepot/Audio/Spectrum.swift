import Accelerate
import Foundation

/// Live voice spectrum: a short window of the latest samples split into log-spaced bands.
/// Plain DFT over the voice range only (~100 bins × 512 samples), cheap enough per audio buffer.
final class Spectrum {
    static let bandCount = 6
    private static let size = 512 // 32 ms at 16 kHz
    private static let edges: [Float] = [90, 180, 320, 560, 1000, 1800, 3400] // Hz, band edges

    private let window: [Float]
    private let cosTable: [[Float]]
    private let sinTable: [[Float]]
    private let bins: [Int]           // first bin of each band, plus one past the last
    private let norm: Float
    private var ring = [Float](repeating: 0, count: Spectrum.size)

    init() {
        let n = Self.size
        window = (0..<n).map { 0.5 - 0.5 * cos(2 * .pi * Float($0) / Float(n - 1)) } // Hann
        norm = 2 / window.reduce(0, +)
        let binWidth = 16_000 / Float(n)
        bins = Self.edges.map { Int(($0 / binWidth).rounded()) }
        let range = bins[0]..<bins[Self.bandCount]
        var c = [[Float]](repeating: [], count: range.upperBound)
        var s = c
        for k in range {
            c[k] = (0..<n).map { cos(2 * .pi * Float(k * $0) / Float(n)) }
            s[k] = (0..<n).map { -sin(2 * .pi * Float(k * $0) / Float(n)) }
        }
        cosTable = c
        sinTable = s
    }

    /// Feeds new samples; returns per-band levels 0…1 (low band first).
    func process(_ chunk: UnsafeBufferPointer<Float>) -> [Float] {
        let n = Self.size
        if chunk.count >= n {
            ring = Array(chunk.suffix(n))
        } else {
            ring.removeFirst(chunk.count)
            ring.append(contentsOf: chunk)
        }
        var windowed = [Float](repeating: 0, count: n)
        vDSP.multiply(ring, window, result: &windowed)

        return (0..<Self.bandCount).map { band in
            var peak: Float = 0
            for k in bins[band]..<bins[band + 1] {
                var re: Float = 0, im: Float = 0
                vDSP_dotpr(windowed, 1, cosTable[k], 1, &re, vDSP_Length(n))
                vDSP_dotpr(windowed, 1, sinTable[k], 1, &im, vDSP_Length(n))
                peak = max(peak, (re * re + im * im).squareRoot() * norm)
            }
            // -52…-20 dB → 0…1, with a small gate so room noise leaves the bars still;
            // voices are weaker in the upper bands, so lift those a little.
            let db = 20 * log10(max(peak, 1e-7)) + 1.5 * Float(band)
            let level = min(max((db + 52) / 32, 0), 1)
            return max(0, (level - 0.12) / 0.88)
        }
    }
}
