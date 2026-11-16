import Charts
import SwiftUI

/// Height profile of a route: distance along the bottom, elevation up the side.
struct ElevationChart: View {
    var samples: [ElevationSample]
    var tint: Color = Theme.blaze
    var labelColor: Color = Theme.inkSoft

    var body: some View {
        let elevations = samples.map(\.elevation)
        let lowest = elevations.min() ?? 0
        let highest = elevations.max() ?? 0
        // Round outwards so flat routes don't look like mountains.
        let step: Double = (highest - lowest) > 400 ? 200 : 50
        let floor = (lowest / step).rounded(.down) * step
        let ceiling = max((highest / step).rounded(.up) * step, floor + step * 2)

        Chart(samples) { sample in
            AreaMark(
                x: .value("Distance", sample.distance / 1000),
                yStart: .value("Base", floor),
                yEnd: .value("Elevation", sample.elevation)
            )
            .foregroundStyle(
                LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.04)], startPoint: .top, endPoint: .bottom)
            )
            LineMark(
                x: .value("Distance", sample.distance / 1000),
                y: .value("Elevation", sample.elevation)
            )
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: floor...ceiling)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let kilometers = value.as(Double.self) {
                        Text(verbatim: "\(Format.number(kilometers, fractionDigits: 0)) km")
                            .font(.system(size: 10))
                            .foregroundStyle(labelColor)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let meters = value.as(Double.self) {
                        Text(verbatim: "\(Format.meters(meters)) m")
                            .font(.system(size: 10))
                            .foregroundStyle(labelColor)
                    }
                }
            }
        }
        .accessibilityLabel(Text("Elevation profile"))
        .accessibilityValue(
            Text(verbatim: "\(Format.elevation(lowest)) – \(Format.elevation(highest))")
        )
    }
}
