import AVFoundation

enum RecorderError: LocalizedError {
    case noInput
    var errorDescription: String? { "Микрофон не найден" }
}

/// Records the microphone as 16 kHz mono Float samples. Memory only, nothing on disk.
final class Recorder {
    static let sampleRate = 16_000

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(Recorder.sampleRate),
        channels: 1,
        interleaved: false
    )!
    private let lock = NSLock()
    private var samples: [Float] = []
    private var isRunning = false

    /// Per-band voice levels 0…1 (low first) and the overall level 0…1, per buffer, off the audio thread.
    var onFrame: (([Float], Float) -> Void)?
    private let spectrum = Spectrum()
    private let analysisQueue = DispatchQueue(label: "shepot.spectrum", qos: .userInteractive)

    func start() throws {
        guard !isRunning else { return }
        lock.withLock { samples.removeAll() }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else { throw RecorderError.noInput }

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, using: converter)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    /// Stops recording and hands over the captured samples.
    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        return lock.withLock {
            defer { samples.removeAll() }
            return samples
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0] else { return }

        let chunk = UnsafeBufferPointer(start: channel, count: Int(out.frameLength))
        lock.withLock { samples.append(contentsOf: chunk) }
        // The audio thread only copies; the analysis runs on its own queue.
        let copy = Array(chunk)
        analysisQueue.async { [weak self] in
            guard let self else { return }
            // Large buffers get several overlapping looks, keeping the loudest of each band.
            var bands = [Float](repeating: 0, count: Spectrum.bandCount)
            var start = 0
            repeat {
                let end = min(start + 256, copy.count)
                let part = copy[start..<end].withUnsafeBufferPointer { self.spectrum.process($0) }
                for i in bands.indices { bands[i] = max(bands[i], part[i]) }
                start = end
            } while start < copy.count
            self.onFrame?(bands, Self.level(of: copy))
        }
    }

    /// RMS mapped from -45…-10 dB to 0…1, with a small gate for room noise.
    private static func level(of chunk: [Float]) -> Float {
        guard !chunk.isEmpty else { return 0 }
        let meanSquare = chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)
        let level = min(max((10 * log10(max(meanSquare, 1e-10)) + 45) / 35, 0), 1)
        return max(0, (level - 0.1) / 0.9)
    }
}
