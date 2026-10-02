import SwiftUI

/// "Offline Topo Canvas" from the prototype: a drawn topographic map with the
/// group's route to the next stop. Everything here is static mock data.
struct OfflineMapView: View {
    let tripID: UUID
    var activityID: UUID?

    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isNavigating = false
    @State private var showsContours = true

    private var trip: Trip? { store.trip(tripID) }
    private var activity: Activity? { trip?.activities.first { $0.id == activityID } }
    private var targetName: String { activity?.place ?? "Nine Arch Bridge" }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                TopoMap(showsContours: showsContours, targetName: targetName, members: trip?.members ?? [])
                statusChips
                mapControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.bottom, 36)
                    .padding(.trailing, 14)
            }
            .clipped()
            targetCard
        }
        .background(Color.black)
        .navigationTitle("Map")
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.title3.weight(.semibold))
                    Text("Day \(activity?.day ?? 2)\nHub")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
            }
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 4) {
                Text("Offline Topo Canvas").font(.title3.bold())
                Label("VECTOR LOCK", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15), in: Capsule())
            }
            Spacer()
            Image(systemName: "square.3.layers.3d")
            Image(systemName: "magnifyingglass")
            Image(systemName: "person.fill")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.blue, in: Circle())
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var statusChips: some View {
        VStack(spacing: 8) {
            HStack {
                mapChip(color: .white) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("Ella V4 Topo Locked").bold()
                    Text("· 27km² · 42MB").foregroundStyle(.secondary)
                }
                Spacer()
                mapChip(color: .blue) {
                    Image(systemName: "location.fill")
                    Text("GPS ±3m")
                }
            }
            HStack {
                mapChip(color: .orange) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Rain advisory 14:00–17:00")
                    Text("· 82% Cloud").foregroundStyle(.secondary)
                }
                Spacer()
                mapChip(color: .green) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                    Text("3 Mesh Linked")
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func mapChip<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 5, content: content)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.75), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
    }

    private var mapControls: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: "location.north.line")
                Text("38°NE").font(.system(size: 9, weight: .bold))
            }
            .frame(width: 48, height: 48)
            .background(.black.opacity(0.8), in: Circle())
            CircleIconButton(systemImage: "mountain.2", size: 48, label: "Toggle contours") {
                withAnimation { showsContours.toggle() }
            }
            CircleIconButton(systemImage: "scope", size: 48, label: "Centre on me") {}
        }
        .foregroundStyle(.white)
    }

    // MARK: - Target card

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 14) {
                PhotoView(photo: .nineArchBridge)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Text("1,041m").font(.caption2.bold()).foregroundStyle(.white).padding(6)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("STOP 4 OF 5 · TARGET").font(.caption.bold()).foregroundStyle(.blue)
                        Spacer()
                        StatusBadge(text: "Safe Trail", color: .green, showsDot: false)
                    }
                    Text(targetName).font(.title2.bold())
                    Text("Next train passing in 55m (17:35 Express)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                metric("Distance", value: "680", unit: "m", color: .primary)
                metric("Est. Walk", value: "12", unit: "min", color: .blue)
                metric("Elevation Δ", value: "+28", unit: "m", color: .green)
            }
            .padding(.vertical, 12)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Elevation Profile").foregroundStyle(.secondary)
                    Spacer()
                    Text("Current: 1,022m → Target: 1,041m").bold()
                }
                .font(.caption)
                ElevationProfile()
                    .frame(height: 50)
                    .padding(.horizontal, 10)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .bottom) {
                        HStack {
                            Text("Art Cafe")
                            Spacer()
                            Text("Viaduct")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 2)
                    }
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation { isNavigating.toggle() }
                } label: {
                    HStack {
                        Circle().fill(.white).frame(width: 8, height: 8)
                        Text(isNavigating ? "End Navigation" : "Start Turn-by-Turn")
                        Image(systemName: "location.north.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 50))
                CircleIconButton(systemImage: "info.circle", size: 50, label: "Info") {}
                CircleIconButton(systemImage: "mic", size: 50, label: "Record memory here") {}
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28, style: .continuous)
                .fill(Theme.card)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func metric(_ title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title2.bold()).foregroundStyle(color)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Map drawing

/// Contour lines, railway and route drawn with Canvas, plus labels and member pins.
private struct TopoMap: View {
    let showsContours: Bool
    let targetName: String
    let members: [Member]

    // Positions as fractions of the map size.
    private let you = CGPoint(x: 0.26, y: 0.80)
    private let routeStops = [CGPoint(x: 0.26, y: 0.80), CGPoint(x: 0.34, y: 0.70), CGPoint(x: 0.45, y: 0.58), CGPoint(x: 0.64, y: 0.40)]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Canvas { context, size in
                    if showsContours { drawContours(in: &context, size: size) }
                    drawRailway(in: &context, size: size)
                    drawRoute(in: &context, size: size)
                }

                label("Little Adam's", detail: "1,141m", icon: "mountain.2")
                    .position(x: size.width * 0.78, y: size.height * 0.31)
                label("Tunnel 19", detail: "Kiosk", icon: "house")
                    .position(x: size.width * 0.66, y: size.height * 0.78)
                Text("\(targetName) · 1,040m")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.white, in: Capsule())
                    .position(x: size.width * 0.42, y: size.height * 0.33)

                ForEach(Array(members.dropFirst().prefix(2).enumerated()), id: \.element.id) { index, member in
                    let point = routeStops[2 - index]
                    memberPin(member)
                        .position(x: size.width * point.x + 44, y: size.height * point.y)
                }

                VStack(spacing: 4) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(color: .blue, radius: 8)
                    Text("You (\(DemoClock.minutesNow.clockText))")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.8), in: Capsule())
                }
                .position(x: size.width * you.x, y: size.height * you.y + 14)

                HStack(spacing: 6) {
                    Rectangle().fill(.white).frame(width: 44, height: 3)
                    Text("100 m · Contours 20m")
                }
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.75), in: Capsule())
                .position(x: 80, y: size.height - 16)
            }
            .foregroundStyle(.white)
        }
        .background(Color(white: 0.1))
    }

    private func drawContours(in context: inout GraphicsContext, size: CGSize) {
        for line in 0..<16 {
            var path = Path()
            let baseY = size.height * CGFloat(line) / 15
            path.move(to: CGPoint(x: 0, y: baseY))
            for x in stride(from: CGFloat(0), through: size.width, by: 6) {
                let wave = sin(x / size.width * .pi * 2 + CGFloat(line) * 0.7) * 24
                let ripple = cos(x / 80 + CGFloat(line)) * 8
                path.addLine(to: CGPoint(x: x, y: baseY + wave + ripple))
            }
            let isMajor = line % 4 == 0
            context.stroke(path, with: .color(.white.opacity(isMajor ? 0.22 : 0.08)), lineWidth: isMajor ? 1.4 : 0.8)
        }
    }

    private func drawRailway(in context: inout GraphicsContext, size: CGSize) {
        var rail = Path()
        rail.move(to: CGPoint(x: 0, y: size.height * 0.47))
        rail.addQuadCurve(to: CGPoint(x: size.width, y: size.height * 0.33),
                          control: CGPoint(x: size.width * 0.5, y: size.height * 0.44))
        context.stroke(rail, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
    }

    private func drawRoute(in context: inout GraphicsContext, size: CGSize) {
        let points = routeStops.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        var route = Path()
        route.addLines(points)
        context.stroke(route, with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        for point in points {
            context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(.white))
        }
    }

    private func label(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).bold()
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
    }

    private func memberPin(_ member: Member) -> some View {
        HStack(spacing: 5) {
            AvatarView(member: member, size: 22)
            Text(member.name).font(.caption.bold())
        }
        .padding(4)
        .padding(.trailing, 6)
        .background(.black.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
    }
}

/// Small elevation curve from the current position to the target.
private struct ElevationProfile: View {
    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: rect.height * 0.7))
                    path.addCurve(to: CGPoint(x: rect.width, y: rect.height * 0.25),
                                  control1: CGPoint(x: rect.width * 0.4, y: rect.height * 0.7),
                                  control2: CGPoint(x: rect.width * 0.6, y: rect.height * 0.3))
                }
                .stroke(Color.primary, lineWidth: 2.5)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 10, height: 10)
                    .position(x: rect.width * 0.35, y: rect.height * 0.64)
            }
        }
    }
}

#Preview {
    NavigationStack { OfflineMapView(tripID: SampleData.hillCountry.id) }
        .environment(TripStore())
        .preferredColorScheme(.dark)
}
