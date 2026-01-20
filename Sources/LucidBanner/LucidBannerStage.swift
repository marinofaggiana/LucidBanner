//
//  LucidBannerStage.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  Defines the semantic stage model used by LucidBanner to express
//  the *meaning* of a banner independently from its visual appearance.
//
//  A stage represents intent, not presentation.
//  It allows the host application to:
//  - Map banner meaning to colors or icons.
//  - Trigger haptics or sounds.
//  - Group or filter banners for analytics or logging.
//  - Apply app-specific semantics without coupling to UI code.
//
//  Stages are intentionally lightweight and value-based.
//  They do not encode behavior, only classification.
//

import Foundation

public extension LucidBanner {

    /// Semantic descriptor representing the meaning of a banner.
    ///
    /// `Stage` is deliberately orthogonal to presentation:
    /// it does not prescribe colors, animations, or layout.
    ///
    /// Instead, it provides a typed signal that the host application
    /// may interpret freely (e.g. mapping `.error` to red UI,
    /// `.success` to haptics, or `.custom` to logging categories).
    ///
    /// Design principles:
    /// - Minimal surface area.
    /// - Stable, string-backed representation.
    /// - Extensible without breaking existing code.
    enum Stage: Equatable {

        /// Represents a successful or completed operation.
        case success

        /// Represents an error or failed operation.
        case error

        /// Represents a neutral informational message.
        case info

        /// Represents a warning or potentially problematic condition.
        case warning

        /// Utility stage typically used for interactive or control-like banners.
        ///
        /// This stage has no intrinsic semantics and is interpreted by the host app.
        case button

        /// Utility stage used for placeholder or non-semantic banners.
        ///
        /// Often used during loading, layout stabilization, or previews.
        case placeholder

        /// Custom, application-defined stage identified by an arbitrary string.
        ///
        /// This allows apps to define domain-specific semantics
        /// without modifying LucidBanner.
        case custom(String)

        /// Canonical string representation of the stage.
        ///
        /// This value is suitable for:
        /// - Logging
        /// - Persistence
        /// - Analytics
        ///
        /// Built-in stages use fixed lowercase identifiers.
        /// Custom stages return their associated string unchanged.
        public var rawValue: String {
            switch self {
            case .success:
                return "success"
            case .error:
                return "error"
            case .info:
                return "info"
            case .warning:
                return "warning"
            case .button:
                return "button"
            case .placeholder:
                return "placeholder"
            case .custom(let value):
                return value
            }
        }

        /// Initializes a `Stage` from a raw string value.
        ///
        /// Matching rules:
        /// - Known built-in values are matched case-insensitively.
        /// - Any unknown value is wrapped as `.custom(rawValue)`.
        ///
        /// This guarantees forward compatibility when reading
        /// persisted or external stage values.
        ///
        /// - Parameter rawValue: String representation of the stage.
        public init(rawValue: String) {
            let lower = rawValue.lowercased()
            switch lower {
            case "success":
                self = .success
            case "error":
                self = .error
            case "info":
                self = .info
            case "warning":
                self = .warning
            case "button":
                self = .button
            case "placeholder":
                self = .placeholder
            default:
                self = .custom(rawValue)
            }
        }
    }
}
