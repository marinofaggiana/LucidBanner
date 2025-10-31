import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Button("Show, then Update with New View") {
                // Show a first banner with the minimal view
                let token = LucidBanner.shared.show(
                    title: "Uploading…",
                    subtitle: "Keep the app in foreground",
                    systemImage: "arrowshape.up.circle",
                    vPosition: .top,
                    autoDismissAfter: 0
                ) { state in
                    MinimalBannerView(state: state)
                }

                // After 2 seconds, replace the SwiftUI content via `update`
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)

                    // Guard that the same banner is still visible
                    guard LucidBanner.shared.isAlive(token) else { return }

                    LucidBanner.shared.update(
                        title: "Completed",
                        subtitle: "Everything is safe",
                        systemImage: "checkmark.circle",
                        for: token
                    ) { state in
                        MinimalBannerSuccessView(state: state)
                    }
                }
            }

            Button("Show Bottom (auto-dismiss)") {
                _ = LucidBanner.shared.show(
                    title: "All done",
                    footnote: "Thanks!",
                    systemImage: "checkmark.seal",
                    vPosition: .bottom,
                    autoDismissAfter: 2.0
                ) { state in
                    MinimalBannerView(state: state)
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}

#Preview {
    ContentView()
}
