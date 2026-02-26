//
//  LucidBannerRegistry.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBannerRegistry provides scene-scoped instances of LucidBanner.
//
//  In multi-window environments (e.g. iPad), each UIWindowScene may host
//  its own independent banner state machine. The registry guarantees:
//
//  - One LucidBanner instance per UIWindowScene
//  - Isolation of token spaces and queues
//  - Deterministic behavior across multiple windows
//
//  The registry does not contain presentation logic.
//  It only manages LucidBanner instance lifecycles.
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

        let banner = LucidBanner()
        instances[id] = banner
        return banner
    }

    public func remove(for scene: UIWindowScene) {
        let id = scene.session.persistentIdentifier
        instances[id] = nil
    }
}
