//
//  LucidBannerMinimizeCoordinator.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Description:
//  Generic minimization coordinator for LucidBanner.
//  Manages per-token minimized state, anchor positions and
//  automatic repositioning on orientation changes.
//

import Foundation
import UIKit

public extension LucidBanner {
    /// Logical anchor used when a banner is minimized.
    ///
    /// This describes *where* the minimized bubble should be placed
    /// inside the window coordinate space.
    enum MinimizeAnchor: Equatable {
        /// Absolute point in window coordinates.
        case absolute(CGPoint)

        /// Attach to one of the window corners with a given inset.
        case corner(Corner, inset: CGSize = CGSize(width: 20, height: 40))

        /// Supported corners for minimized placement.
        public enum Corner {
            case topLeading
            case topTrailing
            case bottomLeading
            case bottomTrailing
        }
    }
}

/// Coordinator that manages minimized positions for LucidBanner tokens.
///
/// This type is intentionally generic and independent from any specific
/// use case (e.g. upload, download, etc.). It tracks:
/// - the original center of each banner before minimization
/// - the configured minimize anchor (absolute or corner) per token
/// - automatic repositioning on device orientation changes
///
/// Usage pattern:
/// - When a banner token is created, call `register(token:anchor:)`.
/// - When the user taps the banner, call `toggleMinimize(for:)`.
/// - When the banner is dismissed, call `clear(token:)`.
@MainActor
public final class LucidBannerMinimizeCoordinator {
    public static let shared = LucidBannerMinimizeCoordinator()

    // MARK: - Types

    /// Internal state for a single banner token.
    private struct Entry {
        var originalCenter: CGPoint?
        var anchor: LucidBanner.MinimizeAnchor?
    }

    // MARK: - Stored properties

    private var entries: [Int: Entry] = [:]
    private var orientationObserver: NSObjectProtocol?

    // MARK: - Init

