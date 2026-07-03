import Darwin
import Foundation

/// Puts the proof packet on the air: the bytes are sent as UDP broadcast
/// datagrams on the local network, so they physically leave the Mac's WiFi
/// radio as RF. Repeated a few times for redundancy.
enum Broadcaster {
    static let port: UInt16 = 47727 // "SIO" relay port

    @discardableResult
    static func broadcast(_ data: Data, repeats: Int = 3, gapMs: UInt32 = 220) -> Bool {
        guard !data.isEmpty else { return false }
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        // HARD send timeout at the socket level. On recent macOS, sendto to
        // the broadcast address can block indefinitely while the Local
        // Network permission is undecided/denied — this guarantees each send
        // returns within 2s no matter what, so the station loop can never
        // wedge here.
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: 0xFFFF_FFFF) // 255.255.255.255

        // A single UDP datagram tops out near 64 KB (and anything over the
        // ~1500-byte MTU fragments), so large proof packets (photos ≈ 2 KB+)
        // are sent as a series of MTU-safe chunks.
        let chunkSize = 1400
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }

        var ok = true
        for i in 0..<max(1, repeats) {
            for chunk in chunks {
                let sent: Int = chunk.withUnsafeBytes { buf in
                    withUnsafePointer(to: addr) { aptr in
                        aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            sendto(fd, buf.baseAddress, chunk.count, 0, sa,
                                   socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                if sent != chunk.count { ok = false }
                if chunks.count > 1 { usleep(4000) } // 4 ms between chunks
            }
            if i < repeats - 1 { usleep(gapMs * 1000) }
        }
        return ok
    }
}
