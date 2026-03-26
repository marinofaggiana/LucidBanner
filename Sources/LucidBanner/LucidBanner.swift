//
//  LucidBanner
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Overview:
//  LucidBanner is a deterministic, scene-aware banner presentation system
//  built on top of SwiftUI and UIKit.
//
//  It provides animated, interruptible, and queueable in-app notifications
//  presented above the entire application UI using a dedicated UIWindow.
//  Only one banner may be visible at any time within a single scene
//  handled through an explicit queue and show policy.
//
//  LucidBanner is intentionally not a view framework.
//  SwiftUI views are passive renderers fed by a single shared state object.
//  All lifecycle, timing, interaction, and animation logic lives here.
//
//  Responsibilities:
//  - Own the full banner lifecycle (show, update, dismiss).
//  - Coordinate animations and layout transitions.
//  - Enforce token safety across async operations.
//  - Manage interaction modes (blocking, passthrough, dragging).
//  - Guarantee MainActor execution for all UI mutations.
//
//  Invariants:
//  - At most one banner window exists per UIWindowScene.
//  - A banner is uniquely identified by a token.
//  - Updates never apply to stale banners.
//  - SwiftUI content contains no presentation logic.
//
//

import SwiftUI
import UIKit

/// Global coordinator and state machine responsible for presenting,
/// updating, and dismissing Lucid banners.
///
/// `LucidBanner` owns the entire control flow of banner presentation.
/// It enforces strict sequencing, token validation, and animation safety.
///
/// SwiftUI views rendered by LucidBanner are pure functions of state.
/// They never initiate transitions or side effects.
@MainActor
public final class LucidBanner: NSObject, UIGestureRecognizerDelegate {
    /// Policy describing how a new banner request is handled when
    /// another banner is already visible or transitioning.
    public enum ShowPolicy {

        /// Immediately dismisses the current banner and replaces it.
        /// Any queued banners are dropped.
        case replace

        /// Enqueues the new banner and presents it after the current
        /// banner has fully dismissed.
        case enqueue

        /// Ignores the new request if a banner is already active.
        case drop
    }

    /// Visual animation style applied to the banner icon.
    ///
    /// These values are interpreted by SwiftUI content only.
    /// They do not affect layout, gestures, or lifecycle.
    public enum LucidBannerAnimationStyle {
        case none
        case rotate
        case pulse
        case pulsebyLayer
        case drawOn
        case breathe
        case bounce
        case wiggle
        case scale
        case scaleUpbyLayer
        case variableColor
    }

    /// Vertical placement of the banner inside the window.
    ///
    /// This value influences:
    /// - Auto Layout constraints
    /// - Presentation animation direction
    /// - Swipe-to-dismiss semantics
    public enum VerticalPosition {
        case top
        case center
        case bottom
    }

    /// Describes how a LucidBanner is positioned and constrained
    /// along the horizontal axis within its hosting window.
    ///
    /// The horizontal layout defines the banner’s relationship
    /// to the window edges or center, independently from its
    /// visual variant or content.
    public enum HorizontalLayout: Equatable {
        /// Stretches the banner across the available horizontal space.
        ///
        /// The banner is constrained using leading and trailing anchors
        /// relative to the window (or safe area), with symmetric margins.
        ///
        /// This layout produces a flexible, full-width banner whose
        /// final width adapts to the window size.
        case stretch(margins: CGFloat)

        /// Centers the banner horizontally with a fixed width.
        ///
        /// The banner is constrained using a centerX anchor and an
        /// explicit width constraint, producing a floating, object-like
        /// presentation independent of the window edges.
        case centered(width: CGFloat)

        /// Anchors the banner to the leading edge with a fixed width.
        ///
        /// The banner is positioned relative to the leading edge of the
        /// window (or safe area) and given a fixed width. An optional
        /// offset may be used to introduce additional horizontal spacing.
        case leading(width: CGFloat, offset: CGFloat = 0)

        /// Anchors the banner to the trailing edge with a fixed width.
        ///
        /// The banner is positioned relative to the trailing edge of the
        /// window (or safe area) and given a fixed width. An optional
        /// offset may be used to introduce additional horizontal spacing.
        case trailing(width: CGFloat, offset: CGFloat = 0)
    }

    /// Defines how the banner animates when appearing and disappearing.
    ///
    /// PresentationStyle controls only the transition animation.
    /// It does not affect layout, interaction, or positioning.
    public enum PresentationStyle: Equatable {
        /// Automatically selects a style based on vertical position.
        case automatic

        /// Slides vertically from outside the window bounds.
        case slide

        /// Scales with a subtle zoom-in effect.
        case scale

        /// Fades without positional or scale transformation.
        case fade
    }

    /// Internal representation of a queued banner request.
    ///
    /// PendingShow encapsulates configuration and content
    /// without instantiating any UI.
    private struct PendingShow {
        let payload: LucidBannerPayload
        let onTap: ((_ token: Int?, _ stage: LucidBanner.Stage?) -> Void)?
        let viewUI: (LucidBannerState) -> AnyView
        let token: Int
    }

    /// Factory producing the SwiftUI content for the active banner.
    ///
    /// The factory is rebound per banner, but always receives
    /// the same shared `LucidBannerState` instance.
    private var contentView: ((LucidBannerState) -> AnyView)?

    // MARK: - Window & Hosting Infrastructure

    /// Scene where the banner window is attached.
    private var scene: UIWindowScene

    /// Public windows Scene
    public var windowScene: UIWindowScene {
        scene
    }

    /// Whether touches outside the banner are blocked.
    private var blocksTouches = false

    /// Dedicated UIWindow hosting the banner.
    private var window: LucidBannerWindow?

