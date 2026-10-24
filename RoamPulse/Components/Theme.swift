import SwiftUI

// Colours and sizes from the Figma design
enum Theme {
    static let blue = Color(hex: 0x0A70E8)
    static let purple = Color(hex: 0x8C47B3)
    static let accentGradient = LinearGradient(colors: [blue, purple], startPoint: .leading, endPoint: .trailing)

    // System colours so light and dark mode both work
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let raised = Color(.tertiarySystemGroupedBackground)
    static let fill = Color(.tertiarySystemFill)
    static let stroke = Color.primary.opacity(0.08)

    static let cornerRadius: CGFloat = 20
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Date {
    // e.g. date.text("EEE d MMM") -> "Sun 13 Dec"
    func text(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = Calendar.trip
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}

extension Int {
    var clockText: String { String(format: "%02d:%02d", self / 60, self % 60) }

    var durationText: String { self < 60 ? "\(self)s" : "\(self / 60)m \(self % 60)s" }

    var timerText: String { String(format: "%d:%02d", self / 60, self % 60) }
}

extension Double {
    private static let groupedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    var grouped: String { Self.groupedFormatter.string(from: NSNumber(value: self)) ?? "\(Int(self))" }

    var lkr: String { "LKR " + grouped }

    var compact: String { self >= 1000 ? String(format: "%.1fK", self / 1000) : grouped }

    var percentText: String { "\(Int((self * 100).rounded()))%" }
}
