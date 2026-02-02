//
//  LucidBannerStage.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  Defines the semantic stage model used by LucidBanner.
//
//  A stage expresses *meaning*, not presentation.
//  It allows host applications to attach semantics such as
//  styling, haptics, logging, or analytics without coupling
//  to banner UI implementation.
//

import Foundation

public extension LucidBanner {

    /// Semantic descriptor representing the meaning of a banner.
    ///
    /// `Stage` is intentionally orthogonal to presentation.
    /// It provides a typed signal that the host application
    /// may interpret freely.
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
        case button

        /// Utility stage used for placeholder or non-semantic banners.
        case placeholder

        /// Application-defined stage identified by an arbitrary string.
        case custom(String)

        /// Canonical string representation of the stage.
        ///
        /// Suitable for logging, persistence, and analytics.
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

        /// Creates a stage from a raw string value.
        ///
        /// Known values are matched case-insensitively.
        /// Unknown values are mapped to `.custom`.
        public init(rawValue: String) {
            let lower = rawValue.lowercased()
            switch lower {
            case "success": self = .success
            case "error": self = .error
            case "info": self = .info
            case "warning": self = .warning
            case "button": self = .button
            case "placeholder": self = .placeholder
            default:
                self = .custom(rawValue)
            }
        }
    }
}
