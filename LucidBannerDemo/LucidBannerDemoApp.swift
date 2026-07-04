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
//  Architecture:
//  - `LucidBannerRegistry` owns one `LucidBanner` instance per `UIWindowScene`.
//  - Each `LucidBanner` manages presentation, queueing, scheduling and dismissal
//    for its scene.
//  - `LucidBannerState` exposes observable UI data to the SwiftUI banner content.
//  - A lightweight `UIWindow` subclass hosts the SwiftUI banner above the scene.
//  - Each presentation request is identified by a token.
//
//  Notes:
//  Designed to be lightweight and non-intrusive. SwiftUI content renders
//  `LucidBannerState`; scene lifecycle and presentation coordination remain
//  in the banner and registry layers.
//

import SwiftUI

@main
struct LucidBannerDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
