import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Button("Show Top") {
                LucidBanner.shared.show(
                    title: "Uploading…",
                    subtitle: "Keep the app in foreground",
                    systemImage: "arrowshape.up.circle",
                    vPosition: .top,
                    autoDismissAfter: 3.0
                ) { state in
                    MinimalBannerView(state: state)
                }
            }

            Button("Show Bottom") {
                LucidBanner.shared.show(
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
