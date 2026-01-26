//
//  LucidBannerState.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBannerState is the shared, observable state model driving all
//  SwiftUI rendering for a LucidBanner instance.
//
//  This object represents the *single source of truth* for banner UI.
//  SwiftUI views are pure functions of this state and never initiate
//  presentation, dismissal, or side effects on their own.
//
//  The state is owned and mutated exclusively by `LucidBanner`
//  (and its coordinators) and injected into SwiftUI content
//  for both initial rendering and live updates.
//
//  Design principles:
//  - Observable, but not autonomous.
//  - Mutable only on the MainActor.
//  - Safe to subclass for app-specific extensions.
//  - No presentation logic or UIKit coupling.
//

import SwiftUI
import Combine

/// Shared observable state used by LucidBanner SwiftUI content.
///
/// `LucidBannerState` is intentionally minimal and declarative.
/// It does not perform any actions; it only exposes data that
/// describes *what* the banner should render.
///
/// Responsibilities:
/// - Expose the current banner payload to SwiftUI.
/// - Expose derived UI flags (e.g. variant state).
/// - Act as the bridge between the LucidBanner state machine
///   and passive SwiftUI views.
///
/// Ownership:
/// - Instances are created and owned by `LucidBanner`.
/// - SwiftUI views must never retain or create their own state instances.
@MainActor
open class LucidBannerState: ObservableObject {

    /// Complete banner configuration snapshot.
    ///
    /// This payload is the canonical representation of banner state.
    /// Any change to this value triggers a SwiftUI re-render.
    ///
    /// Mutations are performed by `LucidBanner` via explicit update APIs.
    @Published public var payload: LucidBannerPayload

    /// Indicates which visual representation of the banner is currently active.
    ///
    /// This flag does **not** imply a reduction, collapse, or hierarchy change.
    /// It simply represents an alternate visual variant of the same banner,
    /// selected by the banner system.
    ///
    /// The value is managed internally by LucidBanner
    /// (e.g. via a coordinator) and must be treated as read-only
    /// by SwiftUI views.
    ///
    /// SwiftUI content may *react* to this value
    /// (e.g. switch between different visual layouts or styles),
    /// but must not toggle it directly.
    public enum BannerVariant {
        case standard
        case alternate
    }
    @Published var variant: BannerVariant = .standard

    /// Creates a new banner state with an initial payload.
    ///
    /// - Parameter payload: Initial full configuration snapshot.
    public init(payload: LucidBannerPayload) {
        self.payload = payload
    }
}
