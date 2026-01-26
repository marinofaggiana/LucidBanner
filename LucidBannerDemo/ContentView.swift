//
//  LucidBanner
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//

import SwiftUI

struct ContentView: View {

    /// Returns the current active UIWindowScene (iOS 17+).
    private var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    @State private var lastToken: Int?

    var body: some View {
        VStack(spacing: 20) {
            Button("Show Top Banner") {
                guard let scene = activeScene else { return }

                let payload = LucidBannerPayload(
                    title: "Uploading…",
                    subtitle: "Keep the app active",
                    systemImage: "arrowshape.up.circle",
                    imageAnimation: .breathe,
                    vPosition: .top,
                    autoDismissAfter: 3.0
                )
                lastToken = LucidBanner.shared.show(scene: scene,
                                                    payload: payload) { state in
                    MinimalBannerView(state: state)
                }
            }

            Button("Show Bottom Banner") {
                guard let scene = activeScene else { return }

                let payload = LucidBannerPayload(
                    title: "Completed",
                    footnote: "All done!",
                    systemImage: "checkmark.circle.fill",
                    vPosition: .bottom,
                    autoDismissAfter: 2.0
                )
                lastToken = LucidBanner.shared.show(scene: scene,
                                        payload: payload) { state in
                    MinimalBannerView(state: state)
                }
            }

            Button("Update Progress") {
                var update = LucidBannerPayload.Update()
                update.progress = .value(0.75)
                LucidBanner.shared.update(payload: update, for: lastToken)
            }

            Button("Dismiss") {
                LucidBanner.shared.dismiss()
            }
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}

#Preview {
    ContentView()
}
