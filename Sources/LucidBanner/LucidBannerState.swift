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

import SwiftUI
import Combine

/// Shared observable state model used by LucidBanner.
///
/// Apps may subclass this type to add custom fields or behaviors.
/// The state is owned by `LucidBanner` and injected into the SwiftUI
/// content for both initial rendering and live updates.
@MainActor
open class LucidBannerState: ObservableObject {
    /// The full banner configuration/state.
    /// This is the single source of truth for SwiftUI.
    @Published public var payload: LucidBannerPayload

    /// Managed internally by the banner system.
    @Published public internal(set) var isMinimized: Bool = false

    public init(payload: LucidBannerPayload) {
        self.payload = payload
    }
}