    /// Hosting controller wrapping SwiftUI content.
    private var hostController: UIHostingController<AnyView>?

    /// Optional dimming scrim used when touches are blocked.
    private weak var scrimView: UIControl?

    /// Root container view hosting the banner.
    private weak var rootView: UIView?

    // MARK: - Lifecycle Flags

    /// Auto-dismiss scheduling task.
    private var dismissTimer: Task<Void, Never>?

    /// Indicates an active presentation animation.
    private var isAnimatingIn = false

    /// Indicates an active dismissal animation.
    private var isDismissing = false

    /// Signals a deferred layout pass after animation.
    private var pendingRelayout = false

    /// Indicates a banner is considered active.
    private var isPresenting = false

    /// Completion handlers waiting for the current banner to fully dismiss.
    private var pendingDismissCompletions: [() -> Void] = []

    private var presentationStyle: PresentationStyle = .automatic

    // MARK: - Layout State

    /// Height constraint stabilizing banner layout.
    private var heightConstraint: NSLayoutConstraint?

    /// Active horizontal layout constraints.
    ///
    /// These constraints are derived from `horizontalLayout`
    /// and are replaced wholesale on each layout pass.
    private var horizontalConstraints: [NSLayoutConstraint] = []

    /// Minimum allowed banner height.
    private let minHeight: CGFloat = 44

    /// Requested vertical position.
    private var vPosition: VerticalPosition = .top

    /// Effective vertical position used during presentation.
    private var presentedVPosition: VerticalPosition = .top

    /// Horizontal layout intent applied to the banner.
    private var horizontalLayout: HorizontalLayout = .stretch(margins: 12)

    /// Whether this banner respects the window safe area.
    private var respectsSafeArea: Bool = true

    /// Vertical margin applied relative to the chosen vertical position.
    private var verticalMargin: CGFloat = 0

    // MARK: - Queue

    /// FIFO queue of pending banner requests.
    private var queue: [PendingShow] = []

    // MARK: - Gestures & Interaction

    /// Time threshold after which gestures are enabled.
    private var interactionUnlockTime: CFTimeInterval = 0

    /// Pan gesture used for dragging or swipe-to-dismiss.
    private weak var panGestureRef: UIPanGestureRecognizer?

    /// Starting frame snapshot for drag clamping.
    private var dragStartFrameInContainer: CGRect = .zero

    /// Starting offset snapshot used for incremental dragging.
    private var dragStartOffset: CGPoint = .zero

    /// Shared observable state injected into SwiftUI.
    ///
    /// This is the single source of truth for UI rendering.
    let state = LucidBannerState(payload: LucidBannerPayload())

    // MARK: - Position State

    /// Logical offset applied on top of Auto Layout.
    ///
    /// This is the single source of truth for persistent visual displacement.
    private var offset: CGPoint = .zero

    /// Persistent transform derived from the logical offset.
    private var offsetTransform: CGAffineTransform = .identity

    /// Transient transform used for non-positional visual effects.
    private var effectTransform: CGAffineTransform = .identity

    private var animationTransform: CGAffineTransform = .identity

    // MARK: - Interaction Configuration

    /// Enables swipe-to-dismiss interaction.
    private var swipeToDismiss = false

    /// Delay after which the banner auto-dismisses.
    private var autoDismissAfter: TimeInterval = 0

    /// Enables free dragging of the banner.
    private var draggable: Bool = false

    // MARK: - Token & Callbacks

    /// Monotonic counter used to generate banner tokens.
    private var generation: Int = 0

    /// Token identifying the currently active banner.
    private var activeToken: Int?

    /// Tap callback associated with the active banner.
    private var onTap: ((_ token: Int?, _ stage: LucidBanner.Stage?) -> Void)?

    // MARK: - Initialization

