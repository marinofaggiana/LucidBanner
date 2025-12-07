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

import UIKit

/// Lightweight `UIWindow` subclass responsible solely for hosting a LucidBanner.
///
/// The window can operate in *passthrough mode*, meaning that it forwards touches
/// to underlying app content except within a designated interactive area (`hitTargetView`).
/// This allows banners to float above the UI without blocking interaction unless requested.
internal final class LucidBannerWindow: UIWindow {

    /// When `true`, the window becomes mostly transparent to hit-testing and only forwards
    /// touches to the assigned `hitTargetView`. When `false`, the window behaves normally.
    var isPassthrough: Bool = true

    /// View that should continue receiving touches even when passthrough mode is enabled.
    /// Typically the banner's root view.
    weak var hitTargetView: UIView?

    /// Closure invoked whenever the window's layout changes, such as on rotation
    /// or safe-area adjustments. Used by LucidBanner to trigger a relayout pass safely.
    var onLayoutChange: (() -> Void)?

    /// Called by UIKit when the window lays out its subviews.
    /// Triggers `onLayoutChange` for layout-driven banner adjustments.
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutChange?()
    }

    /// Customized hit-testing to support passthrough behavior.
    ///
    /// If `isPassthrough` is `true`, the window only returns a hit if the touch
    /// falls inside `hitTargetView`. Otherwise, hits pass through to the app below.
    ///
    /// - Parameters:
    ///   - point: Point in window coordinates.
    ///   - event: UIEvent for the hit test.
    /// - Returns: The view that should receive the touch, or `nil` to allow passthrough.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isPassthrough else {
            return super.hitTest(point, with: event)
        }
        guard let target = hitTargetView else {
            return nil
        }

        let p = target.convert(point, from: self)
        return target.bounds.contains(p) ? super.hitTest(point, with: event) : nil
    }
}
