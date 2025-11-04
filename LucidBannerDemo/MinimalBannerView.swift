import SwiftUI

/// Minimal, neutral banner content (initial view)
struct MinimalBannerView: View {
    let state: LucidBannerState

    var body: some View {
        HStack(spacing: 10) {
            if let symbol = state.systemImage {
                Image(systemName: symbol)
                    .imageScale(.large)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let title = state.title {
                    Text(title)
                        .font(.headline)
                }
                if let subtitle = state.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                }
                if let foot = state.footnote {
                    Text(foot)
                        .font(.footnote)
                        .opacity(0.8)
                }
                if let p = state.progress {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial) // neutral system material
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.6)
        )
        .shadow(radius: 10, y: 4)
    }
}

#Preview {
    MinimalBannerView(
        state: .init(
            title: "Preview Title",
            subtitle: "Subtitle",
            footnote: "Footnote",
            systemImage: "arrowshape.up.circle",
            imageAnimation: .none,
            progress: 0.4,
            stage: "preview"
        )
    )
    .padding()
}
