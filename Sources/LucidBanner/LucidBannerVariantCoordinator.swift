//
//  LucidBannerVariantCoordinator
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  UI-agnostic coordinator that toggles a single active LucidBanner between
//  standard and alternate visual variants.
//
//  Variant behavior is resolved externally:
//  - The alternate target point is mandatory (window coordinates).
//  - The alternate horizontal layout is optional (applied via LucidBanner.update).
//

@preconcurrency import UIKit

@MainActor
public final class LucidBannerVariantCoordinator {

    // MARK: - Singleton

    public static let shared = LucidBannerVariantCoordinator()

    // MARK: - Types

    /// Context passed to the external resolver.
    /// All coordinates are in window space.
    public struct ResolveContext {
        public let token: Int
        public let state: LucidBannerState
        public let hostView: UIView
        public let window: UIWindow
        public let bounds: CGRect
        public let safeAreaInsets: UIEdgeInsets
    }

    /// Resolver result for the alternate variant.
    /// - `targetPoint` is mandatory (window coordinates).
    /// - `horizontalLayout` is optional; when present it overrides the current layout.
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

    /// Modern resolver that returns the full alternate resolution.
    public typealias ResolveVariantHandler =
        @MainActor (_ context: ResolveContext) -> VariantResolution

    // MARK: - Stored Properties

    private var currentToken: Int?
    private var resolveHandler: ResolveVariantHandler?

    /// Cached standard layout, captured right before applying an alternate layout override.
    /// Cleared after restoration.
    private var standardHorizontalLayout: LucidBanner.HorizontalLayout?

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
                // Allow UIKit layout to stabilize before recomputing.
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

    /// Registers with a legacy point-only resolver.
    /// Internally adapted to the modern resolver.
    public func register(
        token: Int?,
        resolveVariantPoint: @escaping ResolveVariantPointHandler
    ) {
        register(token: token) { context in
            VariantResolution(
                targetPoint: resolveVariantPoint(context),
                horizontalLayout: nil
            )
        }
    }

    /// Registers with the modern resolver.
    /// If `token` is nil, coordinator state is cleared.
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

    /// Handles a tap coming from the SwiftUI banner content.
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

        guard let state = LucidBanner.shared.currentState(for: token) else { return }

        if state.variant == .alternate {
            guard let resolution = resolvedVariant(for: token, state: state) else { return }

            // Keep alternate positioning valid on rotation/layout changes.
            // Horizontal layout override (if any) is also refreshed.
            if let layout = resolution.horizontalLayout {
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
            // Restore canonical position (and layout if overridden).
            restoreStandardLayoutIfNeeded(token: token, clearCache: true)
            LucidBanner.shared.resetPosition(for: token, animated: true)
        }
    }

    private func applyAlternateVariant(_ state: LucidBannerState) {
        guard let token = currentToken else { return }

        // Capture current "standard" layout right before overriding it.
        let capturedStandardLayout = state.payload.horizontalLayout

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
            standardHorizontalLayout = capturedStandardLayout
            LucidBanner.shared.update(
                payload: .init(horizontalLayout: layout),
                for: token
            )
        }

        // Re-measure after variant/layout changes.
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

        // Restore canonical layout if the alternate variant overrode it.
        restoreStandardLayoutIfNeeded(token: token, clearCache: true)

        if state.payload.draggable {
            LucidBanner.shared.setDraggingEnabled(true, for: token)
        }

        // Re-measure standard layout.
        LucidBanner.shared.requestRelayout(animated: false)

        // Restore canonical position.
        LucidBanner.shared.resetPosition(for: token, animated: true)
    }

    private func restoreStandardLayoutIfNeeded(token: Int, clearCache: Bool) {
        guard let standard = standardHorizontalLayout else { return }
        guard let state = LucidBanner.shared.currentState(for: token) else { return }

        if state.payload.horizontalLayout != standard {
            LucidBanner.shared.update(
                payload: .init(horizontalLayout: standard),
                for: token
            )
        }

        if clearCache {
            standardHorizontalLayout = nil
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
