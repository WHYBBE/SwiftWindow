import Foundation

enum ByteFormat {
    static func string(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 { return "\(bytes) B" }
        return String(format: "%.1f %@", value, units[index])
    }

    static func string(_ bytes: Int) -> String {
        string(UInt64(max(0, bytes)))
    }
}

enum SizeParser {
    /// Parses a token such as "991.5M", "16K", "3264", "0".
    static func parse(_ token: String) -> UInt64 {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        let numberPart = trimmed.prefix { $0.isNumber || $0 == "." }
        let unitPart = String(trimmed.dropFirst(numberPart.count))
        return bytes(number: String(numberPart), unit: unitPart)
    }

    static func bytes(number: String, unit: String) -> UInt64 {
        guard let value = Double(number) else { return 0 }
        let normalized = unit.uppercased()
            .replacingOccurrences(of: "B", with: "")
            .trimmingCharacters(in: .whitespaces)
        let multiplier: Double
        switch normalized {
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        case "T": multiplier = pow(1024, 4)
        case "P": multiplier = pow(1024, 5)
        default: multiplier = 1
        }
        return UInt64(max(0, value * multiplier))
    }
}
