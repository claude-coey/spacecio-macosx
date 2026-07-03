import SwiftUI

/// Truthful, animated "data blocks" view of the proof packet — the app-side
/// twin of the website's packet anatomy. Every cell is ONE REAL BYTE of the
/// packet on the air, colored by the field it belongs to (same layout + brand
/// palette as the site's packet visualizer), with brightness from the byte's
/// value. While broadcasting, blocks materialize in a sweep with a glowing
/// scan edge; when the broadcast ends the packet is destroyed and the grid
/// vanishes with it.
///
/// Packet layout (MUST stay in sync with src/lib/packet.ts on the server):
///   [0..1]  magic 'SM' · [2] version · [3..8] signal id · [9..12] timestamp
///   [13..28] payload hash (16 B) · [2 B body length][DEFLATE body]
///   [2 B thumb length][JPEG thumb] · [last] XOR checksum
enum PacketField: String {
    case magic = "Magic"
    case version = "Version"
    case id = "Signal ID"
    case timestamp = "Timestamp"
    case hash = "Payload hash"
    case bodyLen = "Msg length"
    case body = "Message (DEFLATE)"
    case thumbLen = "Thumb length"
    case thumb = "Thumbnail (JPEG)"
    case checksum = "Checksum"

    /// Brand palette — same hex values as packet-view.ts COLORS.
    var color: Color {
        switch self {
        case .magic: return Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFF / 255)
        case .version: return Color(red: 0x8F / 255, green: 0x6B / 255, blue: 0xFF / 255)
        case .id: return Color(red: 0x38 / 255, green: 0xDC / 255, blue: 0xF3 / 255)
        case .timestamp: return Color(red: 0x22 / 255, green: 0xD3 / 255, blue: 0xEE / 255)
        case .hash: return Color(red: 0xFF / 255, green: 0x8F / 255, blue: 0x73 / 255)
        case .bodyLen: return Color(red: 0x5F / 255, green: 0x3F / 255, blue: 0xE0 / 255)
        case .body: return Color(red: 0x7C / 255, green: 0x5C / 255, blue: 0xFF / 255)
        case .thumbLen: return Color(red: 0x0E / 255, green: 0xA5 / 255, blue: 0xB7 / 255)
        case .thumb: return Color(red: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255)
        case .checksum: return Color(red: 0xFB / 255, green: 0xBF / 255, blue: 0x24 / 255)
        }
    }
}

struct PacketSegment {
    let field: PacketField
    let range: Range<Int>
    var count: Int { range.count }
}

/// Parse the packet into labeled segments. Returns nil if the bytes don't
/// look like a SpaceSIO packet — callers fall back to an unlabeled grid
/// rather than inventing structure that isn't there.
func parsePacketSegments(_ bytes: [UInt8]) -> [PacketSegment]? {
    let n = bytes.count
    // magic(2)+ver(1)+id(6)+ts(4)+hash(16)+bodyLen(2)+thumbLen(2)+checksum(1)
    guard n >= 34, bytes[0] == 0x53, bytes[1] == 0x4D else { return nil }

    var segs: [PacketSegment] = [
        PacketSegment(field: .magic, range: 0..<2),
        PacketSegment(field: .version, range: 2..<3),
        PacketSegment(field: .id, range: 3..<9),
        PacketSegment(field: .timestamp, range: 9..<13),
        PacketSegment(field: .hash, range: 13..<29),
    ]
    var at = 29
    guard at + 2 <= n else { return nil }
    let bodyLen = Int(bytes[at]) << 8 | Int(bytes[at + 1])
    segs.append(PacketSegment(field: .bodyLen, range: at..<(at + 2)))
    at += 2
    guard at + bodyLen <= n else { return nil }
    if bodyLen > 0 { segs.append(PacketSegment(field: .body, range: at..<(at + bodyLen))) }
    at += bodyLen
    guard at + 2 <= n else { return nil }
    let thumbLen = Int(bytes[at]) << 8 | Int(bytes[at + 1])
    segs.append(PacketSegment(field: .thumbLen, range: at..<(at + 2)))
    at += 2
    guard at + thumbLen + 1 == n else { return nil } // + trailing checksum
    if thumbLen > 0 { segs.append(PacketSegment(field: .thumb, range: at..<(at + thumbLen))) }
    at += thumbLen
    segs.append(PacketSegment(field: .checksum, range: at..<n))
    return segs
}

/// The animated byte grid. `progress` (0…1) sweeps the materialization while
/// broadcasting; pass 1 to show everything settled.
struct PacketBlocksView: View {
    let bytes: [UInt8]
    var progress: Double = 1
    /// Timebase from an enclosing TimelineView for the scan-edge shimmer.
    var time: Double = 0

    /// Cap for smooth Canvas drawing; larger packets show every field but
    /// sample the long body/thumb runs proportionally.
    private static let maxCells = 900

