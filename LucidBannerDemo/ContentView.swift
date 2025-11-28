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
//  - `LucidBanner.shared` manages lifecycle, queuing, scheduling and dismissal.
//  - `LucidBannerState` exposes observable UI data to SwiftUI.
//  - A lightweight UIWindow subclass hosts the SwiftUI banner above all scenes.
//  - Only a single state object is reused; each banner is identified by a token.
//
//  Notes:
//  Designed to be lightweight and non-intrusive. No View contains presentation
//  logic; all coordination is handled by the manager layer.
//

import SwiftUI

struct ContentView: View {

    /// Returns the current active UIWindowScene (iOS 17+).
    private var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    @State private var lastToken: Int = 0

    var body: some View {
        VStack(spacing: 20) {

            Button("Show Top Banner") {
                guard let scene = activeScene else { return }

                lastToken = LucidBanner.shared.show(
                    scene: scene,
                    title: "Uploading…",
                    subtitle: "Keep the app active",
                    systemImage: "arrowshape.up.circle",
                    imageAnimation: .breathe,
                    vPosition: .top,
                    autoDismissAfter: 3.0,
                    onTap: { token, stage in
                        print("Tapped banner token:", token, "stage:", stage ?? "nil")
                    }
                ) { state in
                    MinimalBannerView(state: state)
                }
            }

            Button("Show Bottom Banner") {
                guard let scene = activeScene else { return }

                lastToken = LucidBanner.shared.show(
                    scene: scene,
                    title: "Completed",
                    footnote: "All done!",
                    systemImage: "checkmark.circle.fill",
                    vPosition: .bottom,
                    autoDismissAfter: 2.0
                ) { state in
                    MinimalBannerView(state: state)
                }
            }

            Button("Update Progress") {
                LucidBanner.shared.update(
                    progress: 0.75,
                    stage: "uploading",
                    for: lastToken
                )
            }

            Button("Dismiss") {
                LucidBanner.shared.dismiss(for: lastToken)
            }
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}

#Preview {
    ContentView()
}
