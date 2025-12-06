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

/// Shared observable state model used by LucidBanner.
/// Subclassable to allow custom banner logic or additional UI fields.

@MainActor
open class LucidBannerState: ObservableObject {
    // MARK: - Text

    /// Main title text. `nil` means no title is shown.
    @Published public var title: String?

    /// Optional secondary text placed below the title.
    @Published public var subtitle: String?

    /// Optional small text used for status or extra information.
    @Published public var footnote: String?

    // MARK: - Icon & animation

    /// System symbol name used for the leading icon (e.g. `arrow.up.circle`).
    @Published public var systemImage: String?

    /// Current animation style applied to the icon.
    @Published public var imageAnimation: LucidBanner.LucidBannerAnimationStyle

    // MARK: - Progress

    /// Optional progress value in the `0...1` range. `nil` hides the progress view.
    @Published public var progress: Double?

    // MARK: - Misc

    /// Optional semantic stage identifier attached to the current banner payload.
    @Published public var stage: String?

    /// Arbitrary key–value storage for advanced scenarios (not interpreted by LucidBanner).
    @Published public var flags: [String: Any] = [:]

    /// When `true`, the banner renders in a compact layout controlled by the SwiftUI content.
    @Published public var isMinimized: Bool = false

    /// Creates a new shared state object for a LucidBanner.
    ///
    /// Empty strings for `title`, `subtitle` and `footnote` are normalized to `nil`.
    ///
    /// - Parameters:
    ///   - title: Optional main title text.
    ///   - subtitle: Optional subtitle text.
    ///   - footnote: Optional small footnote text.
    ///   - systemImage: SF Symbol name for the icon.
    ///   - imageAnimation: Icon animation style.
    ///   - progress: Optional progress value (`0...1`).
    ///   - stage: Optional stage identifier string.
    public init(title: String? = nil,
                subtitle: String? = nil,
                footnote: String? = nil,
                systemImage: String? = nil,
                imageAnimation: LucidBanner.LucidBannerAnimationStyle,
                progress: Double? = nil,
                stage: String? = nil) {
        self.title = (title?.isEmpty == true) ? nil : title
        self.subtitle = (subtitle?.isEmpty == true) ? nil : subtitle
        self.footnote = (footnote?.isEmpty == true) ? nil : footnote
        self.systemImage = systemImage
        self.imageAnimation = imageAnimation
        self.progress = progress
        self.stage = stage
    }
}

