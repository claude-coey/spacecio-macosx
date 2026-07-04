import SwiftUI

/// Orthographic wireframe globe — the app-side twin of the website's WireGlobe.
/// Real coastlines + a faint graticule over a soft atmospheric fill, a glowing
/// marker at the station's approximate location, a very slow rotation, and a
/// radial edge-fade so it reads as an elegant, high-end futuristic backdrop.
struct RelayGlobe: View {
    var lat: Double?
    var lon: Double?

    private static let DEG = Double.pi / 180

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
            Canvas { ctx, size in
                let R = min(size.width, size.height) / 2 - 2
                guard R > 12 else { return }
                let cx = size.width / 2
                let cy = size.height / 2
                let lat0 = 16.0
                let t = timeline.date.timeIntervalSinceReferenceDate
                // Very slow spin, starting centred near the marker's longitude.
                let lon0 = (lon ?? 0) + t * 2.0

                func project(_ la: Double, _ lo: Double) -> CGPoint? {
                    let phi = la * Self.DEG
                    let lam = (lo - lon0) * Self.DEG
                    let phi0 = lat0 * Self.DEG
                    let cosc = sin(phi0) * sin(phi) + cos(phi0) * cos(phi) * cos(lam)
                    if cosc <= 0.02 { return nil } // far hemisphere
                    let x = R * cos(phi) * sin(lam)
                    let y = -R * (cos(phi0) * sin(phi) - sin(phi0) * cos(phi) * cos(lam))
                    return CGPoint(x: cx + x, y: cy + y)
                }

                func stroke(_ pts: [(Double, Double)], _ color: Color, _ width: CGFloat) {
                    var path = Path()
                    var pen = false
                    for (la, lo) in pts {
                        if let p = project(la, lo) {
                            if pen { path.addLine(to: p) } else { path.move(to: p); pen = true }
                        } else {
                            pen = false
                        }
                    }
                    ctx.stroke(path, with: .color(color), lineWidth: width)
                }

                // Atmosphere fill (subtle blue sphere) + limb.
                let disc = CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2)
                ctx.fill(
                    Path(ellipseIn: disc),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.10, green: 0.17, blue: 0.36).opacity(0.55),
                            Color(red: 0.02, green: 0.03, blue: 0.09).opacity(0.85),
                        ]),
                        center: CGPoint(x: cx, y: cy - R * 0.18),
                        startRadius: 0, endRadius: R
                    )
                )

                // Graticule (parallels + meridians every 20°).
                let gratColor = Color(red: 0.48, green: 0.36, blue: 1.0).opacity(0.13)
                for p in stride(from: -60.0, through: 60.0, by: 20.0) {
                    var pts: [(Double, Double)] = []
                    for l in stride(from: -180.0, through: 180.0, by: 4.0) { pts.append((p, l)) }
                    stroke(pts, gratColor, 0.6)
                }
                for m in stride(from: -180.0, to: 180.0, by: 20.0) {
                    var pts: [(Double, Double)] = []
                    for p in stride(from: -88.0, through: 88.0, by: 4.0) { pts.append((p, m)) }
                    stroke(pts, gratColor, 0.6)
                }

                // Coastlines.
                let coast = Color(red: 0.22, green: 0.86, blue: 0.95).opacity(0.55)
                for ring in WORLD_OUTLINE {
                    var pts: [(Double, Double)] = []
                    var i = 0
                    while i + 1 < ring.count {
                        pts.append((ring[i], ring[i + 1]))
                        i += 2
                    }
                    if let first = pts.first { pts.append(first) }
                    stroke(pts, coast, 0.8)
                }

                // Marker at the station location (near hemisphere only).
                if let lat, let lon, let mp = project(lat, lon) {
                    let go = Color(red: 0.35, green: 0.95, blue: 0.65)
                    ctx.fill(Path(ellipseIn: CGRect(x: mp.x - 7, y: mp.y - 7, width: 14, height: 14)),
                             with: .color(go.opacity(0.22)))
                    ctx.fill(Path(ellipseIn: CGRect(x: mp.x - 3, y: mp.y - 3, width: 6, height: 6)),
                             with: .color(go))
                    ctx.stroke(Path(ellipseIn: CGRect(x: mp.x - 3, y: mp.y - 3, width: 6, height: 6)),
                               with: .color(.white.opacity(0.85)), lineWidth: 0.8)
                }

                // Thin bright limb.
                ctx.stroke(Path(ellipseIn: disc), with: .color(.white.opacity(0.16)), lineWidth: 1)
            }
        }
        // Soft radial edge-fade so the sphere melts into the panel.
        .mask {
            GeometryReader { g in
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white, location: 0.0),
                        .init(color: .white, location: 0.7),
                        .init(color: .white.opacity(0), location: 1.0),
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: min(g.size.width, g.size.height) / 2
                )
            }
        }
    }
}
