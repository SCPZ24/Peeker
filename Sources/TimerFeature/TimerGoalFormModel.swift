import Foundation

enum TimerDurationComponent: CaseIterable, Sendable {
    case hours
    case minutes
    case seconds
}

struct TimerDurationDraft: Equatable, Sendable {
    var hours: String
    var minutes: String
    var seconds: String

    init(hours: String = "00", minutes: String = "30", seconds: String = "00") {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
    }

    init(targetSeconds: Int64) {
        let clamped = min(max(targetSeconds, 0), 86_399)
        hours = Self.format(Int(clamped / 3_600))
        minutes = Self.format(Int((clamped % 3_600) / 60))
        seconds = Self.format(Int(clamped % 60))
    }

    var targetSeconds: Int64? {
        guard let hours = Self.parse(hours, in: 0...23),
              let minutes = Self.parse(minutes, in: 0...59),
              let seconds = Self.parse(seconds, in: 0...59) else {
            return nil
        }

        let total = Int64(hours * 3_600 + minutes * 60 + seconds)
        return (1...86_399).contains(total) ? total : nil
    }

    mutating func adjust(_ component: TimerDurationComponent, by delta: Int) {
        let range: ClosedRange<Int>
        let currentText: String

        switch component {
        case .hours:
            range = 0...23
            currentText = hours
        case .minutes:
            range = 0...59
            currentText = minutes
        case .seconds:
            range = 0...59
            currentText = seconds
        }

        let current = Self.parse(currentText, in: range) ?? range.lowerBound
        let adjusted = min(max(current + delta, range.lowerBound), range.upperBound)
        let formatted = Self.format(adjusted)

        switch component {
        case .hours:
            hours = formatted
        case .minutes:
            minutes = formatted
        case .seconds:
            seconds = formatted
        }
    }

    private static func parse(_ text: String, in range: ClosedRange<Int>) -> Int? {
        guard !text.isEmpty,
              text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              let value = Int(text),
              range.contains(value) else {
            return nil
        }
        return value
    }

    private static func format(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

enum TimerPresetColor: String, CaseIterable, Identifiable, Sendable {
    case red = "#FF3B30"
    case lightYellow = "#FFD60A"
    case lakeBlue = "#4F9DFF"
    case lightGreen = "#34C759"
    case purple = "#AF52DE"
    case pink = "#FF2D55"
    case cyan = "#64D2FF"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .red: "正红"
        case .lightYellow: "浅黄"
        case .lakeBlue: "湖蓝"
        case .lightGreen: "浅绿"
        case .purple: "紫"
        case .pink: "粉"
        case .cyan: "青"
        }
    }
}
