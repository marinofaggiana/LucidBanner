//
//  LucidBannerVariantCoordinator
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  UI-agnostic coordinator that toggles a single active `LucidBanner`
//  between standard and alternate visual variants.
//
//  The banner remains the same logical entity.
//  Only the active variant and on-screen position change.
//
//  Variant positioning is resolved externally via a mandatory resolver
//  closure, keeping the coordinator independent from app-specific layout.
//

@preconcurrency import UIKit

/// Coordinator responsible for switching a `LucidBanner`
/// between its standard and alternate visual variants.
///
/// The coordinator does not present UI and does not modify banner payloads.
/// It operates only on an already-presented banner, identified by a token.
///
/// Responsibilities:
/// - Track a single active banner token.
/// - Toggle the banner variant (`standard` / `alternate`).
/// - Move the banner to an externally-resolved target position.
/// - Re-apply positioning after orientation or layout changes.
///
/// Notes:
/// - The coordinator is intentionally UI-agnostic.
/// - All layout decisions are resolved outside the library.
/// - SwiftUI views remain passive and state-driven.
@MainActor
public final class LucidBannerVariantCoordinator {

    /// Shared singleton instance.
    public static let shared = LucidBannerVariantCoordinator()

    // MARK: - Types

    /// Context passed to the external variant resolver.
    ///
    /// All coordinates are expressed in window space.
    public struct ResolveContext {
        public let token: Int
        public let state: LucidBannerState
        public let hostView: UIView
        public let window: UIWindow
        public let bounds: CGRect
        public let safeAreaInsets: UIEdgeInsets
    }

    /// Resolver used to compute the target position
    /// for the alternate banner variant.
    ///
    /// The returned point must be expressed in window coordinates.
    public typealias ResolveVariantPointHandler =
        @MainActor (_ context: ResolveContext) -> CGPoint

    // MARK: - Stored Properties

    /// Currently tracked banner token.
    private var currentToken: Int?

    /// Resolver for alternate variant positioning.
    private var resolveHandler: ResolveVariantPointHandler?

    /// Orientation change observer token.
    private var orientationObserver: NSObjectProtocol?

    // MARK: - Initialization

    /// Creates the coordinator and installs an orientation-change observer.
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

    deinit {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
    }

    // MARK: - Registration

    /// Registers the active banner token and the variant-position resolver.
    ///
    /// If `token` is `nil`, the coordinator state is cleared.
    public func register(token: Int?, resolveVariantPoint: @escaping ResolveVariantPointHandler) {
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
    /// Toggles between standard and alternate variants.
    public func handleTap(_ state: LucidBannerState) {
        guard let token = currentToken else {
            return
        }

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
    }

    private func refreshPosition(animated: Bool = true) {
        guard let token = currentToken else { return }

        guard LucidBanner.shared.isAlive(token),
              let state = LucidBanner.shared.currentState(for: token) else {
            clear()
            return
        }

        if state.variant == .alternate,
           let target = resolvedVariantPoint(for: token, state: state) {
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

    private func applyAlternateVariant(_ state: LucidBannerState) {
        guard let token = currentToken else {
            return
        }

        state.variant = .alternate
        LucidBanner.shared.setDraggingEnabled(false, for: token)
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

    private func applyStandardVariant(_ state: LucidBannerState) {
        guard let token = currentToken else {
            return
        }

        state.variant = .standard

        if state.payload.draggable {
            LucidBanner.shared.setDraggingEnabled(true, for: token)
        }

        LucidBanner.shared.requestRelayout(animated: false)
        LucidBanner.shared.resetPosition(for: token, animated: true)
    }

    private func resolvedVariantPoint(for token: Int, state: LucidBannerState) -> CGPoint? {
        guard let resolveHandler,
              let hostView = LucidBanner.shared.currentHostView(for: token),
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
