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

                // Graticule (parallels + meridians every 20°) — kept very faint
                // so the wireframe never competes with the foreground UI.
                let gratColor = Color(red: 0.48, green: 0.36, blue: 1.0).opacity(0.07)
                for p in stride(from: -60.0, through: 60.0, by: 20.0) {
                    var pts: [(Double, Double)] = []
                    for l in stride(from: -180.0, through: 180.0, by: 4.0) { pts.append((p, l)) }
                    stroke(pts, gratColor, 0.5)
                }
                for m in stride(from: -180.0, to: 180.0, by: 20.0) {
                    var pts: [(Double, Double)] = []
                    for p in stride(from: -88.0, through: 88.0, by: 4.0) { pts.append((p, m)) }
                    stroke(pts, gratColor, 0.5)
                }

                // Coastlines — dimmer + thinner than before so the continents
                // read as a soft ghost behind the panel, not a hard wireframe.
                let coast = Color(red: 0.22, green: 0.86, blue: 0.95).opacity(0.30)
                for ring in WORLD_OUTLINE {
                    var pts: [(Double, Double)] = []
                    var i = 0
                    while i + 1 < ring.count {
                        pts.append((ring[i], ring[i + 1]))
                        i += 2
                    }
                    if let first = pts.first { pts.append(first) }
                    stroke(pts, coast, 0.7)
                }

                // Pulsing location beacon (near hemisphere only). Rides the
                // rotating globe because it re-projects every frame; expanding
                // rings + a bright breathing core make it read as a live beacon.
                if let lat, let lon, let mp = project(lat, lon) {
                    let go = Color(red: 0.35, green: 0.95, blue: 0.65)
                    let cycle = 2.4
                    let base = t.truncatingRemainder(dividingBy: cycle) / cycle // 0…1

                    // Two staggered expanding rings.
                    for k in 0..<2 {
                        let kp = (base + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                        let rr = 3.5 + kp * 17
                        let a = (1 - kp) * (1 - kp) * 0.7 // ease-out fade
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: mp.x - rr, y: mp.y - rr, width: rr * 2, height: rr * 2)),
                            with: .color(go.opacity(a)), lineWidth: 1.5
                        )
                    }

                    // Soft glow halo that breathes with the pulse.
                    let breathe = 0.5 + 0.5 * sin(t * (2 * .pi / cycle))
                    let gr = 8.0 + breathe * 4
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: mp.x - gr, y: mp.y - gr, width: gr * 2, height: gr * 2)),
                        with: .radialGradient(
                            Gradient(colors: [go.opacity(0.55), .clear]),
                            center: mp, startRadius: 0, endRadius: gr
                        )
                    )

                    // Bright core + white hotspot.
                    ctx.fill(Path(ellipseIn: CGRect(x: mp.x - 3, y: mp.y - 3, width: 6, height: 6)), with: .color(go))
                    ctx.fill(Path(ellipseIn: CGRect(x: mp.x - 1.3, y: mp.y - 1.3, width: 2.6, height: 2.6)), with: .color(.white))
                }

                // Thin bright limb.
                ctx.stroke(Path(ellipseIn: disc), with: .color(.white.opacity(0.12)), lineWidth: 1)
            }
        }
        // Soft radial edge-fade so the sphere melts into the panel — fades
        // earlier and to nothing so no hard continent edges reach the UI.
        .mask {
            GeometryReader { g in
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white, location: 0.0),
                        .init(color: .white, location: 0.42),
                        .init(color: .white.opacity(0.35), location: 0.72),
                        .init(color: .white.opacity(0), location: 0.94),
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: min(g.size.width, g.size.height) / 2
                )
            }
        }
    }
}
