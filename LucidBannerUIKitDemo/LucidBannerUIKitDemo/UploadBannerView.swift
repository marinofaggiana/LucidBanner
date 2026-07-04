// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2025 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
//import LucidBanner

@MainActor
func showUploadBanner(scene: UIWindowScene?,
                      stage: LucidBanner.Stage? = nil,
                      onButtonTap: (() -> Void)? = nil) -> Int? {
    guard let scene else { return nil }

    let banner = LucidBannerRegistry.shared.banner(for: scene)
    let payload = LucidBannerPayload(
        title: "Uploading…",
        subtitle: "name.rtf",
        footnote: "(tap to minimize)",
        systemImage: "arrowshape.up.circle",
        progress: 0,
        stage: stage,
        vPosition: .top
    )

    let coordinator = LucidBannerVariantCoordinator(banner: banner)
    let token = banner.show(payload: payload, policy: .drop) { state in
        UploadBanner(
            state: state,
            coordinator: coordinator,
            allowMinimizeOnTap: true,
            onButtonTap: onButtonTap
        )
    }

    coordinator.register(token: token, resolveVariant: { context in
        let bounds = context.bounds
        let over: CGFloat = 30
        let regularLayout = context.window.rootViewController?.traitCollection.horizontalSizeClass == .regular
        let iPad = UIDevice.current.userInterfaceIdiom == .pad
        let height: CGFloat = iPad && regularLayout ? over : context.safeAreaInsets.bottom + over

        return LucidBannerVariantCoordinator.VariantResolution(
            targetPoint: CGPoint(x: bounds.midX, y: bounds.maxY - height)
        )
    })

    return token
}

// MARK: - SwiftUI

struct UploadBanner: View {
    @ObservedObject var state: LucidBannerState
    let coordinator: LucidBannerVariantCoordinator?
    @State var trigger = true
    let onButtonTap: (() -> Void)?
    let allowMinimizeOnTap: Bool
    let textColor = Color(.label)

    init(state: LucidBannerState,
         coordinator: LucidBannerVariantCoordinator? = nil,
         allowMinimizeOnTap: Bool = false,
         onButtonTap: (() -> Void)? = nil) {
        self.state = state
        self.coordinator = coordinator
        self.allowMinimizeOnTap = allowMinimizeOnTap
        self.onButtonTap = onButtonTap
    }

