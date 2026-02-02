//
//  LucidBannerWindow.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBannerWindow is a minimal `UIWindow` subclass whose sole
//  responsibility is to host a LucidBanner above the application UI.
//
//  The window supports a *passthrough interaction mode*, allowing
//  touches to flow through to the underlying application except for
//  a designated interactive region representing the banner itself.
//
//  This design enables LucidBanner to appear visually above the UI
//  without behaving like a full modal overlay unless explicitly requested.
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
