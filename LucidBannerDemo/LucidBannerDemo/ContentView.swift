//
//  ContentView.swift
//  LucidBannerDemo
//
//  Created by Marino Faggiana on 28/10/25.
//

import SwiftUI

// MARK: - Previews

#if DEBUG
private func makeMockState(
    title: String = "Upload started",
    subtitle: String? = "Keep the app in foreground",
    footnote: String? = nil,
    systemImage: String? = "arrowshape.up.circle",
    progress: Double? = 0.35,
    stage: String? = "uploading"
) -> LucidBannerState {
    // Create a standalone state for previews. This does not touch the singleton.
    LucidBannerState(
        title: title,
        subtitle: subtitle,
        footnote: footnote,
        systemImage: systemImage,
        imageAnimation: .breathe,
        progress: progress,
        stage: stage
    )
}

/// Shows the "toast" style banner with mock data.
struct ToastBannerView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ToastBannerView(state: makeMockState())
                .previewLayout(.sizeThatFits)
                .padding()
                .previewDisplayName("Toast • Light")

            ToastBannerView(state: makeMockState())
                .previewLayout(.sizeThatFits)
                .padding()
                .preferredColorScheme(.dark)
                .previewDisplayName("Toast • Dark")
        }
    }
}

/// Shows the "success" style banner with mock data.
struct SuccessBannerView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SuccessBannerView(
                state: makeMockState(
                    title: "Upload complete",
                    subtitle: nil,
                    footnote: "All files are now safe in the cloud",
                    systemImage: "checkmark.seal.fill",
                    progress: 1.0,
                    stage: "done"
                )
            )
            .previewLayout(.sizeThatFits)
            .padding()
            .previewDisplayName("Success • Light")

            SuccessBannerView(
                state: makeMockState(
                    title: "Upload complete",
                    subtitle: nil,
                    footnote: "All files are now safe in the cloud",
                    systemImage: "checkmark.seal.fill",
                    progress: 1.0,
                    stage: "done"
                )
            )
            .previewLayout(.sizeThatFits)
            .padding()
            .preferredColorScheme(.dark)
            .previewDisplayName("Success • Dark")
        }
    }
}

/// Preview for the ContentView layout. Note: window-based banners won't render in previews.
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .padding()
            .previewDisplayName("ContentView")
    }
}
#endif