    var body: some View {
        let showTitle = !(state.payload.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let showSubtitle = !(state.payload.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let showFootnote = !(state.payload.footnote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        let isSuccess = (state.payload.stage == .success)
        let isError = (state.payload.stage == .error)
        let isButton = (state.payload.stage == .button)

        containerView(state: state) {
            if state.variant == .alternate {
                HStack(spacing: 5) {
                    Image(systemName: state.payload.systemImage ?? "arrow.up.circle")
                        .font(.body.weight(.medium))
                        .frame(width: 20, height: 20)

                    if let p = state.payload.progress {
                        Text("\(Int(p * 100))%")
                            .font(.caption2.monospacedDigit())
                            .frame(height: 20)
                            .foregroundStyle(textColor)
                    }

                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .clipShape(Capsule())
            } else if isSuccess {
                 HStack(alignment: .center, spacing: 10) {
                     if #available(iOS 26, *) {
                         Image(systemName: "checkmark")
                             .font(.system(size: 60, weight: .regular))
                             .foregroundStyle(.green)
                             .symbolEffect(.drawOn, isActive: trigger)
                             .task {
                                 try? await Task.sleep(for: .seconds(0.1))
                                 trigger = false
                             }
                     } else {
                         Image(systemName: "checkmark")
                             .font(.system(size: 80, weight: .regular))
                             .foregroundStyle(.green)
                     }
                 }
                 .padding(.horizontal, 20)
                 .padding(.vertical, 20)
            } else if isError {
                VStack(spacing: 15) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)

                        VStack(alignment: .leading, spacing: 7) {
                            Text("_error_")
                                .font(.subheadline.weight(.bold))
                                .multilineTextAlignment(.leading)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.9)
                                .foregroundStyle(textColor)
                            if showSubtitle, let subtitle = state.payload.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                    .truncationMode(.tail)
                                    .foregroundStyle(textColor)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 15) {
                    HStack(alignment: .center, spacing: 10) {
                        if let systemImage = state.payload.systemImage {
                            Image(systemName: systemImage)
                                .applyBannerAnimation(state.payload.imageAnimation)
                                .font(.system(size: 30, weight: .regular))
                                .foregroundStyle(Color(uiColor: .blue))
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            if showTitle, let title = state.payload.title {
                                Text(title)
                                    .font(.subheadline.weight(.bold))
                                    .multilineTextAlignment(.leading)
                                    .truncationMode(.tail)
                                    .minimumScaleFactor(0.9)
                                    .foregroundStyle(textColor)
                            }
                            if showSubtitle, let subtitle = state.payload.subtitle {
                                Text(subtitle)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                    .truncationMode(.tail)
                                    .foregroundStyle(textColor)
                            }
                            if showFootnote, let footnote = state.payload.footnote {
                                Text(footnote)
                                    .font(.caption)
                                    .multilineTextAlignment(.leading)
                                    .truncationMode(.tail)
                                    .foregroundStyle(textColor)
                            }
                        }
                    }

                    ProgressView(value: state.payload.progress ?? 0)
                        .tint(.accentColor)
                        .opacity(state.payload.progress == nil ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: state.payload.progress == nil)

                    if isButton {
                        VStack {
                            Button("_cancel_") {
                                onButtonTap?()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(textColor)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .stroke(.gray, lineWidth: 1)
                            )
                        }
                        .padding(15)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Container

    @ViewBuilder
    func containerView<Content: View>(state: LucidBannerState, @ViewBuilder _ content: () -> Content) -> some View {
        let isError = (state.payload.stage == .error)
        let isSuccess = (state.payload.stage == .success)
        let isMinimized = state.variant == .alternate
        let cornerRadius: CGFloat = state.variant == .alternate ? 15 : 25
        let backgroundColor = Color(.systemBackground).opacity(0.65)
        let errorColor = Color.red.opacity(0.75)

        let base = content()
            .contentShape(Rectangle())
            .onTapGesture {
                guard allowMinimizeOnTap else { return }
                coordinator?.handleTap(state)
            }

        if isMinimized || isSuccess {
            if #available(iOS 26, *) {
                if isError {
                    base
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(errorColor)
                        )
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
                } else {
                    base
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(backgroundColor)
                        )
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
                }
            } else {
                let colorBg = isError ? Color.red.opacity(0.9) : Color.white.opacity(0.9)

                base
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(colorBg, lineWidth: 0.6)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
            }
        } else {
            let contentBase = base
                .frame(maxWidth: 500)

            if #available(iOS 26, *) {
                if isError {
                    contentBase
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(errorColor)
                        )
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    contentBase
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(backgroundColor)
                        )
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                let colorBg = isError ? Color.red.opacity(0.9) : Color.white.opacity(0.9)

                contentBase
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(colorBg, lineWidth: 0.6)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 4)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

public extension View {
    @ViewBuilder
    func applyBannerAnimation(_ style: LucidBanner.LucidBannerAnimationStyle) -> some View {
       switch style {

        // ---- iOS 18+ effects ----
        case .rotate, .pulse, .pulsebyLayer, .breathe, .bounce, .wiggle, .scale, .scaleUpbyLayer, .variableColor:
            if #available(iOS 18, *) {
                switch style {
                case .rotate:
                    self.symbolEffect(.rotate, options: .repeat(.continuous))
                case .pulse:
                    self.symbolEffect(.pulse, options: .repeat(.continuous))
                case .pulsebyLayer:
                    self.symbolEffect(.pulse.byLayer, options: .repeat(.continuous))
                case .breathe:
                    self.symbolEffect(.breathe, options: .repeat(.continuous))
                case .bounce:
                    self.symbolEffect(.bounce, options: .repeat(.continuous))
                case .wiggle:
                    self.symbolEffect(.wiggle, options: .repeat(.continuous))
                case .scale:
                    self.symbolEffect(.scale, options: .repeat(.continuous))
                case .scaleUpbyLayer:
                    self.symbolEffect(.scale.up.byLayer, options: .repeat(.continuous))
                case .variableColor:
                    self.symbolEffect(.variableColor, options: .repeat(.continuous))
                default:
                    self
                }
            } else {
                self
            }

        // ---- iOS 26+ effect: drawOn ----
        case .drawOn:
            if #available(iOS 26, *) {
                self
            } else {
                self
            }

        // ---- no animation ----
        case .none:
            self
        }
    }
}
