//
//  LucidBannerVariantCoordinator
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//

@preconcurrency import UIKit

/// UI-agnostic coordinator responsible for toggling a single active
/// `LucidBanner` between standard and alternate variants.
///
/// The coordinator does not decide layout or behavior.
/// All variant-specific decisions are resolved externally via a resolver.
@MainActor
public final class LucidBannerVariantCoordinator {
    public static let shared = LucidBannerVariantCoordinator()

    /// Context passed to the external resolver.
    /// All coordinates are expressed in window space.
    public struct ResolveContext {
        public let token: Int
        public let state: LucidBannerState
        public let hostView: UIView
        public let window: UIWindow
        public let bounds: CGRect
        public let safeAreaInsets: UIEdgeInsets
    }

    /// Resolution for the alternate variant.
    ///
    /// - `targetPoint` is mandatory and expressed in window coordinates.
    /// - `payloadUpdate` is optional and applied when entering the alternate variant.
    public struct VariantResolution {
        public let targetPoint: CGPoint
        public let payloadUpdate: LucidBannerPayload.Update?

        public init(
            targetPoint: CGPoint,
            payloadUpdate: LucidBannerPayload.Update? = nil
        ) {
            self.targetPoint = targetPoint
            self.payloadUpdate = payloadUpdate
        }
    }

    /// External resolver defining alternate-variant behavior.
    public typealias ResolveVariantHandler =
        @MainActor (_ context: ResolveContext) -> VariantResolution

    // MARK: - Stored Properties

    private var currentToken: Int?
    private var resolveHandler: ResolveVariantHandler?
    private var orientationObserver: NSObjectProtocol?
    private var standardPayloadSnapshot: LucidBannerPayload?

    // MARK: - Initialization

    init() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
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

    /// Registers the active banner token and the external variant resolver.
    ///
    /// If `token` is `nil`, the coordinator state is cleared.
    public func register(token: Int?, resolveVariant: @escaping ResolveVariantHandler) {
        guard let token else {
            clear()
            return
        }

        currentToken = token
        resolveHandler = resolveVariant
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
        case .standard:
            applyAlternateVariant(state)

        case .alternate:
            applyStandardVariant(state)
        }
    }

    // MARK: - Internal Helpers

    private func clear() {
        currentToken = nil
        resolveHandler = nil
        standardPayloadSnapshot = nil
    }

    private func refreshPosition(animated: Bool) {
        guard let token = currentToken else { return }
        guard LucidBanner.shared.isAlive(token) else {
            clear()
            return
        }

        guard let state = LucidBanner.shared.currentState(for: token) else { return }

        if state.variant == .alternate {
            guard let resolution = resolvedVariant(for: token, state: state) else { return }

            LucidBanner.shared.move(
                toX: resolution.targetPoint.x,
                y: resolution.targetPoint.y,
                for: token,
                animated: animated
            )
        } else {
            LucidBanner.shared.resetPosition(for: token, animated: true)
        }
    }

    private func applyAlternateVariant(_ state: LucidBannerState) {
        guard let token = currentToken else { return }
        guard let resolution = resolvedVariant(for: token, state: state) else { return }

        state.variant = .alternate

        if standardPayloadSnapshot == nil {
            standardPayloadSnapshot = state.payload
        }

        // Apply externally resolved payload update (if any)
        if let update = resolution.payloadUpdate {
            LucidBanner.shared.update(payload: update, for: token)
        }

        // Disable dragging while minimized
        LucidBanner.shared.setDraggingEnabled(false, for: token)

        LucidBanner.shared.requestRelayout(animated: false)

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

        if let snapshot = standardPayloadSnapshot {
            LucidBanner.shared.update(
                payload: .init(from: snapshot),
                for: token
            )
            standardPayloadSnapshot = nil
        }

        if state.payload.draggable {
            LucidBanner.shared.setDraggingEnabled(true, for: token)
        }

        LucidBanner.shared.requestRelayout(animated: false)
        LucidBanner.shared.resetPosition(for: token, animated: true)
    }

    private func resolvedVariant(for token: Int, state: LucidBannerState) -> VariantResolution? {
        guard let resolveHandler else {
            return nil
        }
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
