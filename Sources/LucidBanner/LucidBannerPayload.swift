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

    // Content

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
    /// Animation changes do not affect layout.
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

    // Appearance

    /// Background color of the banner container.
    public var backgroundColor: Color

    /// Text color applied to title, subtitle, and footnote.
    public var textColor: Color

    /// Tint color applied to the system image.
    public var imageColor: Color

    // Layout

    /// Vertical placement of the banner within its window.
    public var vPosition: LucidBanner.VerticalPosition

    /// Vertical margin applied relative to the chosen vertical position.
    public var verticalMargin: CGFloat

    /// Horizontal layout strategy applied to the banner.
    public var horizontalLayout: LucidBanner.HorizontalLayout

    // Interaction

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
    /// Note: interaction constraints (e.g. disabling dragging when
    /// `blocksTouches` is `true`) are enforced at presentation time,
    /// not within the payload itself.
    public var draggable: Bool

    /// Represents an explicit update intent for a single value.
    ///
    /// - unchanged: Do not modify the existing value.
    /// - value: Set or update the value.
    /// - clear: Explicitly remove the value (set to nil).
    public enum UpdateValue<T> {
        case unchanged
        case value(T)
        case clear
    }

    // Initialization

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
        verticalMargin: CGFloat = 0,
        horizontalLayout: LucidBanner.HorizontalLayout = .stretch(margins: 0),

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
        self.verticalMargin = verticalMargin
        self.horizontalLayout = horizontalLayout

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

        // Content

        public var title: String?
        public var subtitle: String?
        public var footnote: String?
        public var systemImage: String?
        public var imageAnimation: LucidBanner.LucidBannerAnimationStyle?
        public var progress: UpdateValue<Double> = .unchanged
        public var stage: LucidBanner.Stage?

        // Appearance

        public var backgroundColor: Color?
        public var textColor: Color?
        public var imageColor: Color?

        // Interaction

        public var draggable: Bool?
        public var swipeToDismiss: Bool?
        public var blocksTouches: Bool?

        // Layout

        public var vPosition: LucidBanner.VerticalPosition?
        public var verticalMargin: CGFloat?
        public var horizontalLayout: LucidBanner.HorizontalLayout?

        // Timing

        public var autoDismissAfter: TimeInterval?

        /// Creates an update patch.
        ///
        /// - Note:
        ///   Progress uses an explicit intent model:
        ///   - `nil`       → unchanged
        ///   - value      → set progress
        ///   - `.nan`     → clear progress
        public init(
            title: String? = nil,
            subtitle: String? = nil,
            footnote: String? = nil,

            systemImage: String? = nil,
            imageAnimation: LucidBanner.LucidBannerAnimationStyle? = nil,

            progress: Double? = nil,

            stage: LucidBanner.Stage? = nil,

            backgroundColor: Color? = nil,
            textColor: Color? = nil,
            imageColor: Color? = nil,

            vPosition: LucidBanner.VerticalPosition? = nil,
            verticalMargin: CGFloat? = nil,
            horizontalLayout: LucidBanner.HorizontalLayout? = nil,

            autoDismissAfter: TimeInterval? = nil,
            swipeToDismiss: Bool? = nil,
            blocksTouches: Bool? = nil,
            draggable: Bool? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.footnote = footnote

            self.systemImage = systemImage
            self.imageAnimation = imageAnimation

            if let progress {
                self.progress = progress.isNaN ? .clear : .value(progress)
            } else {
                self.progress = .unchanged
            }

            self.stage = stage

            self.backgroundColor = backgroundColor
            self.textColor = textColor
            self.imageColor = imageColor

            self.vPosition = vPosition
            self.verticalMargin = verticalMargin
            self.horizontalLayout = horizontalLayout
            
            self.autoDismissAfter = autoDismissAfter
            self.swipeToDismiss = swipeToDismiss
            self.blocksTouches = blocksTouches
            self.draggable = draggable
        }
    }
}

// MARK: - Merge Logic

public extension LucidBannerPayload.Update {

    /// Describes the semantic effects of applying an update patch.
    ///
    /// This structure describes *how the system should react* to changes,
    /// not the specific values that changed.
    struct MergeResult {
        var needsRelayout = false
        var contentChanged = false
        var stageChanged = false
    }

    /// Creates an update that fully restores a payload snapshot.
    /// Used to revert temporary overrides (e.g. variant transitions).
    init(from payload: LucidBannerPayload) {
        self.init(
            title: payload.title,
            subtitle: payload.subtitle,
            footnote: payload.footnote,
            systemImage: payload.systemImage,
            imageAnimation: payload.imageAnimation,
            progress: payload.progress,
            stage: payload.stage,

            backgroundColor: payload.backgroundColor,
            textColor: payload.textColor,
            imageColor: payload.imageColor,

            vPosition: payload.vPosition,
            verticalMargin: payload.verticalMargin,
            horizontalLayout: payload.horizontalLayout,

            autoDismissAfter: payload.autoDismissAfter,
            swipeToDismiss: payload.swipeToDismiss,
            blocksTouches: payload.blocksTouches,
            draggable: payload.draggable
        )
    }

    /// Applies this update patch to an existing `LucidBannerPayload`.
    ///
    /// This method performs a pure, deterministic merge:
    /// - Only non-`nil` fields are applied.
    /// - Existing values are preserved otherwise.
    /// - Sanitization and clamping are enforced during the merge.
    ///
    /// No UI side effects are performed here.
    func merge(into payload: inout LucidBannerPayload) -> MergeResult {

        var result = MergeResult()

        // Content

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

        if let footnote {
            let new = footnote.trimmedNilIfEmpty
            if payload.footnote != new {
                payload.footnote = new
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

        if let imageAnimation {
            if payload.imageAnimation != imageAnimation {
                payload.imageAnimation = imageAnimation
                result.contentChanged = true
            }
        }

        // Progress (explicit intent)

        switch progress {
        case .unchanged:
            break

        case .value(let value):
            let clamped = max(0, min(1, value))
            if payload.progress != clamped {
                if payload.progress == nil {
                    result.needsRelayout = true
                }
                payload.progress = clamped
                result.contentChanged = true
            }

        case .clear:
            if payload.progress != nil {
                payload.progress = nil
                result.needsRelayout = true
                result.contentChanged = true
            }
        }

        // Stage

        if let stage {
            if payload.stage != stage {
                payload.stage = stage
                result.needsRelayout = true
                result.stageChanged = true
            }
        }

        // Appearance

        if let backgroundColor { payload.backgroundColor = backgroundColor }
        if let textColor { payload.textColor = textColor }
        if let imageColor { payload.imageColor = imageColor }

        // Interaction

        if let draggable { payload.draggable = draggable }
        if let swipeToDismiss { payload.swipeToDismiss = swipeToDismiss }
        if let blocksTouches { payload.blocksTouches = blocksTouches }

        // Layout

        if let vPosition, payload.vPosition != vPosition {
            payload.vPosition = vPosition
            result.needsRelayout = true
        }

        if let verticalMargin, payload.verticalMargin != verticalMargin {
            payload.verticalMargin = verticalMargin
            result.needsRelayout = true
        }

        if let horizontalLayout, payload.horizontalLayout != horizontalLayout {
            payload.horizontalLayout = horizontalLayout
            result.needsRelayout = true
        }

        // Timing

        if let autoDismissAfter {
            payload.autoDismissAfter = autoDismissAfter
        }

        return result
    }
}