    var body: some View {
        let segments = parsePacketSegments(bytes)
        let cells = Self.cells(bytes: bytes, segments: segments)

        VStack(alignment: .leading, spacing: 8) {
            Canvas { ctx, size in
                guard !cells.isEmpty, size.width > 8 else { return }
                let gap: CGFloat = 2
                let target: CGFloat = 9 // preferred cell size
                let cols = max(12, Int((size.width + gap) / (target + gap)))
                let cell = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
                let shown = min(cells.count, Self.maxCells)
                let sweep = progress * Double(shown)

                for i in 0..<shown {
                    let c = cells[i]
                    let col = i % cols
                    let row = i / cols
                    let x = CGFloat(col) * (cell + gap)
                    let y = CGFloat(row) * (cell + gap)
                    let rect = CGRect(x: x, y: y, width: cell, height: cell)
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.28)

                    let d = Double(i) - sweep
                    if d > 0 {
                        // Not yet materialized: faint placeholder.
                        ctx.fill(path, with: .color(.white.opacity(0.05)))
                        continue
                    }
                    // Brightness from the real byte value; freshly-swept cells
                    // flash bright, then settle. A soft shimmer breathes
                    // across settled cells so the grid feels alive on air.
                    let value = 0.30 + 0.70 * Double(c.value) / 255.0
                    let flash = max(0, 1 + d / 14.0) // 1 → 0 over ~14 cells
                    let shimmer = progress < 1
                        ? 0.08 * (0.5 + 0.5 * sin(time * 2.2 + Double(i) * 0.07))
                        : 0
                    let opacity = min(1, value * (0.55 + shimmer) + flash * 0.45)
                    ctx.fill(path, with: .color(c.color.opacity(opacity)))
                    if flash > 0.55 {
                        ctx.fill(path, with: .color(.white.opacity((flash - 0.55) * 0.8)))
                    }
                }
            }
            .frame(height: Self.gridHeight(cellCount: min(cells.count, Self.maxCells)))
            .accessibilityLabel("Packet data blocks — one cell per transmitted byte")

            if bytes.count > Self.maxCells {
                Text("Showing \(Self.maxCells) of \(bytes.count) bytes — long runs sampled proportionally.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }

            legend(segments: segments, total: bytes.count)
        }
    }

    // MARK: cells

    struct Cell {
        let value: UInt8
        let color: Color
    }

    static func cells(bytes: [UInt8], segments: [PacketSegment]?) -> [Cell] {
        guard let segments else {
            return bytes.prefix(maxCells).map { Cell(value: $0, color: .white.opacity(0.6)) }
        }
        // Every field is represented; if the packet exceeds the cap, sample
        // the big segments (body/thumb) evenly so proportions stay truthful.
        let total = bytes.count
        if total <= maxCells {
            var out: [Cell] = []
            out.reserveCapacity(total)
            for seg in segments {
                for i in seg.range { out.append(Cell(value: bytes[i], color: seg.field.color)) }
            }
            return out
        }
        let scale = Double(maxCells) / Double(total)
        var out: [Cell] = []
        out.reserveCapacity(maxCells)
        for seg in segments {
            let want = max(1, Int(Double(seg.count) * scale.rounded(toPlaces: 6)))
            if seg.count <= want {
                for i in seg.range { out.append(Cell(value: bytes[i], color: seg.field.color)) }
            } else {
                let step = Double(seg.count) / Double(want)
                for k in 0..<want {
                    let idx = seg.range.lowerBound + Int(Double(k) * step)
                    out.append(Cell(value: bytes[min(idx, seg.range.upperBound - 1)], color: seg.field.color))
                }
            }
        }
        return out
    }

    static func gridHeight(cellCount: Int) -> CGFloat {
        // Approximate: assumes ~48 columns at typical card width; the Canvas
        // recomputes exact layout, this just reserves sensible space.
        let rows = max(1, Int(ceil(Double(cellCount) / 48.0)))
        return CGFloat(rows) * 11 + 4
    }

    // MARK: legend

    @ViewBuilder
    private func legend(segments: [PacketSegment]?, total: Int) -> some View {
        if let segments {
            let items = segments.map { ($0.field.rawValue, $0.count, $0.field.color) }
            FlowChips(items: items)
        } else {
            Text("Unlabeled payload · \(total) B")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

/// Compact wrapping legend chips: colored dot + field + byte count.
struct FlowChips: View {
    let items: [(String, Int, Color)]

    var body: some View {
        // Two simple rows keep this dependency-free (no Layout protocol
        // gymnastics) and stable at any window width.
        let mid = (items.count + 1) / 2
        VStack(alignment: .leading, spacing: 4) {
            row(Array(items.prefix(mid)))
            if items.count > mid {
                row(Array(items.suffix(items.count - mid)))
            }
        }
    }

    private func row(_ slice: [(String, Int, Color)]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(slice.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Circle().fill(item.2).frame(width: 6, height: 6)
                    Text("\(item.0) · \(item.1) B")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}
