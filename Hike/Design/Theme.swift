import SwiftUI
import UIKit

// The "Blaze" identity: warm map paper, spruce ink and the vermilion of a painted
// trail waymark. Serif headlines, generous rounding, contour lines as texture.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A colour that adapts to light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

enum Theme {
    // Adaptive colours
    static let paper = Color(light: 0xF3EEE3, dark: 0x0F1A15)
    static let card = Color(light: 0xFBF8F1, dark: 0x18271F)
    static let ink = Color(light: 0x14231C, dark: 0xF3EEE3)
    static let inkSoft = Color(light: 0x5B665F, dark: 0xA3AEA6)
    static let line = Color(light: 0xDDD5C5, dark: 0x2B3C33)
    static let blaze = Color(light: 0xE5482D, dark: 0xF05A3E)
    static let moss = Color(light: 0x5E7A4E, dark: 0x8FAE7C)
    static let mossTint = Color(light: 0xDFE6D2, dark: 0x263A2B)
    static let glacier = Color(light: 0x9CC3C9, dark: 0x7FA9B0)
    static let sun = Color(light: 0xF0B54A, dark: 0xF0B54A)

    // Fixed colours, used where the surface is always dark (recording) or always light.
    static let spruce = Color(hex: 0x14231C)
    static let spruceRaised = Color(hex: 0x1E3229)
    static let chalk = Color(hex: 0xF3EEE3)
    static let chalkSoft = Color(hex: 0xA3AEA6)

    // UIKit counterparts for the map.
    static let uiBlaze = UIColor(hex: 0xE5482D)
    static let uiSpruce = UIColor(hex: 0x14231C)
    static let uiChalk = UIColor(hex: 0xF3EEE3)
    static let uiGlacier = UIColor(hex: 0x2F7F8C)

    static let cornerRadius: CGFloat = 18
    static let screenPadding: CGFloat = 20
}

extension Font {
    /// Serif headline face used for screen titles and names.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Serif numerals with fixed digit widths, for statistics.
    static func stat(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif).monospacedDigit()
    }

    /// Small uppercase caption above a statistic.
    static let statLabel = Font.system(size: 11, weight: .semibold).width(.expanded)
}
