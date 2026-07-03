import Foundation

/// The station's control loop: poll the feed, put the packet on the air
/// (UDP broadcast + optional chirp), then send back a signed, located
/// confirmation.
@MainActor
final class RelayEngine: ObservableObject {
    enum Phase: Equatable {
        case offline, listening, receiving, broadcasting, confirming, confirmed
    }

    @Published private(set) var phase: Phase = .offline
    @Published private(set) var onAir = false
    @Published private(set) var current: Transmission?
    @Published private(set) var lastConfirmation: Confirmation?
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var confirmedCount = 0

    // Live on-air state for the packet visualization + sonification playhead.
    // The bytes exist ONLY while the packet is on the air — they are destroyed
    // (cleared) the moment the broadcast cycle ends. This station retains
    // nothing: pulling the signal down over WiFi IS the transmission, and the
    // playback is one-time by design.
    @Published private(set) var onAirBytes: [UInt8] = []
    @Published private(set) var broadcastStartedAt: Date?
    @Published private(set) var chirpDuration: Double = 0

    // Station stats — this session + persisted lifetime totals.
    @Published private(set) var pollCount = 0
    @Published private(set) var sessionBytes = 0
    @Published private(set) var sessionStartedAt: Date?
    @Published private(set) var lifetimeRelayed: Int
    @Published private(set) var lifetimeBytes: Int

    private static let lifetimeRelayedKey = "station_lifetime_relayed"
    private static let lifetimeBytesKey = "station_lifetime_bytes"

    let station: Station
    let locationProvider = LocationProvider()
    private let signer = Signer.load()
    private let chirp = Chirp()
    private var loopTask: Task<Void, Never>?

    /// Base64 raw Ed25519 public key — the station's verifiable identity.
    var stationPublicKey: String { signer.publicKeyBase64 }

    init(station: Station) {
        self.station = station
        _lifetimeRelayed = Published(
            initialValue: UserDefaults.standard.integer(forKey: Self.lifetimeRelayedKey))
        _lifetimeBytes = Published(
            initialValue: UserDefaults.standard.integer(forKey: Self.lifetimeBytesKey))
    }

    func setOnAir(_ on: Bool) {
        guard on != onAir else { return }
        onAir = on
        if on {
            if station.locationMode == .automatic {
                locationProvider.request()
            }
            phase = .listening
            sessionStartedAt = Date()
            pollCount = 0
            sessionBytes = 0
            chirp.prewarm() // start the audio engine off the critical path
            appendLog("Station online — listening for queued signals.", .info)
            loopTask = Task { [weak self] in await self?.runLoop() }
        } else {
            loopTask?.cancel()
            loopTask = nil
            phase = .offline
            sessionStartedAt = nil
            destroyPacket(afterSuccess: false)
            appendLog("Station offline.", .info)
        }
    }

