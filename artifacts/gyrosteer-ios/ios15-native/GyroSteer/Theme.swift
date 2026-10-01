import SwiftUI

enum WheelTheme {
    static let background = Color(hex: 0x090E13)
    static let card = Color(hex: 0x121A22)
    static let cardRaised = Color(hex: 0x1B2630)
    static let foreground = Color(hex: 0xEEF4F6)
    static let primary = Color(hex: 0x46E6D0)
    static let primaryInk = Color(hex: 0x06110F)
    static let accent = Color(hex: 0xFF654A)
    static let muted = Color(hex: 0x82929C)
    static let border = Color(hex: 0x26343E)
    static let input = Color(hex: 0x2A3944)
    static let wheelRim = Color(hex: 0x27343E)
    static let wheelFace = Color(hex: 0x0D141A)
    static let wheelSpoke = Color(hex: 0x202B34)
    static let wheelHub = Color(hex: 0x101820)
    static let brakeFill = Color(hex: 0xFFE4E7)
    static let brakeBorder = Color(hex: 0x55333A)
    static let throttleBorder = Color(hex: 0x285A54)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}