    /// Creates a new coordinator and registers for orientation changes.
    public init() {
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                self.refreshAllMinimizedPositions(animated: true)
            }
        }
    }

    // MARK: - Public API

    /// Registers a banner token to be handled by the minimization system.
    ///
    /// - Parameters:
    ///   - token: The banner token returned by `LucidBanner.shared.show(...)`.
    ///   - anchor: Optional anchor describing where the banner should be placed
    ///             when minimized. Can be updated later via `setAnchor(_:for:)`.
    public func register(token: Int, anchor: LucidBanner.MinimizeAnchor? = nil) {
        entries[token] = Entry(originalCenter: nil, anchor: anchor)
    }

    /// Updates or clears the minimize anchor for a given token.
    ///
    /// - Parameters:
    ///   - anchor: New anchor to apply. Pass `nil` to remove any anchor.
    ///   - token: The banner token to update.
    public func setAnchor(_ anchor: LucidBanner.MinimizeAnchor?, for token: Int) {
        guard var entry = entries[token] else {
            return
        }

        entry.anchor = anchor
        entries[token] = entry
    }

    /// Clears all tracked state for a given banner token.
    ///
    /// - Parameter token: The banner token to forget.
    public func clear(token: Int) {
        entries[token] = nil
    }

    /// Clears all tracked tokens and their associated state.
    public func clearAll() {
        entries.removeAll()
    }

    /// Toggles the minimized state of the banner associated with the token.
    ///
    /// If the banner is currently minimized, it will be restored to its
    /// original position (or reset if the original position is unknown).
    /// If the banner is currently expanded, it will be minimized and moved
    /// to the configured anchor, if any.
    ///
    /// - Parameter token: The banner token to toggle.
    public func toggleMinimize(for token: Int) {
        guard LucidBanner.shared.isAlive(token),
              let state = LucidBanner.shared.currentState(for: token)
        else {
            clear(token: token)
            return
        }

        if state.isMinimized {
            maximize(state: state, token: token)
        } else {
            minimize(state: state, token: token)
        }
    }

    /// Forces minimization of a banner, if it is alive.
    ///
    /// - Parameter token: The banner token to minimize.
    public func minimize(token: Int) {
        guard LucidBanner.shared.isAlive(token),
              let state = LucidBanner.shared.currentState(for: token)
        else {
            clear(token: token)
            return
        }

        minimize(state: state, token: token)
    }

    /// Forces maximization of a banner, if it is alive.
    ///
    /// - Parameter token: The banner token to maximize.
    public func maximize(token: Int) {
        guard LucidBanner.shared.isAlive(token),
              let state = LucidBanner.shared.currentState(for: token)
        else {
            clear(token: token)
            return
        }

        maximize(state: state, token: token)
    }

    /// Repositions a minimized banner after layout changes, if needed.
    ///
    /// Call this when you know the window bounds or safe areas changed
    /// (for example on custom UI transitions) and you want minimized bubbles
    /// to snap to the correct position.
    ///
    /// - Parameters:
    ///   - token: The banner token to refresh.
    ///   - animated: Whether the movement should be animated.
    public func refreshMinimizedPosition(for token: Int, animated: Bool = true) {
        guard LucidBanner.shared.isAlive(token),
              let state = LucidBanner.shared.currentState(for: token),
              state.isMinimized
        else {
            if !LucidBanner.shared.isAlive(token) {
                clear(token: token)
            }
            return
        }

        guard let entry = entries[token],
              let target = resolvedMinimizePoint(for: token, entry: entry)
        else {
            return
        }

        LucidBanner.shared.move(
            toX: target.x,
            y: target.y,
            for: token,
            animated: animated
        )
    }

    // MARK: - Internal helpers

    /// Refreshes positions for all minimized banners after orientation changes.
    ///
    /// - Parameter animated: Whether movements should be animated.
    private func refreshAllMinimizedPositions(animated: Bool) {
        for (token, entry) in entries {
            guard LucidBanner.shared.isAlive(token),
                  let state = LucidBanner.shared.currentState(for: token),
                  state.isMinimized
            else {
                if !LucidBanner.shared.isAlive(token) {
                    clear(token: token)
                }
                continue
            }

            guard let target = resolvedMinimizePoint(for: token, entry: entry) else {
                continue
            }

            LucidBanner.shared.move(
                toX: target.x,
                y: target.y,
                for: token,
                animated: animated
            )
        }
    }

    /// Applies minimization logic to a given state and token.
    ///
    /// - Parameters:
    ///   - state: The shared `LucidBannerState` for the token.
    ///   - token: The banner token to minimize.
    private func minimize(state: LucidBannerState, token: Int) {
        var entry = entries[token] ?? Entry(originalCenter: nil, anchor: nil)

        if let frame = LucidBanner.shared.currentFrameInWindow(for: token) {
            entry.originalCenter = CGPoint(x: frame.midX, y: frame.midY)
        }

        state.isMinimized = true
        entries[token] = entry

        LucidBanner.shared.setDraggingEnabled(false, for: token)
        LucidBanner.shared.requestRelayout(animated: true)

        if let target = resolvedMinimizePoint(for: token, entry: entry) {
            LucidBanner.shared.move(
                toX: target.x,
                y: target.y,
                for: token,
                animated: true
            )
        }
    }

    /// Applies maximization logic to a given state and token.
    ///
    /// - Parameters:
    ///   - state: The shared `LucidBannerState` for the token.
    ///   - token: The banner token to maximize.
    private func maximize(state: LucidBannerState, token: Int) {
        guard var entry = entries[token] else {
            state.isMinimized = false
            LucidBanner.shared.setDraggingEnabled(true, for: token)
            LucidBanner.shared.requestRelayout(animated: true)
            LucidBanner.shared.resetPosition(for: token, animated: true)
            return
        }

        state.isMinimized = false

        LucidBanner.shared.setDraggingEnabled(true, for: token)
        LucidBanner.shared.requestRelayout(animated: true)

        if let center = entry.originalCenter {
            LucidBanner.shared.move(
                toX: center.x,
                y: center.y,
                for: token,
                animated: true
            )
        } else {
            LucidBanner.shared.resetPosition(for: token, animated: true)
        }

        entry.originalCenter = nil
        entries[token] = entry
    }

    /// Resolves the minimized anchor point in window coordinates for a given token.
    ///
    /// - Parameters:
    ///   - token: The banner token.
    ///   - entry: The entry containing anchor information.
    /// - Returns: The resolved point in window coordinates, or `nil` if not available.
    private func resolvedMinimizePoint(for token: Int, entry: Entry) -> CGPoint? {
        guard let anchor = entry.anchor else {
            return nil
        }
        guard let hostView = LucidBanner.shared.currentHostView(for: token),
              let window = hostView.window else {
            return nil
        }

        let bounds = window.bounds

        switch anchor {
        case .absolute(let point):
            return point

        case .corner(let corner, let inset):
            switch corner {
            case .topLeading:
                return CGPoint(
                    x: bounds.minX + inset.width,
                    y: bounds.minY + inset.height
                )
            case .topTrailing:
                return CGPoint(
                    x: bounds.maxX - inset.width,
                    y: bounds.minY + inset.height
                )
            case .bottomLeading:
                return CGPoint(
                    x: bounds.minX + inset.width,
                    y: bounds.maxY - inset.height
                )
            case .bottomTrailing:
                return CGPoint(
                    x: bounds.maxX - inset.width,
                    y: bounds.maxY - inset.height
                )
            }
        }
    }
}
