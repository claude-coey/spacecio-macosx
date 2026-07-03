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

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: 0xFFFF_FFFF) // 255.255.255.255

        var ok = true
        for i in 0..<max(1, repeats) {
            let sent: Int = data.withUnsafeBytes { buf in
                withUnsafePointer(to: addr) { aptr in
                    aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(fd, buf.baseAddress, data.count, 0, sa,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent != data.count { ok = false }
            if i < repeats - 1 { usleep(gapMs * 1000) }
        }
        return ok
    }
}
