//
//  LucidBannerVariantCoordinator
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBannerVariantCoordinator is a lightweight coordinator responsible
//  for toggling a single active LucidBanner between visual variants.
//
//  The coordinator is UI-agnostic:
//  - It does not know app-specific layout (tab bars, split views, etc.).
//  - Positioning and (optionally) horizontal layout for the alternate variant
//    are resolved externally via a mandatory resolver closure.
//
//  Responsibilities:
//  - Track a single active banner token.
//  - Toggle between standard and alternate variants.
//  - Apply externally-resolved position and optional horizontal layout.
//  - Re-apply alternate positioning after orientation/layout changes.
//
//  Invariants:
//  - At most one banner token is tracked at a time.
//  - All operations are validated against the active LucidBanner token.
//  - Variant positioning/layout is always resolved externally.
//

@preconcurrency import UIKit

@MainActor
public final class LucidBannerVariantCoordinator {

    /// Shared singleton instance.
    public static let shared = LucidBannerVariantCoordinator()

    // MARK: - Types

    /// Context passed to the variant resolver.
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

    /// Resolution produced by the external resolver.
    ///
    /// - `targetPoint` is mandatory and expressed in window coordinates.
    /// - `horizontalLayout` is optional; when provided, it is applied via `LucidBanner.update(...)`.
    public struct VariantResolution {
        public let targetPoint: CGPoint
        public let horizontalLayout: LucidBanner.HorizontalLayout?

        public init(
            targetPoint: CGPoint,
            horizontalLayout: LucidBanner.HorizontalLayout? = nil
        ) {
            self.targetPoint = targetPoint
            self.horizontalLayout = horizontalLayout
        }
    }

    /// Legacy resolver that only returns a target point (window coordinates).
    public typealias ResolveVariantPointHandler =
        @MainActor (_ context: ResolveContext) -> CGPoint

    /// Modern resolver that may return both target point and optional horizontal layout.
    public typealias ResolveVariantHandler =
        @MainActor (_ context: ResolveContext) -> VariantResolution

    // MARK: - Stored Properties

    /// Currently tracked banner token.
    private var currentToken: Int?

    /// Unified resolver for alternate variant behavior.
    private var resolveHandler: ResolveVariantHandler?

    /// Stores the canonical (standard) horizontal layout so we can restore it
    /// after applying an alternate layout.
    private var standardHorizontalLayout: LucidBanner.HorizontalLayout?

    /// Orientation change observer token.
    private var orientationObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Allow layout to stabilize before recomputing position/layout.
                try? await Task.sleep(for: .milliseconds(100))
                self.refreshPosition(animated: true)
            }
        }
    }

    deinit {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
    }

    // MARK: - Registration

    /// Registers the active banner token and a legacy point-only resolver.
    ///
    /// This API remains for backward compatibility and is internally
    /// adapted to the modern resolver.
    public func register(
        token: Int?,
        resolveVariantPoint: @escaping ResolveVariantPointHandler
    ) {
        register(token: token) { context in
            VariantResolution(targetPoint: resolveVariantPoint(context), horizontalLayout: nil)
        }
    }

    /// Registers the active banner token and the modern resolver.
    ///
    /// If `token` is `nil`, the coordinator state is cleared.
    public func register(
        token: Int?,
        resolveVariant: @escaping ResolveVariantHandler
    ) {
        guard let token else {
            clear()
            return
        }

        currentToken = token
        resolveHandler = resolveVariant
        standardHorizontalLayout = nil
    }

    // MARK: - Public API

    /// Handles a tap originating from the SwiftUI banner content.
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

    private func clear() {
        currentToken = nil
        resolveHandler = nil
        standardHorizontalLayout = nil
    }

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
            guard let resolution = resolvedVariant(for: token, state: state) else { return }

            // Apply optional alternate horizontal layout (external decision).
            if let layout = resolution.horizontalLayout {
                if standardHorizontalLayout == nil {
                    standardHorizontalLayout = state.payload.horizontalLayout
                }
                LucidBanner.shared.update(
                    payload: .init(horizontalLayout: layout),
                    for: token
                )
                LucidBanner.shared.requestRelayout(animated: false)
            }

            LucidBanner.shared.move(
                toX: resolution.targetPoint.x,
                y: resolution.targetPoint.y,
                for: token,
                animated: animated
            )
        } else {
            // Restore canonical position (and layout if we had overridden it).
            restoreStandardLayoutIfNeeded(token: token)
            LucidBanner.shared.resetPosition(for: token, animated: true)
        }
    }

    private func applyAlternateVariant(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        state.variant = .alternate

        // Disable dragging while using the alternate variant.
        LucidBanner.shared.setDraggingEnabled(false, for: token)

        guard let resolution = resolvedVariant(for: token, state: state) else {
            // Still remeasure because the SwiftUI view likely changed variant.
            LucidBanner.shared.requestRelayout(animated: false)
            return
        }

        // Apply optional alternate horizontal layout (external decision).
        if let layout = resolution.horizontalLayout {
            if standardHorizontalLayout == nil {
                standardHorizontalLayout = state.payload.horizontalLayout
            }
            LucidBanner.shared.update(
                payload: .init(horizontalLayout: layout),
                for: token
            )
        }

        // Re-measure alternate layout after variant/layout changes.
        LucidBanner.shared.requestRelayout(animated: false)

        // Move to externally resolved point.
        LucidBanner.shared.move(
            toX: resolution.targetPoint.x,
            y: resolution.targetPoint.y,
            for: token,
            animated: true
        )
    }

    private func applyStandardVariant(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        state.variant = .standard

        if state.payload.draggable {
            LucidBanner.shared.setDraggingEnabled(true, for: token)
        }

        // Restore canonical layout if the alternate variant overrode it.
        restoreStandardLayoutIfNeeded(token: token)

        // Re-measure standard layout.
        LucidBanner.shared.requestRelayout(animated: false)

        // Restore canonical position.
        LucidBanner.shared.resetPosition(for: token, animated: true)
    }

    private func restoreStandardLayoutIfNeeded(token: Int) {
        guard let standard = standardHorizontalLayout else { return }
        guard let state = LucidBanner.shared.currentState(for: token) else { return }

        if state.payload.horizontalLayout != standard {
            LucidBanner.shared.update(
                payload: .init(horizontalLayout: standard),
                for: token
            )
        }
    }

    private func resolvedVariant(
        for token: Int,
        state: LucidBannerState
    ) -> VariantResolution? {

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
