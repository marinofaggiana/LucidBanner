//
//  LucidBanner
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//

import SwiftUI

/// Minimal SwiftUI banner content showcasing the LucidBannerState.
/// Neutral style, suitable for testing and demos.
struct MinimalBannerView: View {
    @ObservedObject var state: LucidBannerState

    var body: some View {
        HStack(spacing: 10) {
            if let symbol = state.payload.systemImage {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                if let title = state.payload.title {
                    Text(title)
                        .font(.headline)
                }

                if let subtitle = state.payload.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let footnote = state.payload.footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let progress = state.payload.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.20), lineWidth: 0.5)
        )
        .shadow(radius: 8, y: 4)
    }
}

#Preview {
    let payload = LucidBannerPayload(title: "Preview Title",
                                     subtitle: "Subtitle",
                                     footnote: "Footnote",
                                     systemImage: "arrowshape.up.circle",
                                     imageAnimation: .none,
                                     progress: 0.4,
                                     stage: .none)
    MinimalBannerView(
        state: LucidBannerState(payload: payload)
    )
    .padding()
}
