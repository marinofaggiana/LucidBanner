//
//  LucidBanner
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Description:
//  Flexible scene-aware banner system built with SwiftUI + UIKit.
//  Provides animated, interruptible, queueable in-app notifications,
//  with optional touch-passthrough, swipe-to-dismiss and auto-dismiss.
//

import Foundation

/// Semantic stage descriptor for a LucidBanner.
///
/// Stages provide a lightweight, typed way to express the "meaning"
/// of the current banner (e.g. success, error, info). They can be
/// mapped to colors, haptics or logging categories by the host app.
public extension LucidBanner {
    enum Stage: Equatable {
        /// A successful or completed operation.
        case success
        /// An error or failed operation.
        case error
        /// Neutral informational message.
        case info
        /// Warning or potentially problematic condition.
        case warning
        /// Used for utility
        case button
        /// Used for utility
        case none
        /// Used for utility
        case placeholder
        /// Custom, app-defined stage identified by an arbitrary string.
        case custom(String)

        /// String representation of the stage, suitable for logging or storage.
        ///
        /// Built-in cases use fixed lowercase identifiers (`"success"`,
        /// `"error"`, `"info"`, `"warning"`). Custom stages return the
        /// associated string value as-is.
        public var rawValue: String {
            switch self {
            case .success: return "success"
            case .error: return "error"
            case .info: return "info"
            case .warning: return "warning"
            case .button: return "button"
            case .none: return "none"
            case .placeholder: return "placeholder"
            case .custom(let value): return value
            }
        }

        /// Creates a `Stage` from a raw string value.
        ///
        /// Known values (`"success"`, `"error"`, `"info"`, `"warning"`)
        /// are matched case-insensitively. Any other value is wrapped
        /// as `.custom(rawValue)`.
        ///
        /// - Parameter rawValue: String representation of the stage.
        public init(rawValue: String) {
            let lower = rawValue.lowercased()
            switch lower {
            case "success": self = .success
            case "error": self = .error
            case "info": self = .info
            case "warning": self = .warning
            case "button": self = .button
            case "none": self = .none
            case "placeholder": self = .placeholder
            default: self = .custom(rawValue)
            }
        }
    }
}
