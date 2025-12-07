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

public extension LucidBannerState {

    /// Returns the semantic `Stage` representation of the current `stage` string.
    ///
    /// This provides a typed interpretation of the banner’s stage value,
    /// mapping common identifiers such as `"success"`, `"error"`, `"info"` and `"warning"`
    /// to corresponding enum cases, while any unmatched value becomes `.custom(rawValue)`.
    ///
    /// - Returns: A `LucidBanner.Stage` value derived from `stage`, or `nil` if `stage` is not set.
    var typedStage: LucidBanner.Stage? {
        guard let stage else { return nil }
        return LucidBanner.Stage(rawValue: stage)
    }
}
