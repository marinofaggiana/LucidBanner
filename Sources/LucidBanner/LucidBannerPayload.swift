//
//  LucidBannerPayload.swift
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBannerPayload is a value-type data model describing the complete
//  visual, layout, interaction, and timing configuration of a LucidBanner.
//
//  The payload represents a full, immutable snapshot of banner configuration
//  at a given point in time. It is designed to be:
//  - Explicit: every aspect of banner behavior is represented.
//  - Deterministic: identical payloads always produce identical behavior.
//  - Side-effect free: the payload itself contains no logic.
//
//  Incremental changes are expressed via `LucidBannerPayload.Update`,
//  which is merged into an existing payload using a strict
//  non-nil override strategy.
//
//  Design principles:
//  - Value semantics over reference semantics.
//  - Clear separation between full state and incremental updates.
//  - Sanitization and clamping at the data boundary.
//

import SwiftUI

// MARK: - Full Payload

/// Complete configuration snapshot for a LucidBanner.
///
/// This struct describes *everything* required to render and interact
/// with a banner instance, including content, appearance, layout,
/// interaction rules, and timing.
///
/// A `LucidBannerPayload` is never partially applied:
/// it always represents a coherent, self-contained configuration.
public struct LucidBannerPayload {

    // MARK: - Content

    /// Primary title text.
    ///
    /// Empty or whitespace-only strings are normalized to `nil`.
    public var title: String?

    /// Secondary subtitle text.
    ///
    /// Empty or whitespace-only strings are normalized to `nil`.
    public var subtitle: String?

    /// Optional footnote text displayed below main content.
    ///
    /// Empty or whitespace-only strings are normalized to `nil`.
    public var footnote: String?

    /// Name of the SF Symbol displayed in the banner.
    ///
    /// Interpreted by SwiftUI content.
    public var systemImage: String?

    /// Animation style applied to the banner icon.
    ///
    /// This value is declarative and interpreted by SwiftUI.
    public var imageAnimation: LucidBanner.LucidBannerAnimationStyle

    /// Optional progress value in the range `[0, 1]`.
    ///
    /// Values are clamped during initialization.
    /// A `nil` value hides the progress indicator.
    public var progress: Double?

    /// Optional semantic stage associated with the banner.
    ///
    /// Stages are used for higher-level coordination
    /// (e.g. progress flows, state transitions).
    public var stage: LucidBanner.Stage?

    // MARK: - Appearance

    /// Background color of the banner container.
    public var backgroundColor: Color

    /// Text color applied to title, subtitle, and footnote.
    public var textColor: Color

    /// Tint color applied to the system image.
    public var imageColor: Color

    // MARK: - Layout

    /// Vertical placement of the banner within its window.
    public var vPosition: LucidBanner.VerticalPosition

    /// Horizontal margin applied to the banner container.
    public var horizontalMargin: CGFloat

    /// Vertical margin applied relative to the chosen vertical position.
    public var verticalMargin: CGFloat

    // MARK: - Interaction

    /// Auto-dismiss delay in seconds.
    ///
    /// A value of `0` disables auto-dismiss.
    public var autoDismissAfter: TimeInterval

    /// Enables swipe-to-dismiss interaction.
    ///
    /// Direction and behavior depend on `vPosition`.
    public var swipeToDismiss: Bool

    /// When enabled, blocks touches outside the banner.
    ///
    /// This makes the banner behave as a lightweight modal overlay.
    public var blocksTouches: Bool

    /// Enables free dragging of the banner.
    ///
    /// Dragging is automatically disabled when `blocksTouches` is `true`.
    public var draggable: Bool

    // MARK: - Initialization

    /// Creates a complete banner payload.
    ///
    /// Input values are sanitized and normalized at initialization time:
    /// - Empty strings are converted to `nil`.
    /// - Progress is clamped to `[0, 1]`.
    ///
    /// Defaults are chosen to produce a non-intrusive,
    /// non-interactive banner by default.
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
        self.horizontalMargin = horizontalMargin
        self.verticalMargin = verticalMargin

        self.autoDismissAfter = autoDismissAfter
        self.swipeToDismiss = swipeToDismiss
        self.blocksTouches = blocksTouches
        self.draggable = draggable
    }
}

// MARK: - Incremental Update Payload (Patch)

public extension LucidBannerPayload {

    /// Describes a partial update to an existing `LucidBannerPayload`.
    ///
    /// This type represents a *patch*, not a full configuration.
    /// Only non-`nil` fields are applied during merge.
    ///
    /// The merge strategy is deterministic:
    /// - `nil` fields are ignored.
    /// - Non-`nil` fields overwrite the existing payload.
    struct Update {

        // MARK: - Content

        public var title: String?
        public var subtitle: String?
        public var footnote: String?
        public var systemImage: String?
        public var imageAnimation: LucidBanner.LucidBannerAnimationStyle?
        public var progress: Double?
        public var stage: LucidBanner.Stage?

        // MARK: - Appearance

        public var backgroundColor: Color?
        public var textColor: Color?
        public var imageColor: Color?

        // MARK: - Interaction

        public var draggable: Bool?
        public var swipeToDismiss: Bool?
        public var blocksTouches: Bool?

        // MARK: - Layout

        public var vPosition: LucidBanner.VerticalPosition?
        public var horizontalMargin: CGFloat?
        public var verticalMargin: CGFloat?

        // MARK: - Timing

        public var autoDismissAfter: TimeInterval?

