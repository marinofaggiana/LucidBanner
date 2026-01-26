//
//  LucidBannerWindow.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//

import Foundation

/// Convenience helpers for normalizing user-facing strings.
///
/// These utilities are intentionally minimal and side-effect free.
/// They are designed to be used at data boundaries (e.g. payload
/// initialization or update merging) to ensure consistent handling
/// of empty or whitespace-only strings.
public extension String {

    /// Returns `nil` if the string is empty.
    ///
    /// This property performs a direct emptiness check without
    /// trimming whitespace or newlines.
    ///
    /// Typical use cases:
    /// - Filtering optional values after external input.
    /// - Avoiding empty-string propagation in data models.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    /// Returns the string trimmed of whitespace and newlines,
    /// or `nil` if the result is empty.
    ///
    /// This property is commonly used when normalizing
    /// user-provided or dynamic text before storing it
    /// in a payload or state model.
    ///
    /// Example:
    /// ```swift
    /// let title = rawInput.trimmedNilIfEmpty
    /// ```
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
