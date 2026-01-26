//
//  LucidBannerVariantCoordinator
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBannerVariantCoordinator is a lightweight, generic coordinator
//  responsible for switching a LucidBanner between alternative visual
//  representations (variants) of the same banner.
//
//  The banner remains the same logical entity at all times.
//  Only its active visual variant and on-screen positioning change.
//
//  The coordinator is intentionally UI-agnostic:
//  - It has no knowledge of tab bars, navigation controllers, split views,
//    or application-specific layout rules.
//  - The target position for the alternate variant is always provided
//    externally via a mandatory resolver closure.
//
//  The coordinator operates purely as a behavioral extension of LucidBanner.
//  It does not own presentation logic and does not render UI.
//  SwiftUI views remain passive renderers driven entirely by state.
//
//  Responsibilities:
//  - Track a single active banner token.
//  - Toggle the banner between standard and alternate variants.
//  - Reposition the banner using a resolver-defined target point.
//  - Re-apply variant positioning after orientation or layout changes.
//
//  Invariants:
//  - At most one banner token is tracked at a time.
//  - All operations are validated against the active LucidBanner token.
//  - Variant positioning is always resolved in window coordinates.
//

@preconcurrency import UIKit

/// Coordinator responsible for switching a `LucidBanner`
/// between its standard and alternate visual variants.
///
/// This coordinator does not own or present banners.
/// It operates exclusively on an already-presented banner,
/// identified by a token returned from `LucidBanner.shared.show(...)`.
///
/// Concurrency:
/// - Annotated with `@MainActor` because it mutates UIKit views and
///   UI-driven shared state (`LucidBannerState.variant`).
/// - Uses `@preconcurrency import UIKit` to relax strict `Sendable`
///   enforcement for Objective-C based APIs.
///
/// Lifecycle:
/// - `register(token:resolveVariantPoint:)` must be invoked after
///   banner presentation.
/// - Orientation changes are observed to keep variant positioning valid.
/// - User interaction (tap) is delegated from SwiftUI content.
@MainActor
public final class LucidBannerVariantCoordinator {

    /// Shared singleton instance.
    ///
    /// A singleton is appropriate because LucidBanner guarantees
    /// that only one banner can be active at a time.
    public static let shared = LucidBannerVariantCoordinator()

    // MARK: - Types

    /// Context passed to the variant-position resolver.
    ///
    /// All coordinates are expressed in **window space**.
    public struct ResolveContext {

        /// The active banner token.
        public let token: Int

        /// Shared banner state observed by SwiftUI.
        public let state: LucidBannerState

        /// UIKit host view wrapping the SwiftUI banner.
        public let hostView: UIView

        /// Window hosting the banner.
        public let window: UIWindow

        /// Convenience: full window bounds.
        public let bounds: CGRect

        /// Convenience: window safe-area insets.
        public let safeAreaInsets: UIEdgeInsets
    }

    /// Mandatory handler used to compute the target position
    /// for the alternate banner variant.
    ///
    /// The returned point must be expressed in window coordinates.
    public typealias ResolveVariantPointHandler =
        @MainActor (_ context: ResolveContext) -> CGPoint

    // MARK: - Stored Properties

    /// Currently tracked banner token.
    ///
    /// Only one token may be tracked at any given time.
    private var currentToken: Int?

    /// Resolver used to compute the target position
    /// for the alternate banner variant.
    private var resolveHandler: ResolveVariantPointHandler?

    /// Orientation change observer token.
    ///
    /// Stored as `NSObjectProtocol` due to Objective-C based API.
    private var orientationObserver: NSObjectProtocol?

    // MARK: - Initialization

