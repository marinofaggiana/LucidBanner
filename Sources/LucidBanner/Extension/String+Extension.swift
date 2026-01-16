import Foundation

public extension String {
    /// Returns `nil` if the string is empty.
    /// Useful after trimming whitespace/newlines.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    /// Trims whitespace and newlines.
    /// Returns `nil` if the resulting string is empty.
    var trimmedNilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
