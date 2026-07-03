import AVFoundation

/// Sonifies the proof packet: each byte becomes a short tone (440–2100 Hz),
/// so the broadcast is audible in the room. Optional — toggled in Settings.
final class Chirp {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var ready = false

    private func prepare() {
        guard !ready else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0.6
        do {
            try engine.start()
            ready = true
        } catch {
            ready = false
        }
    }

    /// At 0.03 s per byte a ~2 KB photo packet would chirp for over a minute
    /// (and allocate a huge buffer) — chirp at most this many bytes (~4.8 s).
    private static let maxChirpBytes = 160

    /// Plays the chirp; returns its duration in seconds (0 if audio failed).
    /// Long packets are truncated to `maxChirpBytes` — the chirp is an audible
    /// signature of the packet, not the transmission itself (the full bytes go
    /// out over UDP regardless).
    @discardableResult
    func play(_ allBytes: [UInt8]) -> Double {
        let bytes = Array(allBytes.prefix(Self.maxChirpBytes))
        prepare()
        let sampleRate = 44_100.0
        let toneDuration = 0.03
        guard ready, !bytes.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return 0 }

        let framesPerTone = Int(sampleRate * toneDuration)
        let totalFrames = AVAudioFrameCount(framesPerTone * bytes.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
              let channel = buffer.floatChannelData?[0]
        else { return 0 }
        buffer.frameLength = totalFrames

        var idx = 0
        let attack = Int(sampleRate * 0.004)
        for byte in bytes {
            let freq = 440.0 + Double(byte) * 6.5
            for i in 0..<framesPerTone {
                let t = Double(i) / sampleRate
                let edge = min(i, framesPerTone - 1 - i)
                let env = min(1.0, Double(edge) / Double(max(1, attack)))
                channel[idx] = Float(sin(2.0 * .pi * freq * t) * 0.28 * env)
                idx += 1
            }
        }

        player.scheduleBuffer(buffer, at: nil)
        if !player.isPlaying { player.play() }
        return toneDuration * Double(bytes.count)
    }
}
