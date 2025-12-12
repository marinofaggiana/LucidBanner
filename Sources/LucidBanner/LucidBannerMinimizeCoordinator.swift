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

@preconcurrency import UIKit

/// Coordinator that toggles a `LucidBanner` between expanded and minimized states.
///
/// This coordinator is designed to be **generic**:
/// - It does not know about tab bars, navigation bars, controllers, or app layout rules.
/// - The minimized target position is provided by a **mandatory** resolver closure.
///
/// Concurrency:
/// - The class is `@MainActor` because it interacts with UIKit (`UIWindow`, `UIView`)
///   and mutates UI-driven state (`LucidBannerState.isMinimized`).
/// - `@preconcurrency import UIKit` suppresses strict `Sendable` enforcement for UIKit
///   / Objective-C APIs (e.g., `NotificationCenter` observer tokens).
///
/// Lifecycle:
/// - `register(token:resolveMinimizePoint:)` must be called after `LucidBanner.shared.show(...)`
///   returns a token.
/// - The coordinator listens to `UIDevice.orientationDidChangeNotification` and re-applies
///   the minimized position after rotation.
/// - `handleTap(_:)` toggles minimization on user tap.
///
/// Note:
/// - This coordinator tracks a single active token (`currentToken`) at a time.
@MainActor
public final class LucidBannerMinimizeCoordinator {
    static let shared = LucidBannerMinimizeCoordinator()

    // MARK: - Types

    /// Context passed to the mandatory minimize-point resolver.
    ///
    /// The resolver should return a target point in **window coordinates**
    /// for the minimized banner.
    struct ResolveContext {
        /// The active banner token.
        let token: Int

        /// The shared banner state instance (SwiftUI observes this).
        let state: LucidBannerState

        /// The banner host view (UIKit container for the SwiftUI content).
        let hostView: UIView

        /// The window hosting the banner.
        let window: UIWindow

        /// Convenience: window bounds.
        let bounds: CGRect

        /// Convenience: window safe-area insets.
        let safeAreaInsets: UIEdgeInsets
    }

    /// Mandatory resolver used to compute the minimized target point.
    ///
    /// Return a CGPoint in window coordinates where the banner should move
    /// when minimized.
    typealias ResolveMinimizePointHandler = @MainActor (_ context: ResolveContext) -> CGPoint

    // MARK: - Stored properties

    private var currentToken: Int?
    /// Mandatory resolver for minimized target point.
    private var resolveHandler: ResolveMinimizePointHandler?
    /// Orientation change observer token (Objective-C based, not `Sendable`).
    private var orientationObserver: NSObjectProtocol?

    // MARK: - Init

    /// Creates the coordinator and installs an orientation change observer.
    ///
    /// On rotation, a short delay is used to allow UIKit to settle layout and window bounds
    /// before recomputing the minimized target position.
    init() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            Task { @MainActor in
                // Small delay to let the window/layout settle after rotation.
                try? await Task.sleep(for: .milliseconds(100))
                self.refreshPosition(animated: true)
            }
        }
    }

    /// Removes the orientation observer.
    ///
    /// Note: For a singleton this typically runs only at process termination, but removing
    /// observers is still good hygiene.
    deinit {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
    }

    // MARK: - Registration

    /// Registers the active banner token and the mandatory resolver.
    ///
    /// The resolver is required because this coordinator does not make assumptions about
    /// UI chrome (tab bar placement, navigation bars, sidebars, etc.). The host app decides
    /// where the minimized bubble should land.
    ///
    /// - Parameters:
    ///   - token: Banner token returned by `LucidBanner.shared.show(...)`.
    ///   - resolveMinimizePoint: Mandatory handler returning the minimized target point.
    func register(token: Int?, resolveMinimizePoint: @escaping ResolveMinimizePointHandler) {
        guard let token else {
            clear()
            return
        }

        currentToken = token
        resolveHandler = resolveMinimizePoint
    }

    // MARK: - Public API

    /// Handles a tap gesture coming from the SwiftUI banner content.
    ///
    /// - Parameter state: The `LucidBannerState` instance owned by the banner content.
    ///
    /// Behavior:
    /// - If the banner is minimized, it is restored (maximized).
    /// - If the banner is expanded, it is minimized and moved to the resolver-provided point.
    func handleTap(_ state: LucidBannerState) {
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

    // MARK: - Private

    /// Clears the coordinator state.
    private func clear() {
        currentToken = nil
        resolveHandler = nil
    }

    /// Refreshes banner position after rotation/layout changes.
    ///
    /// - Parameter animated: Whether the move should be animated.
    ///
    /// Behavior:
    /// - If minimized, recomputes the target via the resolver and moves there.
    /// - If not minimized, resets to the standard LucidBanner position.
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
            guard let target = resolvedMinimizePoint(for: token, state: state) else {
                return
            }

            LucidBanner.shared.move(
                toX: target.x,
                y: target.y,
                for: token,
                animated: animated
            )
        } else {
            LucidBanner.shared.resetPosition(for: token, animated: true)
        }
    }

    /// Minimizes the banner and moves it to the resolver-provided target point.
    ///
    /// Steps:
    /// - Updates `state.isMinimized` so SwiftUI renders the minimized UI.
    /// - Disables dragging to avoid conflicts with a minimized bubble.
    /// - Requests a relayout to re-measure the minimized content size.
    /// - Moves the banner window to the resolved target point.
    private func minimize(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        state.isMinimized = true

        // Disable dragging while minimized.
        LucidBanner.shared.setDraggingEnabled(false, for: token)

        // Re-measure for the compact (minimized) SwiftUI layout.
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
    /// - Updates `state.isMinimized` so SwiftUI renders the expanded UI.
    /// - Re-enables dragging if the banner was configured as draggable.
    /// - Requests a relayout to re-measure the expanded content size.
    /// - Resets the banner to the canonical position managed by LucidBanner.
    private func maximize(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        state.isMinimized = false

        if state.draggable {
            LucidBanner.shared.setDraggingEnabled(true, for: token)
        }

        // Re-measure for the full SwiftUI layout.
        LucidBanner.shared.requestRelayout(animated: false)

        // Let LucidBanner restore the canonical position.
        LucidBanner.shared.resetPosition(for: token, animated: true)
    }

    /// Resolves the minimized target point using the registered resolver.
    ///
    /// - Parameters:
    ///   - token: The active banner token.
    ///   - state: The current banner state instance.
    /// - Returns: The target point in window coordinates, or nil if resolution failed.
    private func resolvedMinimizePoint(for token: Int, state: LucidBannerState) -> CGPoint? {
        guard let resolveHandler else { return nil }

        guard let hostView = LucidBanner.shared.currentHostView(for: token),
              let window = hostView.window else {
            return nil
        }

        let ctx = ResolveContext(
            token: token,
            state: state,
            hostView: hostView,
            window: window,
            bounds: window.bounds,
            safeAreaInsets: window.safeAreaInsets
        )

        return resolveHandler(ctx)
    }
}
