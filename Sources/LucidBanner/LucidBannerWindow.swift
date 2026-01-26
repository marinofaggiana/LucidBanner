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
/// This window does not manage presentation logic, animations, or state.
/// Its responsibilities are strictly limited to:
/// - Hosting the banner view hierarchy.
/// - Supporting passthrough hit-testing.
/// - Notifying layout changes to the banner coordinator.
///
/// The class is intentionally minimal to keep UIKit surface area small
/// and predictable.
internal final class LucidBannerWindow: UIWindow {

    /// Enables or disables passthrough hit-testing.
    ///
    /// When `true`, the window allows touches to pass through to the
    /// underlying application except within the `hitTargetView`.
    /// When `false`, the window behaves like a normal UIWindow and
    /// intercepts all touches.
    var isPassthrough: Bool = true

    /// View that remains interactive while passthrough mode is enabled.
    ///
    /// Typically this is the banner’s root host view.
    /// Touches outside this view are forwarded to the app below.
    weak var hitTargetView: UIView?

    /// Callback invoked whenever the window’s layout changes.
    ///
    /// This includes events such as:
    /// - Device rotation
    /// - Safe-area inset changes
    /// - Bounds updates
    ///
    /// LucidBanner uses this hook to trigger safe, deferred layout
    /// recalculation without relying on view controller callbacks.
    var onLayoutChange: (() -> Void)?

    /// Called by UIKit when the window lays out its subviews.
    ///
    /// The implementation forwards the event via `onLayoutChange`
    /// to allow the banner system to react to layout-driven changes.
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutChange?()
    }

    /// Custom hit-testing implementation supporting passthrough behavior.
    ///
    /// Behavior:
    /// - If `isPassthrough` is `false`, hit-testing behaves normally.
    /// - If `isPassthrough` is `true`, only touches within `hitTargetView`
    ///   are handled by this window; all other touches are ignored and
    ///   fall through to the underlying application.
    ///
    /// This mechanism allows the banner to float above the UI without
    /// blocking interaction unless explicitly configured to do so.
    ///
    /// - Parameters:
    ///   - point: The touch location in window coordinates.
    ///   - event: The event associated with the touch.
    /// - Returns: The view that should receive the touch, or `nil`
    ///            to allow passthrough to lower windows.
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