    /// Creates the coordinator and installs an orientation-change observer.
    ///
    /// On rotation, a short delay is introduced to allow UIKit to
    /// stabilize window bounds and layout before repositioning.
    init() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                // Allow layout to stabilize before recomputing position.
                try? await Task.sleep(for: .milliseconds(100))
                self.refreshPosition(animated: true)
            }
        }
    }

    /// Removes the orientation observer.
    ///
    /// For a singleton this usually runs only at process termination,
    /// but explicit cleanup avoids observer leaks and aids testability.
    deinit {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
    }

    // MARK: - Registration

    /// Registers the active banner token and the mandatory variant-position resolver.
    ///
    /// If `token` is `nil`, the coordinator state is cleared.
    ///
    /// - Parameters:
    ///   - token: Banner token returned by `LucidBanner.shared.show(...)`.
    ///   - resolveVariantPoint: Mandatory handler resolving the alternate position.
    public func register(
        token: Int?,
        resolveVariantPoint: @escaping ResolveVariantPointHandler
    ) {
        guard let token else {
            clear()
            return
        }

        currentToken = token
        resolveHandler = resolveVariantPoint
    }

    // MARK: - Public API

    /// Handles a tap originating from the SwiftUI banner content.
    ///
    /// Behavior:
    /// - If the banner is using the alternate variant, it switches back
    ///   to the standard variant.
    /// - If the banner is using the standard variant, it switches to the
    ///   alternate variant and repositions accordingly.
    ///
    /// - Parameter state: The shared `LucidBannerState` instance.
    public func handleTap(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        guard LucidBanner.shared.isAlive(token) else {
            clear()
            return
        }

        switch state.variant {
        case .alternate:
            applyStandardVariant(state)

        case .standard:
            applyAlternateVariant(state)
        }
    }

    // MARK: - Internal Helpers

    /// Clears all tracked coordinator state.
    private func clear() {
        currentToken = nil
        resolveHandler = nil
    }

    /// Re-applies banner positioning after layout or orientation changes.
    ///
    /// Behavior:
    /// - If the alternate variant is active, recomputes and applies
    ///   the resolved alternate position.
    /// - Otherwise, restores the canonical LucidBanner position.
    ///
    /// - Parameter animated: Whether repositioning is animated.
    private func refreshPosition(animated: Bool = true) {
        guard let token = currentToken else { return }

        guard LucidBanner.shared.isAlive(token) else {
            clear()
            return
        }

        guard let state = LucidBanner.shared.currentState(for: token) else {
            return
        }

        if state.variant == .alternate {
            guard let target = resolvedVariantPoint(
                for: token,
                state: state
            ) else { return }

            LucidBanner.shared.move(
                toX: target.x,
                y: target.y,
                for: token,
                animated: animated
            )
        } else {
            LucidBanner.shared.resetPosition(
                for: token,
                animated: true
            )
        }
    }

    /// Applies the alternate banner variant and moves the banner
    /// to the resolver-defined target position.
    private func applyAlternateVariant(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        state.variant = .alternate

        // Disable dragging while using the alternate variant.
        LucidBanner.shared.setDraggingEnabled(false, for: token)

        // Re-measure alternate layout.
        LucidBanner.shared.requestRelayout(animated: false)

        if let target = resolvedVariantPoint(for: token, state: state) {
            LucidBanner.shared.move(
                toX: target.x,
                y: target.y,
                for: token,
                animated: true
            )
        }
    }

    /// Restores the standard banner variant and canonical banner position.
    private func applyStandardVariant(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        state.variant = .standard

        if state.payload.draggable {
            LucidBanner.shared.setDraggingEnabled(true, for: token)
        }

        // Re-measure standard layout.
        LucidBanner.shared.requestRelayout(animated: false)

        // Restore canonical position.
        LucidBanner.shared.resetPosition(for: token, animated: true)
    }

    /// Resolves the target point for the alternate variant
    /// using the registered resolver.
    ///
    /// - Parameters:
    ///   - token: Active banner token.
    ///   - state: Current banner state.
    /// - Returns: Target point in window coordinates, or `nil` if resolution fails.
    private func resolvedVariantPoint(
        for token: Int,
        state: LucidBannerState
    ) -> CGPoint? {

        guard let resolveHandler else { return nil }

        guard let hostView = LucidBanner.shared.currentHostView(for: token),
              let window = hostView.window else {
            return nil
        }

        let context = ResolveContext(
            token: token,
            state: state,
            hostView: hostView,
            window: window,
            bounds: window.bounds,
            safeAreaInsets: window.safeAreaInsets
        )

        return resolveHandler(context)
    }
}
