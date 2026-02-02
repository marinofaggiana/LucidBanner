//
//  LucidBannerState.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  Shared observable state driving all SwiftUI rendering
//  for a LucidBanner instance.
//
//  This object is the single source of truth for banner UI.
//  SwiftUI views are pure functions of this state and never
//  initiate presentation, dismissal, or side effects.
//

import SwiftUI
import Combine

//// Observable state injected into LucidBanner SwiftUI content.
///
/// `LucidBannerState` is declarative and passive:
/// it exposes *what* should be rendered, not *how* or *when*.
///
/// The state is owned and mutated exclusively by `LucidBanner`
/// (and its internal coordinators).
@MainActor
open class LucidBannerState: ObservableObject {

    /// Complete banner configuration snapshot.
    ///
    /// Any change triggers a SwiftUI re-render.
    /// Mutations are performed via `LucidBanner` update APIs.
    @Published public var payload: LucidBannerPayload

    /// Active visual variant of the banner.
    ///
    /// This flag represents an alternate visual representation
    /// of the same banner, not a hierarchy or lifecycle change.
    ///
    /// SwiftUI views may react to this value, but must not
    /// mutate it directly.
    public enum BannerVariant {
        case standard
        case alternate
    }

    /// Current banner variant.
    @Published public var variant: BannerVariant = .standard

    /// Creates a new banner state with an initial payload.
    public init(payload: LucidBannerPayload) {
        self.payload = payload
    }
}
