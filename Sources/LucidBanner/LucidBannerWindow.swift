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

/// Lightweight UIWindow subclass used only to display the banner.
///
/// It can optionally forward touch events to the underlying app (passthrough mode)
/// while still hosting the banner content on top of everything else.
internal final class LucidBannerWindow: UIWindow {
    /// When `true`, the window is mostly passthrough and forwards hits to `hitTargetView`.
    var isPassthrough: Bool = true

    /// View used as the region that can still receive touches when the window is passthrough.
    weak var hitTargetView: UIView?

    /// Closure invoked every time the window lays out its subviews (e.g. on rotation).
    var onLayoutChange: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutChange?()
    }

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
