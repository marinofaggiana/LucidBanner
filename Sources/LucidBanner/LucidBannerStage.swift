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
public extension LucidBanner {
    enum Stage: Equatable {
        case success
        case error
        case info
        case warning
        case custom(String)

        public var rawValue: String {
            switch self {
            case .success: return "success"
            case .error:   return "error"
            case .info:    return "info"
            case .warning: return "warning"
            case .custom(let value): return value
            }
        }

        public init(rawValue: String) {
            let lower = rawValue.lowercased()
            switch lower {
            case "success": self = .success
            case "error":   self = .error
            case "info":    self = .info
            case "warning": self = .warning
            default:        self = .custom(rawValue)
            }
        }
    }
}
