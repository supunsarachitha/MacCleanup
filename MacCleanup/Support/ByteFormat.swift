import Foundation

/// Formats sizes the way Finder does (decimal units), so numbers match what users see elsewhere.
enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        formatter().string(fromByteCount: max(0, bytes))
    }

    /// Splits "47.0 GB" into ("47.0", "GB") for large statistics.
    static func parts(_ bytes: Int64) -> (value: String, unit: String) {
        let text = string(bytes)
        guard let space = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }

    private static func formatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }
}

enum DurationFormat {
    static func string(_ duration: Duration) -> String {
        if duration < .seconds(1) { return "Less than a second" }
        return duration.formatted(.units(
            allowed: [.hours, .minutes, .seconds],
            width: .wide,
            maximumUnitCount: 2,
            fractionalPart: .hide
        ))
    }
}
