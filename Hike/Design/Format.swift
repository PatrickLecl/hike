import Foundation

/// Number and date formatting shared by all screens. Hike is metric throughout.
enum Format {
    /// Distance as value and unit, e.g. ("14.2", "km") or ("850", "m").
    static func distanceParts(_ meters: Double) -> (value: String, unit: String) {
        if meters < 1000 {
            return (number(meters.rounded(), fractionDigits: 0), "m")
        }
        let kilometers = meters / 1000
        return (number(kilometers, fractionDigits: kilometers < 100 ? 1 : 0), "km")
    }

    static func distance(_ meters: Double) -> String {
        let parts = distanceParts(meters)
        return "\(parts.value) \(parts.unit)"
    }

    /// Whole metres with grouping, e.g. "1,250".
    static func meters(_ value: Double) -> String {
        number(value.rounded(), fractionDigits: 0)
    }

    static func elevation(_ meters: Double) -> String {
        "\(Format.meters(meters)) m"
    }

    /// Walking time such as "4 h 35" or "45 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        let hourSymbol = String(localized: "h", comment: "Abbreviation for hours, as in 4 h 35")
        return "\(hours) \(hourSymbol) \(String(format: "%02d", minutes))"
    }

    /// Stopwatch time such as "2:41:07" or "41:07".
    static func stopwatch(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func number(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
