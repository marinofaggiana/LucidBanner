//
//  LucidBannerRegistry.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBannerRegistry provides scene-scoped instances of LucidBanner.
//
//  In multi-window environments (e.g. iPadOS), each UIWindowScene
//  owns an independent LucidBanner state machine. The registry ensures:
//
//  - Exactly one LucidBanner instance per UIWindowScene
//  - Isolation of token generation and banner queues per scene
//  - Deterministic behavior when multiple windows are active
//
//  The registry contains no presentation, animation, or state logic.
//  It acts purely as a scene-to-banner mapping layer.
//
//  Lifecycle Model:
//  - Instances are created lazily on first access.
//  - Instances should be removed when a scene disconnects.
//  - The registry does not retain scene lifecycle responsibility;
//    it only mirrors scene existence.
//

import UIKit

@MainActor
public final class LucidBannerRegistry {
    public static let shared = LucidBannerRegistry()

    private var instances: [String: LucidBanner] = [:]

    public func banner(for scene: UIWindowScene) -> LucidBanner {
        let id = scene.session.persistentIdentifier

        if let existing = instances[id] {
            return existing
        }

        let banner = LucidBanner(scene: scene)
        instances[id] = banner
        return banner
    }

    public func remove(for scene: UIWindowScene) {
        let id = scene.session.persistentIdentifier
        instances[id] = nil
    }
}
