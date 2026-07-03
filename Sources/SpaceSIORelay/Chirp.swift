import AVFoundation

/// Sonifies the proof packet: each byte becomes a short tone (440–2100 Hz),
/// so the broadcast is audible in the room. Optional — toggled in Settings.
///
/// EVERY AVFoundation call lives on a private audio queue. CoreAudio (HAL)
/// can stall indefinitely on a misbehaving device, and audio calls made from
/// the station loop repeatedly wedged the whole relay (v1.0–v1.3). The loop
/// now only does pure math (`expectedDuration`) and fire-and-forget playback:
/// if audio hangs, the audio thread hangs alone and the station keeps
/// relaying — silently, with an honest log line.
final class Chirp {
    static let toneDuration = 0.03
    /// At 0.03 s per byte a ~2 KB photo packet would chirp for over a minute
    /// (and allocate a huge buffer) — chirp at most this many bytes (~4.8 s).
    static let maxChirpBytes = 160

    /// Pure math — safe to call from anywhere, never touches AVFoundation.
    static func expectedDuration(_ byteCount: Int) -> Double {
        Double(max(0, min(byteCount, maxChirpBytes))) * toneDuration
    }

    private let audioQueue = DispatchQueue(label: "com.spacesio.relay.chirp", qos: .userInitiated)
    // Touched ONLY on audioQueue (created lazily there — even AVAudioEngine's
    // init talks to the HAL and must stay off the main thread).
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    /// The ONE format used for both the player connection and every buffer.
    /// Connecting with `format: nil` adopts the output device's format (often
    /// 48 kHz stereo) while our buffers are 44.1 kHz mono — that mismatch made
    /// AVAudioPlayerNode.scheduleBuffer throw an NSException (v1.4 crash) and
    /// is the likely reason the chirp was never audible. Using the same
    /// format object for both makes the engine insert converters for the
    /// device leg, guaranteed match on ours.
    private var format: AVAudioFormat?
    private var ready = false
    private var startAttempted = false

    /// Kick off engine startup on the audio queue. Fire-and-forget.
    func prewarm() {
        audioQueue.async { [weak self] in
            self?.startEngineIfNeeded()
        }
    }

    /// Must be called on audioQueue.
    private func startEngineIfNeeded() {
        guard !startAttempted else { return }
        startAttempted = true
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            self.ready = false
            return
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.8
        do {
            try engine.start()
            self.engine = engine
            self.player = player
            self.format = fmt
            self.ready = true
        } catch {
            self.ready = false
        }
    }

    /// Schedules the chirp asynchronously. `report(started)` is invoked from
    /// the audio queue once (or never, if the HAL is truly wedged — which is
    /// exactly why the station loop must not wait on it).
    func play(_ allBytes: [UInt8], report: @escaping @Sendable (Bool) -> Void) {
        let bytes = Array(allBytes.prefix(Self.maxChirpBytes))
        audioQueue.async { [weak self] in
            var ok = false
            defer { report(ok) }
            guard let self else { return }
            self.startEngineIfNeeded()
            let sampleRate = 44_100.0
            guard self.ready, let engine = self.engine, let player = self.player,
                  let format = self.format, !bytes.isEmpty
            else { return }
            // scheduleBuffer/play throw NSExceptions (uncatchable from Swift)
            // if the engine isn't actually running — never call them blind.
            if !engine.isRunning {
                guard (try? engine.start()) != nil, engine.isRunning else { return }
            }

            let framesPerTone = Int(sampleRate * Self.toneDuration)
            let totalFrames = AVAudioFrameCount(framesPerTone * bytes.count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
                  let channel = buffer.floatChannelData?[0]
            else { return }
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
            ok = true
        }
    }
}
