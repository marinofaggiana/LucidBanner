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
///
/// Apps may subclass this type to add custom fields or behaviors.
/// The state is owned by `LucidBanner` and injected into the SwiftUI
/// content for both initial rendering and live updates.
@MainActor
open class LucidBannerState: ObservableObject {

    // MARK: - Text

    /// Main title text. `nil` means no title is shown.
    @Published public var title: String?

    /// Optional secondary text placed below the title.
    @Published public var subtitle: String?

    /// Optional small text used for status or additional context.
    @Published public var footnote: String?

    // MARK: - Icon & animation

    /// System symbol name used for the leading icon (e.g. `"arrow.up.circle"`).
    @Published public var systemImage: String?

    /// Current animation style applied to the banner icon.
    @Published public var imageAnimation: LucidBanner.LucidBannerAnimationStyle

    // MARK: - Progress

    /// Optional progress value in the `0...1` range.
    /// When `nil`, the progress view is hidden.
    @Published public var progress: Double?

    // MARK: - Misc

    /// Optional semantic stage string associated with the banner.
    /// Used for external logic, analytics or styling decisions.
    @Published public var stage: String?

    /// Indicates whether the SwiftUI layout should render the banner
    /// in a compact, minimized form. The library does not enforce any
    /// visual style; the SwiftUI content decides how to react.
    @Published public var isMinimized: Bool = false

    /// Creates a new shared state object for a LucidBanner.
    ///
    /// Empty strings for textual fields are automatically normalized to `nil`
    /// to avoid rendering empty labels in the SwiftUI view layer.
    ///
    /// - Parameters:
    ///   - title: Optional main title text.
    ///   - subtitle: Optional subtitle text.
    ///   - footnote: Optional small footnote text.
    ///   - systemImage: SF Symbol name displayed as the icon.
    ///   - imageAnimation: Animation applied to the icon.
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
