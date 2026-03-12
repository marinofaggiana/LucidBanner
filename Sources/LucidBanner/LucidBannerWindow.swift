//
//  LucidBannerWindow.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBannerWindow is a minimal UIWindow subclass dedicated to hosting
//  a single scene-scoped LucidBanner above the application UI.
//
//  The window exists purely as an isolation boundary between the banner
//  presentation layer and the underlying application content.
//
//  Interaction Model:
//  - Supports passthrough mode, forwarding touches outside the banner
//    to the underlying application.
//  - Supports blocking mode, where the banner behaves as a lightweight
//    modal overlay.
//  - Restricts hit-testing to a designated interactive region.
//
//  LucidBannerWindow does not manage lifecycle, layout, animation,
//  or state. It is a thin infrastructure layer used exclusively
//  by LucidBanner.
//

import UIKit

/// Lightweight `UIWindow` subclass dedicated to hosting a LucidBanner.
///
/// This window is intentionally minimal and UI-agnostic.
/// It only:
/// - Hosts the banner view hierarchy
/// - Supports passthrough hit-testing
/// - Notifies layout changes to the banner system
internal final class LucidBannerWindow: UIWindow {

    /// Enables passthrough hit-testing.
    ///
    /// When enabled, touches are forwarded to the underlying application
    /// except within `hitTargetView`.
    var isPassthrough: Bool = true

    /// View that remains interactive while passthrough mode is enabled.
    ///
    /// Typically this is the banner’s host view.
    weak var hitTargetView: UIView?

    /// Called whenever the window layout changes.
    ///
    /// Used by LucidBanner to react to bounds or safe-area updates.
    var onLayoutChange: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutChange?()
    }

    /// Custom hit-testing supporting passthrough behavior.
    ///
    /// When passthrough is enabled, only touches inside `hitTargetView`
    /// are handled by this window; all others fall through.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isPassthrough else {
            return super.hitTest(point, with: event)
        }

        guard let target = hitTargetView else {
            return nil
        }

        let localPoint = target.convert(point, from: self)
        return target.bounds.contains(localPoint)
            ? super.hitTest(point, with: event)
            : nil
    }
}
