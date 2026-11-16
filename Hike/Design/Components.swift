import SwiftUI

/// The Hike logo and trail symbol: a painted waymark of three stripes.
struct BlazeMark: View {
    var accent: Color = Theme.blaze
    var width: CGFloat = 34

    var body: some View {
        let stripe = width * 0.2
        VStack(spacing: 0) {
            Theme.chalk.frame(height: stripe)
            accent.frame(height: stripe)
            Theme.chalk.frame(height: stripe)
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.09, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

extension TrailNetwork {
    /// Stripe colour of the waymark shown for this kind of trail.
    var accent: Color {
        switch self {
        case .international, .national: return Theme.blaze
        case .regional: return Theme.sun
        case .local: return Theme.glacier
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .international: return "International"
        case .national: return "National"
        case .regional: return "Regional"
        case .local: return "Local"
        }
    }
}

/// Thin topographic contour lines, used as a quiet texture behind cards and thumbnails.
struct ContourBackground: View {
    var color: Color = Theme.line
    var seed: Int = 0

    var body: some View {
        Canvas { context, size in
            let offset = Double(seed % 7) * 0.9
            let shiftX = CGFloat(0.28 + 0.05 * sin(offset))
            let shiftY = CGFloat(0.7 + 0.06 * cos(offset))
            let centers: [CGPoint] = [
                CGPoint(x: size.width * shiftX, y: size.height * 0.35),
                CGPoint(x: size.width * 0.78, y: size.height * shiftY),
            ]
            for (centerIndex, center) in centers.enumerated() {
                for ring in 1...6 {
                    let radius = Double(ring) * Double(max(size.width, size.height)) * 0.085
                    var path = Path()
                    let steps = 72
                    for step in 0...steps {
                        let angle = Double(step) / Double(steps) * 2 * .pi
                        let wobbleA: Double = 0.13 * sin(angle * 3 + offset + Double(centerIndex) * 1.7)
                        let wobbleB: Double = 0.07 * cos(angle * 5 - offset + Double(ring) * 0.6)
                        let wobble: Double = 1 + wobbleA + wobbleB
                        let point = CGPoint(
                            x: center.x + CGFloat(cos(angle) * radius * wobble * 1.25),
                            y: center.y + CGFloat(sin(angle) * radius * wobble)
                        )
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.closeSubpath()
                    context.stroke(path, with: .color(color), lineWidth: 0.8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Draws a route scaled to fit its frame. Used for list thumbnails.
struct RouteShape: Shape {
    var points: [GeoPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1, let box = Geo.boundingBox(of: points) else { return path }
        let projected = points.map { Geo.webMercator(from: $0) }
        let min = Geo.webMercator(from: GeoPoint(latitude: box.minLatitude, longitude: box.minLongitude))
        let max = Geo.webMercator(from: GeoPoint(latitude: box.maxLatitude, longitude: box.maxLongitude))
        let width = Swift.max(max.x - min.x, 1)
        let height = Swift.max(max.y - min.y, 1)
        let scale = Swift.min(Double(rect.width) / width, Double(rect.height) / height)
        let offsetX = (Double(rect.width) - width * scale) / 2
        let offsetY = (Double(rect.height) - height * scale) / 2
        for (index, point) in projected.enumerated() {
            let position = CGPoint(
                x: rect.minX + CGFloat(offsetX + (point.x - min.x) * scale),
                y: rect.minY + CGFloat(offsetY + (max.y - point.y) * scale)
            )
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        return path
    }
}

/// Square thumbnail of a route on contour lines.
struct RouteThumbnail: View {
    var points: [GeoPoint]
    var seed: Int = 0
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            Theme.mossTint.opacity(0.45)
            ContourBackground(color: Theme.moss.opacity(0.35), seed: seed)
            RouteShape(points: points)
                .stroke(Theme.blaze, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .padding(12)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// One statistic: a serif number, its unit and a small uppercase caption.
struct StatView: View {
    var label: LocalizedStringKey
    var value: String
    var unit: String = ""
    var size: CGFloat = 24
    var primary: Color = Theme.ink
    var secondary: Color = Theme.inkSoft
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.stat(size))
                    .foregroundStyle(primary)
                if !unit.isEmpty {
                    Text(verbatim: unit)
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(primary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label)
                .font(.statLabel)
                .textCase(.uppercase)
                .foregroundStyle(secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small rounded label such as "Offline" or "Recorded".
struct TagView: View {
    var text: LocalizedStringKey
    var systemImage: String?
    var tint: Color = Theme.moss
    var background: Color = Theme.mossTint

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Filter chip: filled with ink when selected, outlined otherwise.
struct ChipView: View {
    var title: LocalizedStringKey
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Theme.paper : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.ink : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wide primary action: ink surface, serif label.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(18, weight: .semibold))
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
    }
}

/// Quieter action: outlined, same shape as the primary button.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
    }
}

/// Round floating button that sits on top of the map.
struct MapButton: View {
    var systemImage: String
    var label: LocalizedStringKey
    var isActive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? Theme.blaze : Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

extension View {
    /// Paper card with a hairline border.
    func hikeCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

/// Large serif screen title, as used on Discover and My hikes.
struct ScreenTitle: View {
    var text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.display(38))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Centered message for empty lists and failed loads.
struct EmptyStateView: View {
    var title: LocalizedStringKey
    var message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            BlazeMark(width: 54)
            Text(title)
                .font(.display(22))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