    /// Initializes a scene-scoped LucidBanner coordinator.
    ///
    /// This initializer binds the banner engine to a specific `UIWindowScene`.
    /// The banner instance becomes exclusively responsible for presenting
    /// and managing overlay content within that scene.
    ///
    /// In multi-window environments (e.g. iPad), each scene must own its
    /// own LucidBanner instance to guarantee:
    /// - Isolation of presentation state
    /// - Independent token spaces
    /// - Independent banner queues
    /// - Correct lifecycle handling when a scene deactivates or enters background
    ///
    /// The banner will observe lifecycle notifications for the provided scene
    /// and automatically dismiss active overlays when the scene transitions
    /// out of the foreground.
    ///
    /// - Parameter scene: The UIWindowScene that owns and hosts this banner.
    init(scene: UIWindowScene) {
        self.scene = scene
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    // MARK: - Application Lifecycle

    /// Handles application backgrounding.
    ///
    /// When the app enters the background, any visible banner is
    /// immediately dismissed without animation and all transient
    /// UI resources are released.
    ///
    /// This guarantees that no UIWindow or animation survives
    /// background suspension.
    @objc private func appDidEnterBackground() {
        Task { @MainActor in
            dismissAll(animated: false)
        }
    }

    // MARK: - Public API: Presentation

    /// Presents a new banner using the provided configuration and content.
    ///
    /// This method is the primary entry point for banner presentation.
    /// Each invocation generates a unique token identifying the banner.
    ///
    /// If another banner is already active, the behavior depends on
    /// the selected `ShowPolicy`.
    ///
    /// - Parameters:
    ///   - scene: The target UIWindowScene where the banner window is attached.
    ///   - payload: Describes content, appearance, interaction, and timing.
    ///   - policy: Strategy applied when another banner is already visible.
    ///   - onTap: Optional tap handler receiving the banner token and stage.
    ///   - content: SwiftUI view builder rendering the banner body.
    ///
    /// - Returns: A token uniquely identifying the banner request.
    @discardableResult
    public func show<Content: View>(
        payload: LucidBannerPayload,
        policy: ShowPolicy = .enqueue,
        onTap: ((_ token: Int?, _ stage: LucidBanner.Stage?) -> Void)? = nil,
        @ViewBuilder content: @escaping (LucidBannerState) -> Content) -> Int {

        // Generate a new token up front for deterministic tracking.
        generation &+= 1
        let newToken = generation

        let isSceneActive = scene.activationState == .foregroundActive

        if !isSceneActive {
            // Hard reset: drop any queued requests and dismiss any visible banner without animation.
            queue.removeAll()
            dismissAll(animated: false)
            return newToken
        }

        // Bind SwiftUI content to the shared state.
        let viewFactory: (LucidBannerState) -> AnyView = {
            AnyView(content($0))
        }

        let pending = PendingShow(
            payload: payload,
            onTap: onTap,
            viewUI: viewFactory,
            token: newToken
        )

        // Handle concurrent presentation according to policy.
        if window != nil || isPresenting || isDismissing {
            switch policy {
            case .drop:
                return activeToken ?? newToken

            case .enqueue:
                queue.append(pending)
                return newToken

            case .replace:
                queue.removeAll()
                queue.append(pending)
                dismiss()
                return newToken
            }
        }

        // No banner active: present immediately.
        activeToken = newToken
        presentedVPosition = payload.vPosition
        applyPending(pending)

        isPresenting = true
        startShow(with: pending.viewUI)

        return newToken
    }

    // MARK: - Public API: Updates

    /// Updates the currently visible banner.
    ///
    /// Updates are applied incrementally: only non-`nil` fields
    /// in the update payload are mutated.
    ///
    /// If a token is provided, the update is ignored unless it
    /// matches the active banner.
    ///
    /// Some updates may trigger a layout re-measure or
    /// reschedule auto-dismiss.
    ///
    /// - Parameters:
    ///   - payload: Partial payload describing the updates.
    ///   - token: Optional token to restrict the update.
    public func update(payload update: LucidBannerPayload.Update, for token: Int? = nil) {
        guard window != nil,
              token == nil || token == activeToken else {
            return
        }

        var shouldRescheduleAutoDismiss = false

        // Snapshot before merge (semantic diff reference)
        let oldPayload = state.payload

        // Merge (single source of truth)
        let mergeResult = update.merge(into: &state.payload)
        let newPayload = state.payload

        guard let window else { return }

        // Interaction Resolution

        let wantsBlocksTouches = newPayload.blocksTouches
        let wantsSwipeToDismiss = newPayload.swipeToDismiss
        let wantsDraggable = newPayload.draggable

        // Apply blocking changes

        if oldPayload.blocksTouches != wantsBlocksTouches {
            blocksTouches = wantsBlocksTouches

            window.isPassthrough = !blocksTouches
            window.accessibilityViewIsModal = blocksTouches

            scrimView?.isUserInteractionEnabled = blocksTouches
            scrimView?.backgroundColor = UIColor.black.withAlphaComponent(
                blocksTouches ? 0.08 : 0.0
            )
        }

        // Resolve effective interaction modes

        let effectiveSwipeToDismiss = !blocksTouches && wantsSwipeToDismiss
        let effectiveDraggable = !blocksTouches && wantsDraggable

        if swipeToDismiss != effectiveSwipeToDismiss {
            ensurePanGestureInstalled()
            swipeToDismiss = effectiveSwipeToDismiss
        }

        if draggable != effectiveDraggable {
            ensurePanGestureInstalled()
            draggable = effectiveDraggable
        }

        // Enable or disable pan gesture deterministically
        panGestureRef?.isEnabled = swipeToDismiss || draggable

        // Layout State

        if oldPayload.presentationStyle != newPayload.presentationStyle {
            presentationStyle = newPayload.presentationStyle
        }

        if oldPayload.vPosition != newPayload.vPosition {
            vPosition = newPayload.vPosition
            presentedVPosition = newPayload.vPosition
        }

        if oldPayload.verticalMargin != newPayload.verticalMargin {
            verticalMargin = newPayload.verticalMargin
        }

        if oldPayload.horizontalLayout != newPayload.horizontalLayout {
            horizontalLayout = newPayload.horizontalLayout

            if let hostView = hostController?.view,
               let root = rootView {
                applyHorizontalLayoutConstraints(hostView: hostView, root: root)
            }
        }

        if let newValue = update.respectsSafeArea,
           newValue != respectsSafeArea {

            respectsSafeArea = newValue

            if let hostView = hostController?.view,
               let root = rootView {

                applyVerticalPositionConstraints(hostView: hostView, root: root)
                applyHorizontalLayoutConstraints(hostView: hostView, root: root)

                if isAnimatingIn || isDismissing {
                    pendingRelayout = true
                } else {
                    remeasure(animated: true)
                }
            }
        }

        // Timing

        if oldPayload.autoDismissAfter != newPayload.autoDismissAfter {
            autoDismissAfter = newPayload.autoDismissAfter
            shouldRescheduleAutoDismiss = newPayload.autoDismissAfter > 0

            if !shouldRescheduleAutoDismiss {
                dismissTimer?.cancel()
                dismissTimer = nil
            }
        }

        // Layout Pass

        if mergeResult.needsRelayout {
            if isAnimatingIn || isDismissing {
                pendingRelayout = true
            } else {
                remeasure(animated: true)
            }
        } else {
            UIView.performWithoutAnimation {
                self.applyTransforms()
                window.layoutIfNeeded()
            }
        }

        // Auto-dismiss

        if shouldRescheduleAutoDismiss {
            scheduleAutoDismiss()
        }
    }

    // MARK: - Public API: Positioning & Inspection

    /// Translates the banner so that its visual center matches the given
    /// point in window coordinates.
    ///
    /// The movement is applied as a delta on top of the current logical offset,
    /// preserving the visual position across future layout passes.
    ///
    /// - Parameters:
    ///   - x: Target X coordinate in window space.
    ///   - y: Target Y coordinate in window space.
    ///   - token: Optional token restricting the operation.
    ///   - animated: Whether the movement is animated.
    public func move(toX x: CGFloat, y: CGFloat, for token: Int? = nil, animated: Bool = true) {
        guard window != nil, token == nil || token == activeToken else { return }
        guard let hostView = hostController?.view else { return }

        let currentTransform = hostView.transform
        hostView.transform = .identity

        let frame = hostView.frame
        let currentCenter = CGPoint(x: frame.midX, y: frame.midY)

        hostView.transform = currentTransform

        let dx = x - currentCenter.x
        let dy = y - currentCenter.y

        offset.x += dx
        offset.y += dy
        updateOffsetTransform()

        let animations = {
            self.applyTransforms()
        }

        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.5,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: animations
            )
        } else {
            animations()
        }
    }

    /// Resets any custom offset applied to the banner, restoring the
    /// position defined exclusively by Auto Layout.
    ///
    /// - Parameters:
    ///   - token: Optional token restricting the operation.
    ///   - animated: Whether the reset is animated.
    public func resetPosition(for token: Int? = nil, animated: Bool = true) {
        guard window != nil, token == nil || token == activeToken else { return }
        guard hostController?.view != nil else { return }

        offset = .zero
        updateOffsetTransform()

        let animations = {
            self.applyTransforms()
        }

        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.5,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: animations
            )
        } else {
            animations()
        }
    }

    /// Returns the current banner frame in window coordinates,
    /// including any active transform.
    ///
    /// - Parameter token: Optional token validation.
    /// - Returns: The banner frame, or `nil` if not visible.
    public func currentFrameInWindow(for token: Int? = nil) -> CGRect? {
        guard window != nil, token == nil || token == activeToken else { return nil }
        return currentLayoutFrame()
    }

    /// Returns the underlying UIKit host view of the active banner.
    ///
    /// Intended for advanced integrations requiring direct access
    /// to transforms or layer properties.
    public func currentHostView(for token: Int? = nil) -> UIView? {
        guard token == nil || token == activeToken else { return nil }
        return hostController?.view
    }

    /// Enables or disables drag-related gestures for the active banner.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether dragging is allowed.
    ///   - token: Optional token validation.
    public func setDraggingEnabled(_ isEnabled: Bool, for token: Int? = nil) {
        guard window != nil, token == nil || token == activeToken else { return }
        panGestureRef?.isEnabled = isEnabled
    }

    /// Requests a full re-measure of the banner content.
    ///
    /// This is useful after external SwiftUI changes that affect
    /// intrinsic content size.
    public func requestRelayout(animated: Bool) {
        remeasure(animated: animated)
    }

    /// Returns whether the provided token identifies the currently
    /// visible banner.
    public func isAlive(_ token: Int?) -> Bool {
        token == activeToken && window != nil
    }

    /// Returns the shared banner state for the active token.
    ///
    /// This method never exposes state for stale or queued banners.
    public func currentState(for token: Int) -> LucidBannerState? {
        guard activeToken == token else { return nil }
        return state
    }

    // MARK: - Public API: Dismissal

    /// Dismisses the active banner and starts the next queued banner, if any.
    ///
    /// If a dismissal is already in progress, the completion is queued
    /// and executed when the current dismissal finishes.
    public func dismiss(completion: (() -> Void)? = nil) {
        if let completion {
            pendingDismissCompletions.append(completion)
        }

        dismissTimer?.cancel()
        dismissTimer = nil

        if isPresenting {
            pendingDismissCompletions.append { [weak self] in
                self?.dismiss()
            }
            return
        }

        if isDismissing {
            return
        }

        guard let window, let hostView = hostController?.view else {
            hostController = nil
            self.window?.isHidden = true
            self.window = nil
            self.rootView = nil
            self.scrimView = nil
            self.panGestureRef = nil
            self.activeToken = nil
            self.heightConstraint = nil
            self.isPresenting = false
            self.isDismissing = false
            self.offset = .zero
            self.offsetTransform = .identity
            self.effectTransform = .identity

            let completions = pendingDismissCompletions
            pendingDismissCompletions.removeAll()
            completions.forEach { $0() }
            return
        }

        isPresenting = false
        isDismissing = true

        hostView.isUserInteractionEnabled = false
        panGestureRef?.isEnabled = false

        let resolvedStyle: PresentationStyle = {
            if presentationStyle == .automatic {
                switch presentedVPosition {
                case .center: return .scale
                case .top, .bottom: return .slide
                }
            }
            return presentationStyle
        }()

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            hostView.alpha = 0

            switch resolvedStyle {

            case .slide:
                let offsetY: CGFloat = {
                    switch self.presentedVPosition {
                    case .top:
                        return -window.bounds.height
                    case .bottom:
                        return window.bounds.height
                    case .center:
                        return -hostView.bounds.height - 40
                    }
                }()

                self.offset.y += offsetY
                self.updateOffsetTransform()
                self.applyTransforms()

            case .scale:
                self.effectTransform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                self.applyTransforms()

            case .fade:
                break

            default:
                break
            }

            hostView.layer.shadowOpacity = 0
            window.layoutIfNeeded()

        } completion: { _ in
            hostView.transform = .identity

            self.horizontalConstraints.forEach { $0.isActive = false }
            self.horizontalConstraints.removeAll()

            if let constraint = self.heightConstraint {
                constraint.isActive = false
                self.heightConstraint = nil
            }

            self.hostController = nil
            window.isHidden = true
            window.rootViewController = nil
            self.window = nil
            self.rootView = nil

            self.isDismissing = false
            self.panGestureRef = nil
            self.scrimView = nil

            self.blocksTouches = false
            self.swipeToDismiss = false
            self.draggable = false

            self.activeToken = nil
            self.offset = .zero
            self.offsetTransform = .identity
            self.effectTransform = .identity

            self.dequeueAndStartIfNeeded()

            let completions = self.pendingDismissCompletions
            self.pendingDismissCompletions.removeAll()
            completions.forEach { $0() }
        }
    }

    /// Async variant of `dismiss()`.
    public func dismissAsync() async {
        await withCheckedContinuation { continuation in
            dismiss { continuation.resume() }
        }
    }

    /// Dismisses the active banner after a delay.
    ///
    /// If another banner becomes active before the delay expires,
    /// the dismissal is ignored.
    public func dismiss(after seconds: TimeInterval, completion: (() -> Void)? = nil) {
        dismissTimer?.cancel()

        guard seconds > 0 else {
            dismiss(completion: completion)
            return
        }

        let tokenAtSchedule = activeToken

        dismissTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run {
                guard self.activeToken == tokenAtSchedule else { return }
                self.dismiss(completion: completion)
            }
        }
    }

    /// Async variant of delayed dismissal.
    public func dismissAsync(after seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            dismiss(after: seconds) { continuation.resume() }
        }
    }

    /// Immediately dismisses all banners and clears the queue.
    ///
    /// This is a hard reset of the banner system.
    public func dismissAll(animated: Bool = true, completion: (() -> Void)? = nil) {
        dismissTimer?.cancel()
        dismissTimer = nil
        queue.removeAll()

        guard let window else {
            activeToken = nil
            offset = .zero
            offsetTransform = .identity
            effectTransform = .identity
            completion?()
            return
        }

        let hide = {
            window.alpha = 0
        }

        let finalize = {
            self.hostController?.view.transform = .identity
            self.activeToken = nil
            window.isHidden = true
            window.rootViewController = nil

            self.horizontalConstraints.forEach { $0.isActive = false }
            self.horizontalConstraints.removeAll()

            if let constraint = self.heightConstraint {
                constraint.isActive = false
                self.heightConstraint = nil
            }

            self.hostController = nil
            self.window = nil
            self.rootView = nil
            self.scrimView = nil
            self.panGestureRef = nil

            self.isPresenting = false
            self.isDismissing = false
            self.blocksTouches = false
            self.swipeToDismiss = false
            self.draggable = false

            self.offset = .zero
            self.offsetTransform = .identity
            self.effectTransform = .identity

            completion?()
        }

        if animated {
            UIView.animate(withDuration: 0.20, animations: hide) { _ in
                finalize()
            }
        } else {
            hide()
            finalize()
        }
    }

    public func setRespectsSafeArea(_ value: Bool, for token: Int? = nil, animated: Bool = true) {
        guard window != nil,
              token == nil || token == activeToken,
              value != respectsSafeArea else { return }

        respectsSafeArea = value

        if let hostView = hostController?.view,
           let root = rootView {
            applyVerticalPositionConstraints(hostView: hostView, root: root)
            applyHorizontalLayoutConstraints(hostView: hostView, root: root)
            remeasure(animated: animated)
        }
    }

    // MARK: - Internals: Presentation Pipeline

    /// Starts the presentation pipeline for the provided SwiftUI content factory.
    ///
    /// This method transitions the coordinator into the "animating in" phase,
    /// binds the active `contentView`, attaches the banner window, and schedules
    /// auto-dismiss if configured.
    ///
    /// Contract:
    /// - Assumes `applyPending(_:)` has already populated all per-banner configuration.
    /// - Marks the banner as transitioning in (`isAnimatingIn = true`).
    /// - Creates window/UI synchronously on the MainActor.
    /// - Auto-dismiss is token-safe and will not affect future banners.
    private func startShow(with viewUI: @escaping (LucidBannerState) -> AnyView) {
        isAnimatingIn = true
        pendingRelayout = false
        contentView = viewUI

        attachWindowAndPresent()
        scheduleAutoDismiss()
    }

    // MARK: - Internals: Queue & Presentation

    /// Applies a queued banner configuration to internal state
    /// before presentation.
    private func applyPending(_ p: PendingShow) {
        state.variant = .standard
        state.payload = p.payload

        presentationStyle = p.payload.presentationStyle
        vPosition = p.payload.vPosition
        verticalMargin = p.payload.verticalMargin
        horizontalLayout = p.payload.horizontalLayout
        respectsSafeArea = p.payload.respectsSafeArea

        autoDismissAfter = p.payload.autoDismissAfter
        blocksTouches = p.payload.blocksTouches
        draggable = p.payload.draggable && !p.payload.blocksTouches
        swipeToDismiss = p.payload.blocksTouches ? false : p.payload.swipeToDismiss

        onTap = p.onTap

        offset = .zero
        offsetTransform = .identity
        effectTransform = .identity
    }

    /// Dequeues and presents the next banner, if possible.
    private func dequeueAndStartIfNeeded() {
        guard !isPresenting, !isDismissing, window == nil else { return }
        guard let next = queue.first else { return }

        queue.removeFirst()
        activeToken = next.token
        presentedVPosition = next.payload.vPosition

        applyPending(next)
        isPresenting = true
        startShow(with: next.viewUI)
    }

    // MARK: - Internals: Window Attachment & Layout

    /// Attaches the banner window and presents the SwiftUI content.
    ///
    /// This method bridges the banner state machine with UIKit.
    /// It creates the UIWindow, installs the hosting controller,
    /// applies layout constraints, and runs the presentation animation.
    ///
    /// Must be called on the MainActor.
    /// Attaches the banner window and presents the SwiftUI content.
    ///
    /// This method bridges the banner state machine with UIKit.
    /// It creates the UIWindow, installs the hosting controller,
    /// applies layout constraints, and runs the presentation animation.
    ///
    /// Must be called on the MainActor.
    private func attachWindowAndPresent() {
        let window = LucidBannerWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        window.isPassthrough = !blocksTouches
        window.accessibilityViewIsModal = blocksTouches

        let root = UIView()
        root.backgroundColor = .clear
        self.rootView = root

        let rootViewController = UIViewController()
        rootViewController.view = root
        window.rootViewController = rootViewController

        let content = contentView?(state) ?? AnyView(EmptyView())
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        rootViewController.addChild(host)
        root.addSubview(host.view)
        host.view.transform = .identity
        host.didMove(toParent: rootViewController)

        let scrim = UIControl()
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.backgroundColor = UIColor.black.withAlphaComponent(blocksTouches ? 0.08 : 0.0)
        scrim.isUserInteractionEnabled = blocksTouches
        self.scrimView = scrim

        root.insertSubview(scrim, belowSubview: host.view)

        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: root.topAnchor),
            scrim.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let guide = root.safeAreaLayoutGuide
        let useSafeArea = respectsSafeArea

        let referenceTop = useSafeArea ? guide.topAnchor : root.topAnchor
        let referenceBottom = useSafeArea ? guide.bottomAnchor : root.bottomAnchor

        switch vPosition {

        case .top:
            host.view.topAnchor.constraint(
                equalTo: referenceTop,
                constant: verticalMargin
            ).isActive = true

        case .center:
            let centerY = useSafeArea ? guide.centerYAnchor : root.centerYAnchor
            host.view.centerYAnchor.constraint(
                equalTo: centerY,
                constant: verticalMargin
            ).isActive = true

        case .bottom:
            host.view.bottomAnchor.constraint(
                equalTo: referenceBottom,
                constant: -verticalMargin
            ).isActive = true
        }

        applyHorizontalLayoutConstraints(hostView: host.view, root: root)

        window.hitTargetView = host.view

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBannerTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        host.view.addGestureRecognizer(tap)

        host.view.isAccessibilityElement = true
        host.view.accessibilityTraits.insert(.button)
        host.view.accessibilityLabel = "Banner"

        self.window = window
        self.hostController = host

        ensurePanGestureInstalled()
        panGestureRef?.isEnabled = swipeToDismiss || draggable

        window.onLayoutChange = { [weak self] in
            self?.pendingRelayout = true
        }

        presentedVPosition = vPosition
        interactionUnlockTime = .greatestFiniteMagnitude

        root.layoutIfNeeded()
        window.layoutIfNeeded()

        // Reset initial state
        offset = .zero
        offsetTransform = .identity
        effectTransform = .identity
        animationTransform = .identity

        host.view.transform = .identity
        host.view.alpha = 0

        // Resolve presentation style

        let style: PresentationStyle = {
            if presentationStyle == .automatic {
                switch vPosition {
                case .center: return .scale
                case .top, .bottom: return .slide
                }
            }
            return presentationStyle
        }()

        // Initial animation state (before visibility)

        switch style {

        case .slide:

            let initialOffsetY: CGFloat = {
                switch vPosition {
                case .top:
                    return -window.bounds.height
                case .bottom:
                    return window.bounds.height
                case .center:
                    // FIX: use frame instead of bounds
                    return -host.view.frame.height - 40
                }
            }()

            animationTransform = CGAffineTransform(translationX: 0, y: initialOffsetY)

        case .scale:
            effectTransform = CGAffineTransform(scaleX: 0.92, y: 0.92)

        case .fade:
            break

        default:
            break
        }

        applyTransforms()

        window.makeKeyAndVisible()

        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            host.view.alpha = 1

            switch style {
            case .slide:
                self.animationTransform = .identity
            case .scale:
                self.effectTransform = .identity
            case .fade:
                break
            default:
                break
            }

            self.applyTransforms()

        } completion: { [weak self] _ in
            guard let self else { return }

            self.interactionUnlockTime = CACurrentMediaTime()

            self.isAnimatingIn = false
            self.isPresenting = false

            if self.isDismissing == false && self.pendingDismissCompletions.isEmpty == false {
                self.dismiss()
                return
            }

            if self.pendingRelayout {
                self.pendingRelayout = false
                self.remeasure(animated: true)
            } else {
                self.remeasure(animated: false)
            }
        }
    }

    private func applyHorizontalLayoutConstraints(hostView: UIView, root: UIView) {
        let guide = root.safeAreaLayoutGuide
        let useSafeArea = respectsSafeArea

        let leading = useSafeArea ? guide.leadingAnchor : root.leadingAnchor
        let trailing = useSafeArea ? guide.trailingAnchor : root.trailingAnchor

        horizontalConstraints.forEach { $0.isActive = false }
        horizontalConstraints.removeAll()

        switch horizontalLayout {

        case .stretch(let margins):
            let c1 = hostView.leadingAnchor.constraint(equalTo: leading, constant: margins)
            let c2 = hostView.trailingAnchor.constraint(equalTo: trailing, constant: -margins)
            horizontalConstraints = [c1, c2]

        case .centered(let width):
            let centerX = useSafeArea ? guide.centerXAnchor : root.centerXAnchor
            let c1 = hostView.centerXAnchor.constraint(equalTo: centerX)
            let c2 = hostView.widthAnchor.constraint(equalToConstant: width)
            horizontalConstraints = [c1, c2]

        case .leading(let width, let offset):
            let c1 = hostView.leadingAnchor.constraint(equalTo: leading, constant: offset)
            let c2 = hostView.widthAnchor.constraint(equalToConstant: width)
            horizontalConstraints = [c1, c2]

        case .trailing(let width, let offset):
            let c1 = hostView.trailingAnchor.constraint(equalTo: trailing, constant: -offset)
            let c2 = hostView.widthAnchor.constraint(equalToConstant: width)
            horizontalConstraints = [c1, c2]
        }

        NSLayoutConstraint.activate(horizontalConstraints)
    }

    private func applyVerticalPositionConstraints(hostView: UIView, root: UIView) {
        let guide = root.safeAreaLayoutGuide
        let useSafeArea = respectsSafeArea

        NSLayoutConstraint.deactivate(
            root.constraints.filter {
                $0.firstItem as? UIView === hostView &&
                ($0.firstAttribute == .top ||
                 $0.firstAttribute == .bottom ||
                 $0.firstAttribute == .centerY)
            }
        )

        let referenceTop = useSafeArea ? guide.topAnchor : root.topAnchor
        let referenceBottom = useSafeArea ? guide.bottomAnchor : root.bottomAnchor

        switch vPosition {

        case .top:
            hostView.topAnchor.constraint(
                equalTo: referenceTop,
                constant: verticalMargin
            ).isActive = true

        case .center:
            let centerY = useSafeArea ? guide.centerYAnchor : root.centerYAnchor
            hostView.centerYAnchor.constraint(
                equalTo: centerY,
                constant: verticalMargin
            ).isActive = true

        case .bottom:
            hostView.bottomAnchor.constraint(
                equalTo: referenceBottom,
                constant: -verticalMargin
            ).isActive = true
        }
    }

    private func currentLayoutFrame() -> CGRect? {
        guard let hostView = hostController?.view else { return nil }

        let currentTransform = hostView.transform
        hostView.transform = .identity

        let frame = hostView.frame

        hostView.transform = currentTransform
        return frame
    }

    // MARK: - Internals: Layout Measurement

    /// Updates the persistent translation transform from the logical offset.
    private func updateOffsetTransform() {
        offsetTransform = CGAffineTransform(
            translationX: offset.x,
            y: offset.y
        )
    }

    /// Applies the composed transform (effect + offset) to the banner host view.
    ///
    /// This keeps visual effects and positional displacement independent.
    private func applyTransforms() {
        guard let hostView = hostController?.view else { return }
        hostView.transform =
            effectTransform
            .concatenating(animationTransform)
            .concatenating(offsetTransform)
    }

    /// Re-measures the SwiftUI content and stabilizes the banner height.
    ///
    /// This prevents vertical jumps when intrinsic content size changes.
    private func remeasure(animated: Bool = false) {
        guard let window,
              let hostView = hostController?.view else { return }

        heightConstraint?.isActive = false

        let targetWidth = max(hostView.bounds.width, 1)

        hostView.invalidateIntrinsicContentSize()
        hostView.setNeedsLayout()
        hostView.layoutIfNeeded()

        let targetSize = CGSize(
            width: targetWidth,
            height: UIView.layoutFittingCompressedSize.height
        )

        let fittingSize = hostView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        let newHeight = max(minHeight, fittingSize.height)

        let constraint = heightConstraint ?? hostView.heightAnchor.constraint(equalToConstant: newHeight)
        constraint.constant = newHeight
        constraint.isActive = true
        heightConstraint = constraint

        let animations = {
            window.layoutIfNeeded()

            self.applyTransforms()
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: animations
            )
        } else {
            UIView.performWithoutAnimation {
                animations()
            }
        }
    }

    // MARK: - Internals: Auto-dismiss Scheduling

    /// Schedules the auto-dismiss task for the active banner.
    ///
    /// Auto-dismiss is token-safe: if another banner becomes active
    /// before the delay expires, the dismissal is ignored.
    private func scheduleAutoDismiss() {
        dismissTimer?.cancel()

        let seconds = autoDismissAfter
        guard seconds > 0 else { return }

        let tokenAtSchedule = activeToken

        dismissTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run {
                guard let self,
                      self.activeToken == tokenAtSchedule else { return }
                self.dismiss()
            }
        }
    }

    // MARK: - Gesture Recognition & Interaction Policy

    /// Controls whether multiple gesture recognizers may recognize simultaneously.
    ///
    /// LucidBanner explicitly disables simultaneous recognition to avoid
    /// ambiguous interactions between drag, swipe, and tap gestures.
    ///
    /// This guarantees deterministic gesture resolution.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    /// Determines whether a gesture recognizer should receive a touch.
    ///
    /// This method enforces the banner interaction policy:
    /// - When touches are not blocked, gestures outside the banner are ignored.
    /// - When touches are blocked, gestures are constrained to the banner bounds.
    /// - Only banner-related gestures are allowed to proceed.
    ///
    /// This method acts as the first line of defense against unintended interaction.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let hostView = hostController?.view else { return true }

        let location = touch.location(in: hostView)
        let isInsideBanner = hostView.bounds.contains(location)

        // Passthrough mode: ignore touches outside the banner.
        if !blocksTouches && !isInsideBanner {
            return false
        }

        // Blocking mode: gestures are restricted to banner bounds.
        if blocksTouches {
            if gestureRecognizer is UITapGestureRecognizer { return isInsideBanner }
            if gestureRecognizer is UIPanGestureRecognizer { return isInsideBanner }
        }

        return true
    }

    /// Determines whether a gesture may begin based on
    /// interaction state, timing, and banner position.
    public func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {

        // Prevent interaction while the presentation animation is still active.
        if isAnimatingIn {
            return false
        }

        // Prevent interaction immediately after presentation animation.
        if CACurrentMediaTime() < interactionUnlockTime {
            return false
        }

        // Drag mode: always allow pan gestures inside the banner.
        if draggable, gestureRecognizer is UIPanGestureRecognizer {
            return true
        }

        // Swipe-to-dismiss: validate direction and intent.
        if let pan = gestureRecognizer as? UIPanGestureRecognizer,
           let view = pan.view {

            let velocityY = pan.velocity(in: view).y

            switch presentedVPosition {
            case .top:
                // Only upward swipes dismiss a top banner.
                return velocityY < 0

            case .bottom:
                // Only downward swipes dismiss a bottom banner.
                return velocityY > 0

            case .center:
                // Center banners require a strong vertical intent.
                let translation = pan.translation(in: view)
                return abs(translation.y) > abs(translation.x)
                    && abs(velocityY) > 150
            }
        }

        return true
    }

    /// Handles pan gestures for dragging or swipe-to-dismiss,
    /// depending on the current interaction configuration.
    @objc private func handlePanGesture(_ g: UIPanGestureRecognizer) {
        guard let view = hostController?.view else { return }

        // Prevent interaction during initial animation.
        if isAnimatingIn { return }
        if CACurrentMediaTime() < interactionUnlockTime { return }

        // MARK: - DRAG MODE (UNCHANGED)

        if draggable {
            guard let container = view.superview else { return }

            let translation = g.translation(in: container)

            switch g.state {
            case .began:
                dragStartFrameInContainer = view.frame
                dragStartOffset = offset

            case .changed:
                var newOffset = CGPoint(
                    x: dragStartOffset.x + translation.x,
                    y: dragStartOffset.y + translation.y
                )

                let proposedFrame = dragStartFrameInContainer
                    .offsetBy(dx: translation.x, dy: translation.y)

                let insets = container.safeAreaInsets
                let minY = insets.top
                let maxY = container.bounds.height
                    - insets.bottom
                    - dragStartFrameInContainer.height

                if proposedFrame.minY < minY {
                    newOffset.y += (minY - proposedFrame.minY)
                } else if proposedFrame.minY > maxY {
                    newOffset.y -= (proposedFrame.minY - maxY)
                }

                offset = newOffset
                updateOffsetTransform()
                applyTransforms()

            case .ended, .cancelled, .failed:
                UIView.animate(
                    withDuration: 0.25,
                    delay: 0,
                    usingSpringWithDamping: 0.85,
                    initialSpringVelocity: 0.5,
                    options: [.curveEaseOut, .beginFromCurrentState]
                ) {
                    view.alpha = 1.0
                }

            default:
                break
            }
            return
        }

        // MARK: - SWIPE TO DISMISS

        guard let container = view.superview else { return }

        let translation = g.translation(in: container)
        let dy = translation.y

        switch g.state {

        case .began:
            dragStartOffset = offset

        case .changed:

            var newOffset = dragStartOffset

            switch presentedVPosition {
            case .top:
                newOffset.y += min(0, dy)

            case .bottom:
                newOffset.y += max(0, dy)

            case .center:
                let t = max(-80, min(80, dy))
                newOffset.y += t
            }

            offset = newOffset
            updateOffsetTransform()
            applyTransforms()

            let visualY = offset.y - dragStartOffset.y
            view.alpha = max(0.4, 1.0 - abs(visualY) / 120.0)

        case .ended, .cancelled:

            let velocityY = g.velocity(in: view).y
            let totalY = offset.y - dragStartOffset.y

            let shouldDismiss: Bool = {
                switch presentedVPosition {
                case .top:
                    return totalY < -30 || velocityY < -500

                case .bottom:
                    return totalY > 30 || velocityY > 500

                case .center:
                    return abs(totalY) > 40 || abs(velocityY) > 600
                }
            }()

            if shouldDismiss {
                dismiss()
            } else {
                UIView.animate(
                    withDuration: 0.25,
                    delay: 0,
                    usingSpringWithDamping: 0.85,
                    initialSpringVelocity: 0.5,
                    options: [.curveEaseOut, .beginFromCurrentState]
                ) {
                    view.alpha = 1
                    self.offset = self.dragStartOffset
                    self.updateOffsetTransform()
                    self.applyTransforms()
                }
            }

        default:
            break
        }
    }

    /// Lazily installs the pan gesture recognizer on the banner host view.
    ///
    /// The gesture recognizer is reused across runtime configuration updates,
    /// allowing drag or swipe behavior to be enabled or disabled dynamically
    /// without reattaching the view.
    private func ensurePanGestureInstalled() {
        guard let hostView = hostController?.view else { return }
        if panGestureRef?.view === hostView { return }

        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePanGesture(_:))
        )
        pan.cancelsTouchesInView = false
        pan.delegate = self

        hostView.addGestureRecognizer(pan)
        panGestureRef = pan
    }

    /// Handles tap gestures on the banner.
    ///
    /// The tap is ignored if a dismissal animation is in progress.
    /// Otherwise, the registered callback is invoked with the
    /// active banner token and current stage.
    @objc private func handleBannerTap() {
        guard !isDismissing else { return }
        onTap?(activeToken, state.payload.stage)
    }
}