        /// Creates an empty update patch.
        ///
        /// All properties default to `nil`.
        init(
            // MARK: - Content
            title: String? = nil,
            subtitle: String? = nil,
            footnote: String? = nil,
            systemImage: String? = nil,
            imageAnimation: LucidBanner.LucidBannerAnimationStyle? = nil,
            progress: Double? = nil,
            stage: LucidBanner.Stage? = nil,

            // MARK: - Appearance
            backgroundColor: Color? = nil,
            textColor: Color? = nil,
            imageColor: Color? = nil,

            // MARK: - Interaction
            draggable: Bool? = nil,
            swipeToDismiss: Bool? = nil,
            blocksTouches: Bool? = nil,

            // MARK: - Layout
            vPosition: LucidBanner.VerticalPosition? = nil,
            horizontalMargin: CGFloat? = nil,
            verticalMargin: CGFloat? = nil,

            // MARK: - Timing
            autoDismissAfter: TimeInterval? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.footnote = footnote
            self.systemImage = systemImage
            self.imageAnimation = imageAnimation
            self.progress = progress
            self.stage = stage

            self.backgroundColor = backgroundColor
            self.textColor = textColor
            self.imageColor = imageColor

            self.draggable = draggable
            self.swipeToDismiss = swipeToDismiss
            self.blocksTouches = blocksTouches

            self.vPosition = vPosition
            self.horizontalMargin = horizontalMargin
            self.verticalMargin = verticalMargin

            self.autoDismissAfter = autoDismissAfter
        }
    }
}

// MARK: - Merge Logic
public extension LucidBannerPayload.Update {
    /// Describes the semantic effects of applying an update patch.
    ///
    /// This structure does **not** describe *what* changed,
    /// but *how the system should react* to the applied changes.
    ///
    /// It is intentionally minimal and high-level, so that
    /// layout and side-effect decisions can be made by the caller
    /// without re-inspecting the payload.
    struct MergeResult {
        /// Indicates that the banner requires a full re-measure / re-layout pass.
        ///
        /// This is typically triggered by changes affecting intrinsic size,
        /// geometry, or content structure (e.g. title, image, progress visibility).
        var needsRelayout = false

        /// Indicates that user-visible content has changed.
        ///
        /// This flag can be used to trigger content-specific animations
        /// or accessibility updates, without necessarily re-laying out
        /// the entire banner.
        var contentChanged = false

        /// Indicates that the logical stage of the banner has changed.
        ///
        /// This is useful for driving stage-based transitions
        /// (e.g. progress → success / error) or conditional side effects.
        var stageChanged = false
    }

    /// Applies this update patch to an existing `LucidBannerPayload`,
    /// producing a semantic description of the resulting changes.
    ///
    /// This method performs a **pure, deterministic merge**:
    /// - Only non-`nil` fields in the update are applied.
    /// - Existing values are preserved when the corresponding update field is `nil`.
    /// - Sanitization rules (such as string trimming or progress clamping)
    ///   are applied during the merge.
    ///
    /// The method does **not** perform any UI side effects,
    /// scheduling, gesture updates, or layout operations.
    /// Those responsibilities are intentionally left to the caller,
    /// based on the returned `MergeResult`.
    ///
    /// - Parameters:
    ///   - payload: The payload to be mutated in place.
    ///   - old: A snapshot of the payload *before* the merge,
    ///          used only for semantic comparison.
    ///
    /// - Returns: A `MergeResult` describing the high-level impact
    ///            of the applied changes.
    ///
    /// - Important:
    ///   This method is designed to be the **single source of truth**
    ///   for payload mutation. Callers should avoid re-implementing
    ///   merge or diff logic outside of this API.
    func merge(into payload: inout LucidBannerPayload, comparing old: LucidBannerPayload) -> MergeResult {
        var result = MergeResult()

        // MARK: - Content

        if let title {
            let new = title.trimmedNilIfEmpty
            if payload.title != new {
                payload.title = new
                result.needsRelayout = true
                result.contentChanged = true
            }
        }

        if let subtitle {
            let new = subtitle.trimmedNilIfEmpty
            if payload.subtitle != new {
                payload.subtitle = new
                result.needsRelayout = true
                result.contentChanged = true
            }
        }

        if let systemImage {
            if payload.systemImage != systemImage {
                payload.systemImage = systemImage
                result.needsRelayout = true
                result.contentChanged = true
            }
        }

        if let progress {
            let clamped = max(0, min(1, progress))
            if payload.progress == nil {
                result.needsRelayout = true
            }
            payload.progress = clamped
        }

        if let stage {
            if payload.stage != stage {
                payload.stage = stage
                result.needsRelayout = true
                result.stageChanged = true
            }
        }

        // MARK: - Appearance (no layout impact)

        if let backgroundColor { payload.backgroundColor = backgroundColor }
        if let textColor { payload.textColor = textColor }
        if let imageColor { payload.imageColor = imageColor }

        // MARK: - Interaction / Layout / Timing (pure state)

        if let draggable { payload.draggable = draggable }
        if let swipeToDismiss { payload.swipeToDismiss = swipeToDismiss }
        if let blocksTouches { payload.blocksTouches = blocksTouches }

        if let vPosition {
            payload.vPosition = vPosition
            result.needsRelayout = true
        }

        if let horizontalMargin {
            payload.horizontalMargin = horizontalMargin
            result.needsRelayout = true
        }

        if let verticalMargin {
            payload.verticalMargin = verticalMargin
            result.needsRelayout = true
        }

        if let autoDismissAfter {
            payload.autoDismissAfter = autoDismissAfter
        }

        return result
    }
}
