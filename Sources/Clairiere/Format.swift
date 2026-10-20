import Foundation

enum Format {
    private static let number: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.decimalSeparator = ","
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func mem(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        let units: [(Double, String, Int)] = [
            (1_073_741_824, "Go", 1),
            (1_048_576, "Mo", 0),
            (1024, "Ko", 0)
        ]
        for (size, unit, digits) in units where value >= size || unit == "Ko" {
            number.maximumFractionDigits = value / size >= 100 ? 0 : digits
            let rendered = number.string(from: NSNumber(value: value / size)) ?? "0"
            return "\(rendered) \(unit)"
        }
        return "0 Ko"
    }

    static func signedMem(_ bytesPerMinute: Double) -> String {
        let sign = bytesPerMinute >= 0 ? "+" : "−"
        return "\(sign)\(mem(UInt64(abs(bytesPerMinute)))) / min"
    }

    static func cpu(_ percent: Double) -> String {
        if percent < 0.4 { return "peu active" }
        number.maximumFractionDigits = percent >= 10 ? 0 : 1
        let rendered = number.string(from: NSNumber(value: percent)) ?? "0"
        return "\(rendered) %"
    }

    static func share(_ part: UInt64, of total: UInt64) -> String {
        guard total > 0 else { return "0 %" }
        let value = min(999, (Double(part) / Double(total)) * 100)
        number.maximumFractionDigits = value >= 10 ? 0 : 1
        let rendered = number.string(from: NSNumber(value: value)) ?? "0"
        return "\(rendered) %"
    }

    static func count(_ value: Int, one: String, many: String) -> String {
        value > 1 ? "\(value) \(many)" : "\(value) \(one)"
    }

    static func day(_ date: Date?) -> String {
        guard let date else { return "pas encore ouverte" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