    private func runLoop() async {
        while !Task.isCancelled && onAir {
            // Watchdog: no single broadcast cycle may hold the station longer
            // than 90s. Cancellation unwedges every await point (sleep, HTTP);
            // the cycle's own error handling logs it and destroys the packet.
            let cycleTask = Task { [weak self] in await self?.cycle() }
            let watchdog = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.appendLog("Watchdog: cycle exceeded 90s — abandoning this broadcast.", .error)
                }
                cycleTask.cancel()
            }
            _ = await cycleTask.value
            watchdog.cancel()
            try? await Task.sleep(nanoseconds: 6_000_000_000)
        }
    }

    /// Short audible test (three notes) so a member can verify the audio path
    /// without waiting for a real signal. Fired from the mute toggle.
    func testChirp() {
        chirp.play([40, 120, 220]) { [weak self] ok in
            Task { @MainActor in
                self?.appendLog(
                    ok
                        ? "Test chirp played."
                        : "Test chirp failed — audio engine not running (check output device / volume).",
                    ok ? .info : .error
                )
            }
        }
    }

    private func cycle() async {
        guard let api = station.api else {
            appendLog("Server URL or API key looks invalid — check Settings.", .error)
            setOnAir(false)
            return
        }
        if case .confirmed = phase {} else { phase = .receiving }

        do {
            let feed = try await api.next(rig: station.rigName)
            pollCount += 1
            guard let t = feed.transmission else {
                if phase != .confirmed { phase = .listening }
                return
            }

            current = t
            lastConfirmation = nil
            phase = .broadcasting

            // THE PULL IS THE TRANSMISSION: the packet just travelled to this
            // station over the WiFi radio — that download IS the RF event.
            // (No UDP re-broadcast, so no Local Network permission is needed
            // and no raw-socket call can ever wedge the station.)
            let packetData = t.packet.flatMap { Data(base64Encoded: $0) }
                ?? Data((t.title ?? t.id).utf8)
            let bytes = [UInt8](packetData)
            // Live for the visualization + sonification playhead — and ONLY
            // for the on-air moment; destroyPacket() wipes it on every exit.
            onAirBytes = bytes
            broadcastStartedAt = Date()
            appendLog(
                "Received \"\(t.title ?? t.slug ?? "signal")\" — \(bytes.count) bytes over the WiFi radio. On air.",
                .info
            )

            // Fire-and-forget: the loop only does the MATH for the chirp's
            // duration — all actual audio happens on Chirp's own queue, so a
            // wedged CoreAudio device can never stall the station again.
            var chirpSeconds = 0.0
            if station.chirpEnabled {
                chirpSeconds = Chirp.expectedDuration(bytes.count)
                chirp.play(bytes, timbres: Self.timbreCodes(for: bytes)) { [weak self] ok in
                    Task { @MainActor in
                        self?.appendLog(
                            ok ? "Chirp playing." : "Chirp couldn't start (audio engine unavailable) — on air silently.",
                            ok ? .info : .error
                        )
                    }
                }
            }
            chirpDuration = chirpSeconds
            // Hold the on-air moment for at least the chirp's duration, but
            // never longer than a few seconds — a photo packet is ~2 KB and
            // would otherwise hold the station for over a minute.
            try? await Task.sleep(nanoseconds: UInt64(min(max(chirpSeconds, 1.2), 6.0) * 1_000_000_000))

            phase = .confirming
            appendLog("Signing confirmation…", .info)
            // The first signal often beats the first GPS fix (the cause of
            // early "location not shared" confirmations while the dashboard
            // showed coordinates moments later). Give the fix a bounded
            // moment to land before signing — never more than 5s.
            var locWait = 0.0
            while station.locationMode == .automatic,
                  station.effectiveCoordinate(from: locationProvider) == nil,
                  locWait < 5.0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                locWait += 0.5
            }
            let coord = station.effectiveCoordinate(from: locationProvider)
            // Coarse by design (~5 mi): one decimal place, matching
            // Station.effectiveCoordinate's rounding.
            let latStr = coord.map { String(format: "%.1f", $0.lat) } ?? ""
            let lonStr = coord.map { String(format: "%.1f", $0.lon) } ?? ""
            let payload = Signer.confirmationPayload(
                id: t.id, payloadHash: t.payload_hash, at: Date(), lat: latStr, lon: lonStr
            )
            guard let signature = signer.sign(payload) else {
                appendLog("Signing failed — confirmation not sent.", .error)
                phase = .listening
                destroyPacket(afterSuccess: false)
                return
            }

            let res = try await api.complete(
                id: t.id, signedPayload: payload,
                signature: signature, pubkey: signer.publicKeyBase64
            )

            if res.ok == true {
                confirmedCount += 1
                sessionBytes += bytes.count
                lifetimeRelayed += 1
                lifetimeBytes += bytes.count
                persistLifetime()
                lastConfirmation = Confirmation(
                    title: t.title ?? "Untitled signal",
                    permalink: res.permalink ?? t.permalink,
                    certificateURL: res.certificate_url,
                    lat: coord?.lat,
                    lon: coord?.lon,
                    signaturePrefix: String(signature.prefix(16)),
                    verified: res.signature_verified ?? false,
                    date: Date()
                )
                appendLog("On air ✓ — signed confirmation delivered.", .success)
                phase = .confirmed
                destroyPacket(afterSuccess: true)
            } else {
                appendLog("Confirmation rejected: \(res.error ?? "unknown error").", .error)
                phase = .listening
                destroyPacket(afterSuccess: false)
            }
        } catch {
            appendLog(error.localizedDescription, .error)
            phase = .listening
            destroyPacket(afterSuccess: false)
        }
    }

    /// The relay retains NOTHING: the pulled-down packet exists only for the
    /// on-air moment. Called on every exit path of a broadcast cycle.
    private func destroyPacket(afterSuccess: Bool) {
        let had = !onAirBytes.isEmpty
        onAirBytes = []
        broadcastStartedAt = nil
        chirpDuration = 0
        current = nil
        if had {
            appendLog(
                afterSuccess
                    ? "Packet destroyed after broadcast — nothing retained on this station."
                    : "Packet bytes cleared — nothing retained on this station.",
                .info
            )
        }
    }

    private func persistLifetime() {
        UserDefaults.standard.set(lifetimeRelayed, forKey: Self.lifetimeRelayedKey)
        UserDefaults.standard.set(lifetimeBytes, forKey: Self.lifetimeBytesKey)
    }

    /// Per-byte timbre codes for the sonification — same field→instrument
    /// mapping as the website (sonify.ts segTimbre): body=sawtooth,
    /// thumb=square, checksum=sine, framing=triangle.
    nonisolated static func timbreCodes(for bytes: [UInt8]) -> [Int] {
        var codes = [Int](repeating: Chirp.Timbre.triangle.rawValue, count: bytes.count)
        guard let segments = parsePacketSegments(bytes) else { return codes }
        for seg in segments {
            let code: Chirp.Timbre
            switch seg.field {
            case .body: code = .sawtooth
            case .thumb: code = .square
            case .checksum: code = .sine
            default: code = .triangle
            }
            if code != .triangle {
                for i in seg.range { codes[i] = code.rawValue }
            }
        }
        return codes
    }

    private func appendLog(_ text: String, _ kind: LogEntry.Kind) {
        log.insert(LogEntry(date: Date(), text: text, kind: kind), at: 0)
        if log.count > 60 { log.removeLast(log.count - 60) }
    }
}
