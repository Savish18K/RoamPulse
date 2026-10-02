import SwiftUI

// MARK: - Theme

/// Shared colours and sizes so every screen matches the Figma prototype.
enum Theme {
    // Brand gradient used on primary buttons (blue → purple).
    static let blue = Color(hex: 0x0A70E8)
    static let purple = Color(hex: 0x8C47B3)
    static let accentGradient = LinearGradient(colors: [blue, purple], startPoint: .leading, endPoint: .trailing)

    // Surfaces. System grouped colours give black/#1C1C1E/#2C2C2E in dark mode
    // and a matching light palette for free.
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let raised = Color(.tertiarySystemGroupedBackground)
    static let fill = Color(.tertiarySystemFill)
    static let stroke = Color.primary.opacity(0.08)

    static let cornerRadius: CGFloat = 20
}

/// Appearance option chosen in Settings.
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

// MARK: - Formatters

extension Date {
    /// Formats the date with a fixed pattern, e.g. `date.text("EEE d MMM")` → "Sun 13 Dec".
    func text(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = DemoClock.calendar
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}

extension Int {
    /// Minutes since midnight → "07:30".
    var clockText: String { String(format: "%02d:%02d", self / 60, self % 60) }

    /// Seconds → "1m 20s".
    var durationText: String { self < 60 ? "\(self)s" : "\(self / 60)m \(self % 60)s" }

    /// Seconds → "1:20".
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

    /// 51600 → "51,600".
    var grouped: String { Self.groupedFormatter.string(from: NSNumber(value: self)) ?? "\(Int(self))" }

    /// 51600 → "LKR 51,600".
    var lkr: String { "LKR " + grouped }

    /// 68400 → "68.4K".
    var compact: String { self >= 1000 ? String(format: "%.1fK", self / 1000) : grouped }

    /// 0.94 → "94%".
    var percentText: String { "\(Int((self * 100).rounded()))%" }
}
