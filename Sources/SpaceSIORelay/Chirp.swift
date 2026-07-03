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
    /// Chirp at most this many bytes — the audible signature, not the packet.
    static let maxChirpBytes = 160

    // ── Sonification model: EXACT port of the website's src/lib/sonify.ts ──
    // Minor-pentatonic scale over 4 octaves from A2; pitch is a pure function
    // of the byte value; timbre reflects the packet field. Same packet →
    // same sound, on the site and on the station.
    private static let scaleSteps = [0, 3, 5, 7, 10]
    private static let octaves = 4
    private static let baseMidi = 45.0 // A2

    /// sonify.ts `byteToFreq` — byte (0…255) → Hz on the pentatonic grid.
    static func byteToFreq(_ v: UInt8) -> Double {
        let notes = scaleSteps.count * octaves
        let idx = min(notes - 1, Int(Double(v) / 256.0 * Double(notes)))
        let octave = idx / scaleSteps.count
        let midi = baseMidi + Double(octave * 12 + scaleSteps[idx % scaleSteps.count])
        return 440.0 * pow(2.0, (midi - 69.0) / 12.0)
    }

    /// sonify.ts `noteDurFor` — aim for ~6s total, clamped per note.
    static func noteDur(forCount n: Int) -> Double {
        guard n > 0 else { return 0.06 }
        return max(0.02, min(0.09, 6.0 / Double(n)))
    }

    /// Timbre codes (sonify.ts `segTimbre`): 0 triangle (framing default),
    /// 1 sawtooth (message body), 2 square (thumbnail), 3 sine (checksum).
    enum Timbre: Int { case triangle = 0, sawtooth = 1, square = 2, sine = 3 }

    /// Pure math — safe to call from anywhere, never touches AVFoundation.
    static func expectedDuration(_ byteCount: Int) -> Double {
        let n = max(0, min(byteCount, maxChirpBytes))
        return Double(n) * noteDur(forCount: n)
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

    /// Schedules the chirp asynchronously. `timbres` carries one Timbre raw
    /// value per byte (defaults to triangle when omitted/short). `report` is
    /// invoked from the audio queue once (or never, if the HAL is truly
    /// wedged — which is exactly why the station loop must not wait on it).
    func play(
        _ allBytes: [UInt8],
        timbres allTimbres: [Int] = [],
        report: @escaping @Sendable (Bool) -> Void
    ) {
        let bytes = Array(allBytes.prefix(Self.maxChirpBytes))
        let timbres = Array(allTimbres.prefix(Self.maxChirpBytes))
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

            let noteDur = Self.noteDur(forCount: bytes.count)
            let framesPerNote = max(1, Int(sampleRate * noteDur))
            let totalFrames = AVAudioFrameCount(framesPerNote * bytes.count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
                  let channel = buffer.floatChannelData?[0]
            else { return }
            buffer.frameLength = totalFrames

            // Same envelope as the website: linear attack over the first 25%
            // of the note, exponential decay to near-zero by 98%.
            let attackEnd = 0.25
            let peak = 0.3
            var idx = 0
            for (n, byte) in bytes.enumerated() {
                let freq = Self.byteToFreq(byte)
                let timbre = Timbre(rawValue: n < timbres.count ? timbres[n] : 0) ?? .triangle
                var phase = 0.0
                let step = freq / sampleRate
                for i in 0..<framesPerNote {
                    let x = Double(i) / Double(framesPerNote) // 0…1 through the note
                    let env: Double = x < attackEnd
                        ? x / attackEnd
                        : pow(0.001, (x - attackEnd) / (0.98 - attackEnd))
                    let frac = phase - phase.rounded(.down)
                    let sample: Double
                    switch timbre {
                    case .sine: sample = sin(2.0 * .pi * frac)
                    case .square: sample = frac < 0.5 ? 0.7 : -0.7 // softened square
                    case .sawtooth: sample = (2.0 * frac - 1.0) * 0.8
                    case .triangle: sample = 2.0 * abs(2.0 * frac - 1.0) - 1.0
                    }
                    channel[idx] = Float(sample * peak * env)
                    phase += step
                    idx += 1
                }
            }

            player.scheduleBuffer(buffer, at: nil)
            if !player.isPlaying { player.play() }
            ok = true
        }
    }
}
