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

    let station: Station
    let locationProvider = LocationProvider()
    private let signer = Signer.load()
    private let chirp = Chirp()
    private var loopTask: Task<Void, Never>?

    /// Base64 raw Ed25519 public key — the station's verifiable identity.
    var stationPublicKey: String { signer.publicKeyBase64 }

    init(station: Station) {
        self.station = station
    }

    func setOnAir(_ on: Bool) {
        guard on != onAir else { return }
        onAir = on
        if on {
            if station.locationMode == .automatic {
                locationProvider.request()
            }
            phase = .listening
            appendLog("Station online — listening for queued signals.", .info)
            loopTask = Task { [weak self] in await self?.runLoop() }
        } else {
            loopTask?.cancel()
            loopTask = nil
            phase = .offline
            current = nil
            appendLog("Station offline.", .info)
        }
    }

    private func runLoop() async {
        while !Task.isCancelled && onAir {
            await cycle()
            try? await Task.sleep(nanoseconds: 6_000_000_000)
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
            guard let t = feed.transmission else {
                if phase != .confirmed { phase = .listening }
                return
            }

            current = t
            lastConfirmation = nil
            appendLog("Received \"\(t.title ?? t.slug ?? "signal")\" — going on air.", .info)
            phase = .broadcasting

            // The proof packet is what physically goes out over the WiFi radio.
            let packetData = t.packet.flatMap { Data(base64Encoded: $0) }
                ?? Data((t.title ?? t.id).utf8)
            let bytes = [UInt8](packetData)

            // Bounded: the UDP send can block indefinitely on macOS if the
            // Local Network permission is pending/denied — never let it wedge
            // the whole station loop (the claimed signal would stay "on air"
            // forever and polling would stop). If the send doesn't finish in
            // time we still proceed to the signed confirmation.
            let sent = await Self.withDeadline(seconds: 15) {
                Broadcaster.broadcast(packetData)
            } ?? false
            if !sent {
                appendLog(
                    "UDP broadcast didn't complete (check Local Network permission in System Settings → Privacy) — continuing to confirmation.",
                    .error
                )
            }

            var chirpSeconds = 0.0
            if station.chirpEnabled {
                chirpSeconds = chirp.play(bytes)
            }
            // Hold the on-air moment for at least the chirp's duration, but
            // never longer than a few seconds — a photo packet is ~2 KB and
            // would otherwise hold the station for over a minute.
            try? await Task.sleep(nanoseconds: UInt64(min(max(chirpSeconds, 1.2), 6.0) * 1_000_000_000))

            phase = .confirming
            let coord = station.effectiveCoordinate(from: locationProvider)
            let latStr = coord.map { String(format: "%.5f", $0.lat) } ?? ""
            let lonStr = coord.map { String(format: "%.5f", $0.lon) } ?? ""
            let payload = Signer.confirmationPayload(
                id: t.id, payloadHash: t.payload_hash, at: Date(), lat: latStr, lon: lonStr
            )
            guard let signature = signer.sign(payload) else {
                appendLog("Signing failed — confirmation not sent.", .error)
                phase = .listening
                return
            }

            let res = try await api.complete(
                id: t.id, signedPayload: payload,
                signature: signature, pubkey: signer.publicKeyBase64
            )

            if res.ok == true {
                confirmedCount += 1
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
                appendLog(
                    sent
                        ? "On air ✓ — signed confirmation delivered."
                        : "Confirmation delivered (UDP send reported an issue).",
                    .success
                )
                phase = .confirmed
            } else {
                appendLog("Confirmation rejected: \(res.error ?? "unknown error").", .error)
                phase = .listening
            }
            current = nil
        } catch {
            appendLog(error.localizedDescription, .error)
            current = nil
            phase = .listening
        }
    }

    /// Runs blocking work off the main actor with a deadline. Returns nil if
    /// the deadline passes first (the orphaned work finishes in the background;
    /// the station loop moves on instead of wedging).
    private static func withDeadline<T: Sendable>(
        seconds: Double,
        _ work: @escaping @Sendable () -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask(priority: .userInitiated) { work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func appendLog(_ text: String, _ kind: LogEntry.Kind) {
        log.insert(LogEntry(date: Date(), text: text, kind: kind), at: 0)
        if log.count > 60 { log.removeLast(log.count - 60) }
    }
}
