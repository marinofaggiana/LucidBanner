//
//  Untitled.swift
//  LucidBannerDemo
//
//  Created by Marino Faggiana on 31/10/25.
//

import SwiftUI

/// Success variant shown after `update` replaces the content
struct MinimalBannerSuccessView: View {
    let state: LucidBannerState

    var body: some View {
        HStack(spacing: 10) {
            if let symbol = state.systemImage {
                Image(systemName: symbol)
                    .imageScale(.large)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title.isEmpty ? " " : state.title)
                    .font(.headline)
                if let subtitle = state.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(radius: 12, y: 5)
    }
}

#Preview {
    MinimalBannerSuccessView(
        state: .init(
            title: "Completed",
            subtitle: "Everything is safe",
            systemImage: "checkmark.circle",
            imageAnimation: .none,
            progress: nil,
            stage: "preview-success"
        )
    )
    .padding()
}
