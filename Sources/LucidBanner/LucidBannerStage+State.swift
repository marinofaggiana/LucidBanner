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

import Foundation

public extension LucidBannerState {
    var typedStage: LucidBanner.Stage? {
        guard let stage else { return nil }
        return LucidBanner.Stage(rawValue: stage)
    }
}
