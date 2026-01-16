//
//  LucidBannerPayload.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Description:
//  Data model describing the full visual, layout and interaction
//  configuration of a LucidBanner instance.
//
//  The payload represents a complete snapshot of banner state.
//  Incremental changes are applied via `LucidBannerPayload.Update`
//  using a deterministic merge strategy.
//

import SwiftUI

// MARK: - Full payload

public struct LucidBannerPayload {

    // MARK: Content

    public var title: String?
    public var subtitle: String?
    public var footnote: String?
    public var systemImage: String?
    public var imageAnimation: LucidBanner.LucidBannerAnimationStyle
    public var progress: Double?
    public var stage: LucidBanner.Stage?

    // MARK: Appearance

    public var backgroundColor: Color
    public var textColor: Color
    public var imageColor: Color

    // MARK: Layout

    public var vPosition: LucidBanner.VerticalPosition
    public var hAlignment: LucidBanner.HorizontalAlignment
    public var horizontalMargin: CGFloat
    public var verticalMargin: CGFloat

    // MARK: Interaction

    public var autoDismissAfter: TimeInterval
    public var swipeToDismiss: Bool
    public var blocksTouches: Bool
    public var draggable: Bool

    // MARK: Init

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        footnote: String? = nil,
        systemImage: String? = nil,
        imageAnimation: LucidBanner.LucidBannerAnimationStyle = .none,
        progress: Double? = nil,
        stage: LucidBanner.Stage? = nil,
        backgroundColor: Color = .clear,
        textColor: Color = .primary,
        imageColor: Color = .primary,
        vPosition: LucidBanner.VerticalPosition = .center,
        hAlignment: LucidBanner.HorizontalAlignment = .center,
        horizontalMargin: CGFloat = 12,
        verticalMargin: CGFloat = 10,
        autoDismissAfter: TimeInterval = 0,
        swipeToDismiss: Bool = false,
        blocksTouches: Bool = false,
        draggable: Bool = false
    ) {
        self.title = title?.trimmedNilIfEmpty
        self.subtitle = subtitle?.trimmedNilIfEmpty
        self.footnote = footnote?.trimmedNilIfEmpty
        self.systemImage = systemImage
        self.imageAnimation = imageAnimation
        self.progress = progress.map { max(0, min(1, $0)) }
        self.stage = stage

        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.imageColor = imageColor

        self.vPosition = vPosition
        self.hAlignment = hAlignment
        self.horizontalMargin = horizontalMargin
        self.verticalMargin = verticalMargin

        self.autoDismissAfter = autoDismissAfter
        self.swipeToDismiss = swipeToDismiss
        self.blocksTouches = blocksTouches
        self.draggable = draggable
    }
}

// MARK: - Incremental update payload (patch)

public extension LucidBannerPayload {

    /// Describes a partial update to an existing `LucidBannerPayload`.
    /// Only non-nil values are applied during merge.
    struct Update {

        // MARK: Content

        public var title: String?
        public var subtitle: String?
        public var footnote: String?
        public var systemImage: String?
        public var imageAnimation: LucidBanner.LucidBannerAnimationStyle?
        public var progress: Double?
        public var stage: LucidBanner.Stage?

        // MARK: Appearance

        public var backgroundColor: Color?
        public var textColor: Color?
        public var imageColor: Color?

        // MARK: Interaction

        public var draggable: Bool?
        public var swipeToDismiss: Bool?
        public var blocksTouches: Bool?

        // MARK: Layout

        public var vPosition: LucidBanner.VerticalPosition?
        public var hAlignment: LucidBanner.HorizontalAlignment?
        public var horizontalMargin: CGFloat?
        public var verticalMargin: CGFloat?

        // MARK: Timing

        public var autoDismissAfter: TimeInterval?

        public init() {}
    }
}

// MARK: - Merge logic

public extension LucidBannerPayload.Update {

    /// Applies this update patch to an existing payload.
    /// Only non-nil fields are merged.
    func merge(into payload: inout LucidBannerPayload) {

        // MARK: Content

        if let title {
            payload.title = title.trimmedNilIfEmpty
        }

        if let subtitle {
            payload.subtitle = subtitle.trimmedNilIfEmpty
        }

        if let footnote {
            payload.footnote = footnote.trimmedNilIfEmpty
        }

        if let systemImage {
            payload.systemImage = systemImage
        }

        if let imageAnimation {
            payload.imageAnimation = imageAnimation
        }

        if let progress {
            payload.progress = max(0, min(1, progress))
        }

        if let stage {
            payload.stage = stage
        }

        // MARK: Appearance

        if let backgroundColor {
            payload.backgroundColor = backgroundColor
        }

        if let textColor {
            payload.textColor = textColor
        }

        if let imageColor {
            payload.imageColor = imageColor
        }

        // MARK: Interaction

        if let draggable {
            payload.draggable = draggable
        }

        if let swipeToDismiss {
            payload.swipeToDismiss = swipeToDismiss
        }

        if let blocksTouches {
            payload.blocksTouches = blocksTouches
        }

        // MARK: Layout

        if let vPosition {
            payload.vPosition = vPosition
        }

        if let hAlignment {
            payload.hAlignment = hAlignment
        }

        if let horizontalMargin {
            payload.horizontalMargin = horizontalMargin
        }

        if let verticalMargin {
            payload.verticalMargin = verticalMargin
        }

        // MARK: Timing

        if let autoDismissAfter {
            payload.autoDismissAfter = autoDismissAfter
        }
    }
}
