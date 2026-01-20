//
//  LucidBannerMinimizeCoordinator
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBannerMinimizeCoordinator is a lightweight, generic coordinator
//  responsible for toggling a LucidBanner between expanded and minimized states.
//
//  The coordinator is intentionally UI-agnostic:
//  - It has no knowledge of tab bars, navigation controllers, split views,
//    or application-specific layout rules.
//  - The minimized target position is always provided externally via a
//    mandatory resolver closure.
//
//  The coordinator operates purely as a behavioral extension of LucidBanner,
//  manipulating banner position and state without owning presentation logic.
//
//  Responsibilities:
//  - Track a single active banner token.
//  - Toggle minimization state in response to user interaction.
//  - Reposition the banner using a resolver-defined target point.
//  - Re-apply minimized positioning after orientation or layout changes.
//
//  Design principles:
//  - Zero assumptions about app layout.
//  - No UIKit hierarchy introspection beyond the banner itself.
//  - SwiftUI remains a passive renderer driven by state.
//
//  Invariants:
//  - At most one banner token is tracked at a time.
//  - All operations are validated against the active LucidBanner token.
//  - Minimized positioning is always resolved in window coordinates.
//

@preconcurrency import UIKit

/// Coordinator responsible for toggling a `LucidBanner` between
/// expanded and minimized presentation states.
///
/// This coordinator does not own or present banners.
/// It operates exclusively on an already-presented banner
/// identified by a token returned from `LucidBanner.shared.show(...)`.
///
/// Concurrency:
/// - Annotated `@MainActor` because it mutates UIKit views and
///   UI-driven shared state (`LucidBannerState.isMinimized`).
/// - Uses `@preconcurrency import UIKit` to relax strict Sendable
///   enforcement for Objective-C based APIs.
///
/// Lifecycle:
/// - `register(token:resolveMinimizePoint:)` must be invoked after
///   banner presentation.
/// - Orientation changes are observed to keep minimized positioning valid.
/// - Tap handling is delegated from SwiftUI content.
@MainActor
public final class LucidBannerMinimizeCoordinator {

    /// Shared singleton instance.
    ///
    /// A singleton is appropriate because only one banner may be
    /// active at a time in the LucidBanner system.
    public static let shared = LucidBannerMinimizeCoordinator()

    // MARK: - Types

    /// Context passed to the minimized-position resolver.
    ///
    /// All coordinates are expressed in **window space**.
    /// The resolver is free to ignore or use any of the provided fields.
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

        /// Convenience: safe-area insets of the window.
        public let safeAreaInsets: UIEdgeInsets
    }

    /// Mandatory handler used to compute the minimized target position.
    ///
    /// The returned point must be expressed in window coordinates.
    public typealias ResolveMinimizePointHandler =
        @MainActor (_ context: ResolveContext) -> CGPoint

    // MARK: - Stored Properties

    /// Currently tracked banner token.
    ///
    /// Only one token may be tracked at a time.
    private var currentToken: Int?

    /// Resolver used to compute the minimized target position.
    ///
    /// This handler is mandatory for minimization to occur.
    private var resolveHandler: ResolveMinimizePointHandler?

    /// Orientation change observer token.
    ///
    /// Stored as `NSObjectProtocol` due to Objective-C based API.
    private var orientationObserver: NSObjectProtocol?

    // MARK: - Initialization

    /// Creates the coordinator and installs an orientation-change observer.
    ///
    /// On rotation, a short delay is introduced to allow UIKit to settle
    /// window bounds and layout before recomputing the minimized position.
    init() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                // Allow layout to stabilize before repositioning.
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

    /// Registers the active banner token and the mandatory minimize-point resolver.
    ///
    /// If `token` is `nil`, the coordinator state is cleared.
    ///
    /// - Parameters:
    ///   - token: Banner token returned by `LucidBanner.shared.show(...)`.
    ///   - resolveMinimizePoint: Mandatory handler resolving the minimized position.
    public func register(
        token: Int?,
        resolveMinimizePoint: @escaping ResolveMinimizePointHandler
    ) {
        guard let token else {
            clear()
            return
        }

        currentToken = token
        resolveHandler = resolveMinimizePoint
    }

    // MARK: - Public API

    /// Handles a tap originating from the SwiftUI banner content.
    ///
    /// Behavior:
    /// - If the banner is currently minimized, it is restored.
    /// - If the banner is expanded, it is minimized and repositioned.
    ///
    /// - Parameter state: The shared `LucidBannerState` instance.
    public func handleTap(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        guard LucidBanner.shared.isAlive(token) else {
            clear()
            return
        }

        if state.isMinimized {
            maximize(state)
        } else {
            minimize(state)
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
    /// - If minimized, recomputes and applies the minimized position.
    /// - If expanded, restores the canonical LucidBanner position.
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

        if state.isMinimized {
            guard let target = resolvedMinimizePoint(
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

    /// Minimizes the banner and moves it to the resolved target position.
    ///
    /// Steps:
    /// - Updates shared state to trigger minimized SwiftUI rendering.
    /// - Disables dragging to avoid interaction conflicts.
    /// - Requests a layout re-measure for compact content.
    /// - Moves the banner to the resolver-defined point.
    private func minimize(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        state.isMinimized = true

        // Disable dragging while minimized.
        LucidBanner.shared.setDraggingEnabled(false, for: token)

        // Re-measure compact layout.
        LucidBanner.shared.requestRelayout(animated: false)

        if let target = resolvedMinimizePoint(for: token, state: state) {
            LucidBanner.shared.move(
                toX: target.x,
                y: target.y,
                for: token,
                animated: true
            )
        }
    }

    /// Restores the banner to its expanded state and canonical position.
    ///
    /// Steps:
    /// - Updates shared state to trigger expanded SwiftUI rendering.
    /// - Re-enables dragging if configured.
    /// - Requests a layout re-measure for expanded content.
    /// - Resets the banner to its standard position.
    private func maximize(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        state.isMinimized = false

        if state.payload.draggable {
            LucidBanner.shared.setDraggingEnabled(true, for: token)
        }

        // Re-measure expanded layout.
        LucidBanner.shared.requestRelayout(animated: false)

        // Restore canonical position.
        LucidBanner.shared.resetPosition(for: token, animated: true)
    }

    /// Resolves the minimized target point using the registered resolver.
    ///
    /// - Parameters:
    ///   - token: Active banner token.
    ///   - state: Current banner state.
    /// - Returns: Target point in window coordinates, or `nil` if resolution fails.
    private func resolvedMinimizePoint(
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
