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

    @MainActor
    private func banner(for scene: UIWindowScene) -> LucidBanner {
        if let banner {
            return banner
        }

        let banner = LucidBannerRegistry.shared.banner(for: scene)
        self.banner = banner
        return banner
    }

    @State private var lastToken: Int?
    @State private var banner: LucidBanner?

    var body: some View {
        VStack(spacing: 20) {
            Button("Show Top Banner") {
                guard let scene = activeScene else { return }
                let banner = banner(for: scene)

                let payload = LucidBannerPayload(
                    title: "Uploading…",
                    subtitle: "Keep the app active",
                    systemImage: "arrowshape.up.circle",
                    imageAnimation: .breathe,
                    vPosition: .top
                )
                lastToken = banner.show(
                    payload: payload
                ) { state in
                    MinimalBannerView(state: state)
                }
            }

            Button("Show Bottom Banner") {
                guard let scene = activeScene else { return }
                let banner = banner(for: scene)

                let payload = LucidBannerPayload(
                    title: "Completed",
                    footnote: "All done!",
                    systemImage: "checkmark.circle.fill",
                    vPosition: .bottom,
                    autoDismissAfter: 2.0
                )
                lastToken = banner.show(
                    payload: payload
                ) { state in
                    MinimalBannerView(state: state)
                }
            }

            Button("Progress") {
                guard let scene = activeScene else { return }
                let banner = banner(for: scene)

                let payload = LucidBannerPayload(
                    title: "Uploading…",
                    subtitle: "Uploading file",
                    systemImage: "arrowshape.up.circle",
                    imageAnimation: .breathe,
                    progress: 0,
                    vPosition: .top
                )

                let token = banner.show(payload: payload) { state in
                    MinimalBannerView(state: state)
                }
                lastToken = token

                Task { @MainActor in
                    for value in stride(from: 0.0, through: 1.0, by: 0.05) {
                        guard banner.isAlive(token) else { return }

                        banner.update(
                            payload: LucidBannerPayload.Update(
                                subtitle: "Uploading \(Int(value * 100))%",
                                progress: value
                            ),
                            for: token
                        )

                        try? await Task.sleep(for: .milliseconds(150))
                    }

                    guard banner.isAlive(token) else { return }
                    banner.update(
                        payload: LucidBannerPayload.Update(
                            title: "Upload completed",
                            subtitle: "100%",
                            systemImage: "checkmark.circle.fill",
                            progress: 1
                        ),
                        for: token
                    )

                    try? await Task.sleep(for: .milliseconds(500))
                    guard banner.isAlive(token) else { return }
                    banner.dismiss()
                }
            }

            Button("Dismiss") {
                guard let scene = activeScene else { return }
                let banner = banner(for: scene)
                banner.dismiss()
            }
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}

#Preview {
    ContentView()
}
