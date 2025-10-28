//
//  ToastBannerView.swift
//  LucidBannerDemo
//
//  Created by Marino Faggiana on 28/10/25.
//

import SwiftUI

/// Simple demo view for LucidBanner content.
/// Displays title, subtitle, footnote, icon and progress in a compact layout.
struct ToastBannerView: View {
    @ObservedObject var state: LucidBannerState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let systemImage = state.systemImage {
                iconView(systemImage: systemImage, style: state.imageAnimation)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.headline)
                    .foregroundColor(Color(state.textColor))

                if let subtitle = state.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(Color(state.textColor).opacity(0.8))
                }

                if let footnote = state.footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundColor(Color(state.textColor).opacity(0.6))
                }

                if let progress = state.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color(state.progressColor))
                        .frame(height: 3)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 4)
    }

    // Apply a concrete symbol effect per case to satisfy the generic constraint.
    @ViewBuilder
    private func iconView(systemImage: String, style: LucidBanner.LucidBannerAnimationStyle) -> some View {
        let base = Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .foregroundColor(Color(state.imageColor))

        switch style {
        case .none:
            base
        case .rotate:
            base.symbolEffect(.rotate, options: .repeat(.continuous))
        case .pulse:
            base.symbolEffect(.pulse, options: .repeat(.continuous))
        case .pulsebyLayer:
            base.symbolEffect(.pulse.byLayer, options: .repeat(.continuous))
        case .bounce:
            base.symbolEffect(.bounce, options: .repeat(.continuous))
        case .wiggle:
            // No dedicated wiggle on iOS 17; approximate with bounce.
            base.symbolEffect(.bounce, options: .repeat(.continuous))
        case .scale:
            // iOS 18+: scale exists; on iOS 17 you can simulate via animation if needed.
            base.symbolEffect(.scale.up, options: .repeat(.continuous))
        case .breathe:
            // Not a standard effect; approximate with variableColor for a subtle shimmer.
            base.symbolEffect(.variableColor, options: .repeat(.continuous))
        }
    }
}

#Preview {
    ToastBannerView(
        state: LucidBannerState(
            title: "Upload complete",
            subtitle: "3 files synced successfully",
            footnote: "Nextcloud demo banner",
            textColor: .white,
            systemImage: "checkmark.circle.fill",
            imageColor: .green,
            imageAnimation: .pulse,
            progress: 1.0,
            progressColor: .green,
            stage: "complete"
        )
    )
    .padding()
    .background(Color.black)
}
