//
//  LucidBanner
//
//  Created by Marino Faggiana.
//  Licensed under the MIT License.
//
//  Description:
//  Flexible scene-aware banner system built with SwiftUI + UIKit.
//  Provides animated, interruptible, queueable in-app notifications,
//  with optional touch-passthrough, swipe-to-dismiss and auto-dismiss.
//
//  Architecture:
//  - `LucidBanner.shared` manages lifecycle, queuing, scheduling and dismissal.
//  - `LucidBannerState` exposes observable UI data to SwiftUI.
//  - A lightweight UIWindow subclass hosts the SwiftUI banner above all scenes.
//  - Only a single state object is reused; each banner is identified by a token.
//
//  Notes:
//  Designed to be lightweight and non-intrusive. No View contains presentation
//  logic; all coordination is handled by the manager layer.
//

import SwiftUI
import UIKit

/// Global manager responsible for showing, updating and dismissing Lucid banners.
///
/// The manager owns a single shared `LucidBannerState` instance that is injected into
/// the SwiftUI content. Only one banner window is visible at a time, but multiple
/// requests can be queued according to the selected `ShowPolicy`.
@MainActor
public final class LucidBanner: NSObject, UIGestureRecognizerDelegate {
    /// Shared singleton instance.
    public static let shared = LucidBanner()

    /// When `true`, the banner positions itself inside the safe area.
    public static var useSafeArea: Bool = true

    /// Policy describing how to handle a new request when a banner is already visible.
    public enum ShowPolicy {
        /// Immediately dismiss the current banner and show the new one, dropping any queue.
        case replace
        /// Queue the new banner and display it after the currently visible one is dismissed.
        case enqueue
        /// Ignore the new request if a banner is already visible or animating.
        case drop
    }

    /// Visual animation style for the icon inside the banner.
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
    }

    /// Vertical placement of the banner inside the window.
    public enum VerticalPosition {
        case top
        case center
        case bottom
    }

    /// Horizontal alignment of the banner inside the window.
    public enum HorizontalAlignment {
        case left
        case center
        case right
    }

    // Pending payload used for queueing
    private struct PendingShow {
        let scene: UIWindowScene?
        let title: String?
        let subtitle: String?
        let footnote: String?
        let systemImage: String?
        let imageAnimation: LucidBannerAnimationStyle
        let progress: Double?
        let vPosition: VerticalPosition
        let hAlignment: HorizontalAlignment
        let horizontalMargin: CGFloat
        let verticalMargin: CGFloat
        let autoDismissAfter: TimeInterval
        let swipeToDismiss: Bool
        let blocksTouches: Bool
        let draggable: Bool
        let stage: String?
        let onTap: ((_ token: Int?, _ stage: String?) -> Void)?
        let viewUI: (LucidBannerState) -> AnyView
        let token: Int
    }

    /// View factory for the currently visible banner content.
    private var contentView: ((LucidBannerState) -> AnyView)?

    // Window/UI
    private var scene: UIWindowScene?
    private var blocksTouches = false
    private var window: LucidBannerWindow?
    private var hostController: UIHostingController<AnyView>?

    // Timers/flags
    private var dismissTimer: Task<Void, Never>?
    private var isAnimatingIn = false
    private var isDismissing = false
    private var pendingRelayout = false
    private var isPresenting = false
    private var pendingDismissCompletions: [() -> Void] = []

    // Size
    private var heightConstraint: NSLayoutConstraint?
    private let minHeight: CGFloat = 44

    // Position
    private var vPosition: VerticalPosition = .top
    private var hAlignment: HorizontalAlignment = .center
    private var horizontalMargin: CGFloat = 12
    private var verticalMargin: CGFloat = 10
    private var presentedVPosition: VerticalPosition = .top

    // Queue
    private var queue: [PendingShow] = []

    // Gestures
    private var interactionUnlockTime: CFTimeInterval = 0
    private weak var panGestureRef: UIPanGestureRecognizer?
    private var dragStartTransform: CGAffineTransform = .identity
    private var isUserDraggingBanner = false
    private var dragStartFrameInContainer: CGRect = .zero
    private var pendingGeometryWorkItem: DispatchWorkItem?

    /// Shared observable state injected into the SwiftUI banner content.
    let state = LucidBannerState(
        title: nil,
        subtitle: nil,
        footnote: nil,
        systemImage: nil,
        imageAnimation: .none,
        progress: nil,
        draggable: false,
        stage: nil
    )

    // Config
    private var swipeToDismiss = false
    private var autoDismissAfter: TimeInterval = 0
    private var draggable: Bool = false

    // Token/revision
    private var generation: Int = 0
    private var activeToken: Int?
    private var onTap: ((_ token: Int?, _ stage: String?) -> Void)?

    // MARK: - Init
    override public init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneGeometryChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        Task { @MainActor in
            dismissAll(animated: false)

            window?.isHidden = true
            window = nil
            activeToken = nil
        }
    }

    @objc private func handleSceneGeometryChange() {
        pendingGeometryWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.clampCurrentTransformToBounds()
        }

        pendingGeometryWorkItem = workItem

        // ~2–3 frames delay: stable after rotation and interactive iPad resizing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
    }

    // MARK: - Public API

    /// Presents a new Lucid banner in the specified scene.
    ///
    /// The banner content is provided by a SwiftUI view builder that receives the shared `LucidBannerState`.
    /// If another banner is already visible, the behavior depends on `policy` (`replace`, `enqueue`, `drop`).
    ///
    /// - Parameters:
    ///   - scene: Target `UIWindowScene` where the banner window should be attached.
    ///   - title: Optional title text for the banner.
    ///   - subtitle: Optional subtitle text.
    ///   - footnote: Optional footnote text (smaller status text).
    ///   - systemImage: Optional SF Symbol name for the leading icon.
    ///   - imageAnimation: Icon animation style.
    ///   - progress: Optional progress value in `0...1` range.
    ///   - vPosition: Vertical position (top, center, bottom).
    ///   - hAlignment: Horizontal alignment (left, center, right) for internal layout decisions.
    ///   - horizontalMargin: Horizontal margin from safe area edges.
    ///   - verticalMargin: Vertical margin from safe area edges.
    ///   - autoDismissAfter: Optional auto-dismiss delay in seconds (0 disables).
    ///   - swipeToDismiss: Enables swipe-to-dismiss behavior when `true`.
    ///   - blocksTouches: When `true`, touches behind the banner are blocked by a scrim.
    ///   - draggable: When `true`, the banner can be dragged freely instead of only swiped to dismiss.
    ///   - stage: Optional semantic stage value attached to the state.
    ///   - policy: Show policy when another banner is already visible.
    ///   - onTap: Optional tap handler that receives the banner token and stage.
    ///   - content: SwiftUI content builder for the banner body.
    /// - Returns: A token identifying this banner instance.
    @discardableResult
    public func show<Content: View>(scene: UIWindowScene?,
                                    title: String? = nil,
                                    subtitle: String? = nil,
                                    footnote: String? = nil,
                                    systemImage: String? = nil,
                                    imageAnimation: LucidBannerAnimationStyle = .none,
                                    progress: Double? = nil,
                                    vPosition: VerticalPosition = .center,
                                    hAlignment: HorizontalAlignment = .center,
                                    horizontalMargin: CGFloat = 12,
                                    verticalMargin: CGFloat = 10,
                                    autoDismissAfter: TimeInterval = 0,
                                    swipeToDismiss: Bool = false,
                                    blocksTouches: Bool = false,
                                    draggable: Bool = false,
                                    stage: Stage? = nil,
                                    policy: ShowPolicy = .enqueue,
                                    onTap: ((_ token: Int?, _ stage: String?) -> Void)? = nil,
                                    @ViewBuilder content: @escaping (LucidBannerState) -> Content) -> Int? {
        // Normalize text fields to avoid showing empty strings.
        let normalizedTitle: String? = {
            guard let text = title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return nil
            }
            return text
        }()

        let normalizedSubtitle: String? = {
            guard let text = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return nil
            }
            return text
        }()

        let normalizedFootnote: String? = {
            guard let text = footnote?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return nil
            }
            return text
        }()

        let normalizedProgress: Double? = {
            guard let progress else { return nil }
            let clamped = max(0, min(1, progress))
            return clamped
        }()

        // Prepare view factory bound to the shared state
        let viewFactory: (LucidBannerState) -> AnyView = { s in AnyView(content(s)) }

        // Generate a token
        generation &+= 1
        let newToken = generation

        // Build pending payload
        let pending = PendingShow(
            scene: scene,
            title: normalizedTitle,
            subtitle: normalizedSubtitle,
            footnote: normalizedFootnote,
            systemImage: systemImage,
            imageAnimation: imageAnimation,
            progress: normalizedProgress,
            vPosition: vPosition,
            hAlignment: hAlignment,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin,
            autoDismissAfter: autoDismissAfter,
            swipeToDismiss: swipeToDismiss,
            blocksTouches: blocksTouches,
            draggable: draggable,
            stage: stage?.rawValue,
            onTap: onTap,
            viewUI: viewFactory,
            token: newToken
        )

        // If a banner is attached or in transition, handle according to policy.
        if window != nil || isPresenting || isDismissing {
            switch policy {
            case .drop:
                return activeToken
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

        // No banner visible: present now
        activeToken = newToken
        presentedVPosition = vPosition
        applyPending(pending)
        isPresenting = true
        startShow(with: pending.viewUI)
        return newToken
    }

    /// Updates the currently visible banner state and optionally reschedules auto-dismiss.
    ///
    /// Only non-`nil` parameters are applied; other properties remain unchanged.
    /// Some changes (like text and progress visibility) can trigger a relayout.
    ///
    /// - Parameters:
    ///   - title: Optional new title.
    ///   - subtitle: Optional new subtitle.
    ///   - footnote: Optional new footnote text.
    ///   - systemImage: Optional new SF Symbol name.
    ///   - imageAnimation: Optional new icon animation style.
    ///   - progress: Optional new progress (`0...1`).
    ///   - stage: Optional new stage value.
    ///   - autoDismissAfter: Optional new auto-dismiss delay; `0` disables auto-dismiss.
    ///   - onTap: Optional new tap handler.
    ///   - token: Optional banner token to restrict the update to a specific banner.
    public func update(title: String? = nil,
                       subtitle: String? = nil,
                       footnote: String? = nil,
                       systemImage: String? = nil,
                       imageAnimation: LucidBanner.LucidBannerAnimationStyle? = nil,
                       progress: Double? = nil,
                       stage: Stage? = nil,
                       autoDismissAfter: TimeInterval? = nil,
                       onTap: ((_ token: Int?, _ stage: String?) -> Void)? = nil,
                       for token: Int? = nil) {
        guard window != nil, (token == nil || token == activeToken) else {
            return
        }

        var needsRelayout = false
        var shouldRescheduleAutoDismiss = false

        // Text
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue = trimmed.isEmpty ? nil : trimmed
            if newValue != state.title { needsRelayout = true }
            state.title = newValue
        }

        if let subtitle {
            let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue = trimmed.isEmpty ? nil : trimmed
            if newValue != state.subtitle { needsRelayout = true }
            state.subtitle = newValue
        }

        if let footnote {
            let trimmed = footnote.trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue = trimmed.isEmpty ? nil : trimmed
            if newValue != state.footnote { needsRelayout = true }
            state.footnote = newValue
        }

        // Icon & animation
        if let systemImage {
            if systemImage != state.systemImage { needsRelayout = true }
            state.systemImage = systemImage
        }

        if let imageAnimation {
            state.imageAnimation = imageAnimation
        }

        // Progress
        if let progress {
            let clamped = max(0, min(1, progress))
            let newProgress: Double? = clamped

            let oldVisible = (state.progress != nil)
            let newVisible = (newProgress != nil)

            if oldVisible != newVisible {
                needsRelayout = true
            }

            state.progress = newProgress
        }

        // Stage, autoDismissAfter, tap
        if let stage = stage?.rawValue {
            if stage != state.stage { needsRelayout = true }
            state.stage = stage
        }
        if let autoDismissAfter {
            self.autoDismissAfter = autoDismissAfter

            if autoDismissAfter > 0 {
                // Enable or change auto-dismiss: reschedule timer from now
                shouldRescheduleAutoDismiss = true
            } else {
                // Disable auto-dismiss (0 or negative)
                dismissTimer?.cancel()
                dismissTimer = nil
            }
        }

        if let onTap {
            self.onTap = onTap
        }

        guard let window = self.window else {
            return
        }

        // Layout / remeasure
        if needsRelayout {
            if isAnimatingIn || isDismissing {
                pendingRelayout = true
            } else {
                remeasure(animated: true)
            }
        } else {
            UIView.performWithoutAnimation {
                window.layoutIfNeeded()
            }
        }

        // Reschedule auto-dismiss if needed
        if shouldRescheduleAutoDismiss {
            scheduleAutoDismiss()
        }
    }

    /// Translates the current banner in window space so that its center moves to the given point.
    ///
    /// This method preserves any existing transform (e.g. from dragging) and applies a delta transform
    /// so movement is relative to the current position.
    ///
    /// - Parameters:
    ///   - x: Target center X coordinate in window coordinates.
    ///   - y: Target center Y coordinate in window coordinates.
    ///   - token: Optional banner token to restrict movement to a specific banner.
    ///   - animated: When `true`, applies a smooth animation to the movement.
    public func move(toX x: CGFloat, y: CGFloat, for token: Int? = nil, animated: Bool = true) {
        guard window != nil, token == nil || token == activeToken else { return }
        guard let window, let hostView = hostController?.view else { return }

        // Current center in window coordinates (includes current transform / drag)
        let frameInWindow = hostView.convert(hostView.bounds, to: window)
        let currentCenter = CGPoint(x: frameInWindow.midX, y: frameInWindow.midY)

        let dx = x - currentCenter.x
        let dy = y - currentCenter.y

        let targetTransform = hostView.transform.translatedBy(x: dx, y: dy)

        let animations = {
            hostView.transform = targetTransform
        }

        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.5,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: animations,
                completion: nil
            )
        } else {
            animations()
        }
    }

    /// Resets any custom transform applied to the banner, restoring its layout
    /// to the position defined purely by Auto Layout constraints.
    ///
    /// - Parameters:
    ///   - token: Optional banner token to restrict the reset.
    ///   - animated: When `true`, animates the transform reset.
    public func resetPosition(for token: Int? = nil, animated: Bool = true) {
        guard window != nil, token == nil || token == activeToken else {
            return
        }
        guard let hostView = hostController?.view else {
            return
        }

        let animations = {
            hostView.transform = .identity
        }

        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.5,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: animations,
                completion: nil
            )
        } else {
            animations()
        }
    }

    /// Returns the current frame of the banner host view in window coordinates,
    /// including any active transform (e.g. drag or custom positioning).
    ///
    /// - Parameter token: Optional banner token to ensure the frame belongs
    ///   to the currently visible banner.
    /// - Returns: The frame in window space, or `nil` if no matching banner is visible.
    public func currentFrameInWindow(for token: Int? = nil) -> CGRect? {
        guard window != nil, token == nil || token == activeToken else { return nil }
        guard let window,
              let hostView = hostController?.view else {
            return nil
        }

        return hostView.convert(hostView.bounds, to: window)
    }

    /// Returns the underlying UIKit host view for the currently visible banner.
    ///
    /// Intended for advanced integrations that need direct access to the view’s
    /// transform or custom animations.
    ///
    /// - Parameter token: Optional banner token to validate against the active banner.
    /// - Returns: The host UIView if the token matches, otherwise `nil`.
    public func currentHostView(for token: Int? = nil) -> UIView? {
        guard token == nil || token == activeToken else { return nil }
        return hostController?.view
    }

    /// Enables or disables the swipe-to-dismiss / drag gesture for the current banner.
    ///
    /// Useful for modes like minimized icons where dragging should be disabled while
    /// keeping other interactions active.
    ///
    /// - Parameters:
    ///   - isEnabled: `true` to allow dragging, `false` to lock the banner in place.
    ///   - token: Optional banner token to ensure the change applies to the active banner.
    public func setDraggingEnabled(_ isEnabled: Bool, for token: Int? = nil) {
        guard window != nil, token == nil || token == activeToken else {
            return
        }
        panGestureRef?.isEnabled = isEnabled
    }

    /// Requests a re-measure and layout pass for the current banner content.
    ///
    /// This should be called after significant content changes that affect the
    /// intrinsic height, especially when using custom layouts in the SwiftUI view.
    ///
    /// - Parameter animated: When `true`, applies a small animation to the height change.
    public func requestRelayout(animated: Bool) {
        remeasure(animated: animated)
    }

    /// Returns whether the provided token still corresponds to an active, visible banner.
    ///
    /// - Parameter token: Banner token to check.
    /// - Returns: `true` if the token matches the current banner and a window is attached.
    public func isAlive(_ token: Int?) -> Bool {
        token == activeToken && window != nil
    }

    /// Returns the currently active `LucidBannerState` for the specified token.
    ///
    /// This method provides safe, read-only access to the banner state managed by `LucidBanner`.
    /// It is intended for external controllers (such as gesture coordinators or layout managers)
    /// that need to inspect properties of the active banner—e.g., whether it is minimized,
    /// its current progress value, or any UI-related fields.
    ///
    /// The function performs a strict token check: only the banner associated with the
    /// `activeToken` may expose its state. If the provided token does not match the active
    /// banner, the method returns `nil`. No internal state is modified.
    ///
    /// - Parameter token: The banner identifier for which the caller requests the state.
    /// - Returns: The `LucidBannerState` associated with the active token, or `nil` if the
    ///            token does not correspond to the currently displayed banner.
    public func currentState(for token: Int) -> LucidBannerState? {
        guard activeToken == token else { return nil }
        return state
    }

    // MARK: - Dismiss Public API

    /// Dismisses the currently visible banner, optionally animating it off-screen,
    /// and then starts the next queued banner if any.
    ///
    /// - Parameter completion: Optional closure called after the banner has been fully dismissed.
    public func dismiss(completion: (() -> Void)? = nil) {
        // Always store the completion: all callers of dismiss
        // should be notified when the *current* banner is gone.
        if let completion {
            pendingDismissCompletions.append(completion)
        }

        // Cancel auto-dismiss timer
        dismissTimer?.cancel()
        dismissTimer = nil

        // No active window → no banner to kill.
        // We still call all pending completions, but we do NOT touch the queue.
        guard let window,
              let hostView = hostController?.view else {
            hostController = nil
            self.window?.isHidden = true
            self.window = nil
            heightConstraint = nil
            isPresenting = false
            isDismissing = false

            let completions = pendingDismissCompletions
            pendingDismissCompletions.removeAll()
            completions.forEach { $0() }

            return
        }

        // If a dismiss is already in progress, do NOT start another animation.
        // The current cycle will eventually clean up and run all completions.
        if isDismissing {
            return
        }

        // First dismiss call: start the animation for this *single* banner.
        isPresenting = false
        isDismissing = true

        hostView.isUserInteractionEnabled = false
        panGestureRef?.isEnabled = false

        let offsetY: CGFloat = {
            switch presentedVPosition {
            case .top:    return -window.bounds.height
            case .bottom: return  window.bounds.height
            case .center: return 0
            }
        }()

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) { [weak self] in
            guard let self else { return }
            hostView.alpha = 0
            hostView.transform = (self.presentedVPosition == .center)
                ? CGAffineTransform(scaleX: 0.9, y: 0.9)
                : CGAffineTransform(translationX: 0, y: offsetY)
            hostView.layer.shadowOpacity = 0
            self.window?.layoutIfNeeded()
        } completion: { [weak self] _ in
            guard let self else { return }

            self.hostController = nil
            window.isHidden = true
            self.window = nil
            self.heightConstraint = nil
            self.isDismissing = false

            self.dequeueAndStartIfNeeded()

            let completions = self.pendingDismissCompletions
            self.pendingDismissCompletions.removeAll()
            completions.forEach { $0() }
        }
    }

    public func dismissAsync() async {
        await withCheckedContinuation { continuation in
            self.dismiss {
                continuation.resume()
            }
        }
    }

    /// Schedules a dismissal for the currently visible banner after a delay.
    ///
    /// If a new banner becomes active before the delay expires, the dismissal is ignored.
    ///
    /// - Parameters:
    ///   - seconds: Delay in seconds before dismissing; `0` dismisses immediately.
    ///   - completion: Optional closure called after the banner has been dismissed.
    public func dismiss(after seconds: TimeInterval, completion: (() -> Void)? = nil) {
        dismissTimer?.cancel()

        guard seconds > 0 else {
            dismiss(completion: completion)
            return
        }

        let tokenAtSchedule = activeToken

        dismissTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

            await MainActor.run {
                guard let self else { return }
                guard self.activeToken == tokenAtSchedule else { return }
                self.dismiss(completion: completion)
            }
        }
    }

    public func dismissAsync(after seconds: TimeInterval) async {
        await withCheckedContinuation { continuation in
            self.dismiss(after: seconds) {
                continuation.resume()
            }
        }
    }

    public func dismissAll(animated: Bool = true, completion: (() -> Void)? = nil) {
        // If no window is present, clean state and fire completion.
        guard let window else {
            activeToken = nil
            completion?()
            return
        }

        // Animation block for hiding the window
        let hideWindow = {
            window.alpha = 0
        }

        // Cleanup block to fully reset the banner system
        let finalize: () -> Void = { [weak self] in
            // Destroy the state machine
            self?.activeToken = nil

            // Remove and destroy the window
            window.isHidden = true
            window.windowLevel = .normal
            window.rootViewController = nil
            self?.window = nil

            // Notify caller
            completion?()
        }

        // Execute with or without animation
        if animated {
            UIView.animate(withDuration: 0.20, animations: hideWindow) { _ in
                finalize()
            }
        } else {
            hideWindow()
            finalize()
        }
    }

    // MARK: - Internals

    /// Starts the presentation flow for the given view factory, attaching the window
    /// and scheduling auto-dismiss if configured.
    ///
    /// - Parameter viewUI: Factory that produces the SwiftUI content for the banner.
    private func startShow(with viewUI: @escaping (LucidBannerState) -> AnyView) {
        isAnimatingIn = true
        pendingRelayout = false
        contentView = viewUI
        attachWindowAndPresent()
        scheduleAutoDismiss()
    }

    /// Applies the pending configuration payload to the manager’s internal state
    /// before presentation.
    ///
    /// - Parameter p: Pending payload describing the banner to be shown.
    private func applyPending(_ p: PendingShow) {
        scene = p.scene

        // Reset layout-related flags so each banner starts clean
        state.isMinimized = false
        state.title = p.title
        state.subtitle = p.subtitle
        state.footnote = p.footnote
        state.systemImage = p.systemImage
        state.imageAnimation = p.imageAnimation
        state.progress = p.progress
        state.stage = p.stage
        state.draggable = p.draggable

        autoDismissAfter = p.autoDismissAfter
        vPosition = p.vPosition
        hAlignment = p.hAlignment
        horizontalMargin = p.horizontalMargin
        verticalMargin = p.verticalMargin
        blocksTouches = p.blocksTouches
        draggable = p.draggable && !p.blocksTouches

        // If touches are blocked, swipeToDismiss is forced off
        swipeToDismiss = p.blocksTouches ? false : p.swipeToDismiss

        onTap = p.onTap
    }

    /// Dequeues the next banner (if any) and starts its presentation,
    /// provided no other banner is currently animating or attached.
    private func dequeueAndStartIfNeeded() {
        // Do not start a new banner while one is being presented or dismissed,
        // or if a banner window is still attached.
        guard !isPresenting,
              !isDismissing,
              window == nil else {
            return
        }

        guard let next = queue.first else {
            return
        }

        queue.removeFirst()

        activeToken = next.token
        presentedVPosition = next.vPosition

        // Apply the content/configuration for this request
        applyPending(next)

        // From now on, we consider a banner as "presenting" (including animation-in + visible).
        isPresenting = true

        startShow(with: next.viewUI)
    }

    /// Creates and attaches the hosting window, installs constraints, gestures,
    /// and runs the presentation animation for the current banner.
    private func attachWindowAndPresent() {
        guard let scene = self.scene else {
            return
        }

        let window = LucidBannerWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        window.isPassthrough = !blocksTouches
        window.accessibilityViewIsModal = blocksTouches

        // SwiftUI host
        let content = contentView?(state) ?? AnyView(EmptyView())
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear

        // Root
        let root = UIView()
        root.backgroundColor = .clear

        // Scrim
        let scrim = UIControl()
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.backgroundColor = UIColor.black.withAlphaComponent(blocksTouches ? 0.08 : 0.0)
        scrim.isUserInteractionEnabled = blocksTouches

        let rootViewController = UIViewController()
        rootViewController.view = root
        window.rootViewController = rootViewController

        root.addSubview(scrim)
        root.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        let guide = root.safeAreaLayoutGuide
        let useSafeArea = LucidBanner.useSafeArea

        var constraints: [NSLayoutConstraint] = []

        constraints += [
            scrim.topAnchor.constraint(equalTo: root.topAnchor),
            scrim.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ]

        // Vertical position.
        switch vPosition {
        case .top:
            constraints.append(
                host.view.topAnchor.constraint(
                    equalTo: useSafeArea ? guide.topAnchor : root.topAnchor,
                    constant: verticalMargin
                )
            )
        case .center:
            constraints.append(
                host.view.centerYAnchor.constraint(
                    equalTo: useSafeArea ? guide.centerYAnchor : root.centerYAnchor
                )
            )
        case .bottom:
            constraints.append(
                host.view.bottomAnchor.constraint(
                    equalTo: useSafeArea ? guide.bottomAnchor : root.bottomAnchor,
                    constant: -verticalMargin
                )
            )
        }

        // Horizontal full-width inside safe area (or full window if disabled)
        let leadingAnchor = useSafeArea ? guide.leadingAnchor : root.leadingAnchor
        let trailingAnchor = useSafeArea ? guide.trailingAnchor : root.trailingAnchor

        constraints.append(
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalMargin)
        )
        constraints.append(
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalMargin)
        )

        NSLayoutConstraint.activate(constraints)

        // Gestures
        window.hitTargetView = host.view

        if swipeToDismiss || draggable {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            pan.cancelsTouchesInView = false
            pan.delegate = self
            host.view.addGestureRecognizer(pan)
            panGestureRef = pan
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBannerTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        host.view.addGestureRecognizer(tap)

        // Accessibility
        host.view.isAccessibilityElement = true
        host.view.accessibilityTraits.insert(.button)
        host.view.accessibilityLabel = "Banner"

        self.window = window
        self.hostController = host

        // Handle rotation or other layout passes: just mark that a relayout is needed.
        // The actual remeasure will be performed at a safe moment (e.g. after show
        // animation or after an explicit `update(...)` that triggers it).
        window.onLayoutChange = { [weak self] in
            guard let self else { return }
            self.pendingRelayout = true
        }

        // Presentation animation (solo fade + leggero scale, niente offset che litiga con i vincoli)
        presentedVPosition = vPosition
        interactionUnlockTime = CACurrentMediaTime() + 0.25
        host.view.alpha = 0
        host.view.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)

        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            host.view.alpha = 1
            host.view.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isAnimatingIn = false
            if self.pendingRelayout {
                self.pendingRelayout = false
                self.remeasure(animated: true)
            } else {
                self.remeasure(animated: false)
            }
        }
    }

    /// Forces a re-measure of the SwiftUI content and applies a layout update.
    ///
    /// Uses the actual window width minus safe area and horizontal margins
    /// to compute a stable height, so dynamic content (like progress) can
    /// grow or shrink without breaking vertical positioning.
    ///
    /// - Parameter animated: When `true`, animates the resulting height change.
    private func remeasure(animated: Bool = false) {
        guard let window,
              let hostView = hostController?.view else { return }

        if let existing = heightConstraint {
            existing.isActive = false
        }

        let targetWidth: CGFloat = max(hostView.bounds.width, 1)

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

        let heightConstraint: NSLayoutConstraint
        if let existing = self.heightConstraint {
            existing.constant = newHeight
            heightConstraint = existing
        } else {
            let created = hostView.heightAnchor.constraint(equalToConstant: newHeight)
            self.heightConstraint = created
            heightConstraint = created
        }

        heightConstraint.isActive = true

        let animations = {
            window.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: animations,
                completion: nil
            )
        } else {
            UIView.performWithoutAnimation {
                animations()
            }
        }
    }

    /// Schedules an auto-dismiss timer for the current banner if a delay is configured.
    ///
    /// If `autoDismissAfter` is `0` or less, the timer is not started.
    private func scheduleAutoDismiss() {
        dismissTimer?.cancel()

        let seconds = autoDismissAfter
        guard seconds > 0 else { return }

        let tokenAtSchedule = activeToken

        dismissTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

            await MainActor.run {
                guard let self else { return }
                guard self.activeToken == tokenAtSchedule else { return }
                self.dismiss()
            }
        }
    }

    // MARK: - Gestures

    /// Controls whether multiple gesture recognizers should be recognized simultaneously.
    ///
    /// For LucidBanner, simultaneous recognition is always disabled, so this returns `false`.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    /// Controls whether a gesture recognizer should receive a touch based on banner bounds
    /// and the current touch-blocking configuration.
    ///
    /// - Parameters:
    ///   - gestureRecognizer: The gesture recognizer about to receive the touch.
    ///   - touch: The incoming touch.
    /// - Returns: `true` if the gesture recognizer should handle the touch.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldReceive touch: UITouch) -> Bool {
        guard let hostView = hostController?.view else { return true }
        let p = touch.location(in: hostView)
        let inside = hostView.bounds.contains(p)

        if !blocksTouches && !inside { return false }

        if blocksTouches {
            if gestureRecognizer is UITapGestureRecognizer { return inside }
            if gestureRecognizer is UIPanGestureRecognizer { return inside }
        }
        return true
    }

    /// Determines whether a gesture recognizer should begin based on current interaction
    /// lock timing, drag mode, and swipe direction.
    ///
    /// - Parameter gestureRecognizer: The gesture recognizer requesting permission to begin.
    /// - Returns: `true` if the gesture recognizer is allowed to start.
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if CACurrentMediaTime() < interactionUnlockTime { return false }

        // In draggable mode, always allow the pan to begin when touching inside the banner.
        if draggable, gestureRecognizer is UIPanGestureRecognizer {
            return true
        }

        if let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view {
            let velocityY = pan.velocity(in: view).y
            switch presentedVPosition {
            case .top:
                return velocityY < 0
            case .bottom:
                return velocityY > 0
            case .center:
                let t = pan.translation(in: view)
                return abs(t.y) > abs(t.x) && abs(velocityY) > 150
            }
        }
        return true
    }

    /// Handles the pan gesture attached to the banner view.
    ///
    /// In draggable mode, the gesture moves the banner freely. In non-draggable mode,
    /// the gesture is interpreted as a swipe-to-dismiss interaction.
    ///
    /// - Parameter g: Active pan gesture recognizer.
    @objc private func handlePanGesture(_ g: UIPanGestureRecognizer) {
        guard let view = hostController?.view else { return }

        // Prevent interaction for a very short time after show animation
        if CACurrentMediaTime() < interactionUnlockTime { return }

        // DRAG MODE: pan repositions the banner instead of dismissing it.
        if draggable {
            guard let container = view.superview else { return }

            // Use container coordinates for stable translation and clamping.
            let translation = g.translation(in: container)

            switch g.state {
            case .began:
                isUserDraggingBanner = true

                // Store the starting transform so we can apply deltas on top of it.
                dragStartTransform = view.transform

                // Capture the starting frame in container space for stable math.
                dragStartFrameInContainer = view.frame

            case .changed:
                // Proposed transform from pan gesture.
                var transform = dragStartTransform.translatedBy(x: translation.x, y: translation.y)

                // Proposed frame in container coordinates based on the starting frame.
                let proposedFrame = dragStartFrameInContainer.offsetBy(dx: translation.x, dy: translation.y)

                // Allowed range (safe-area aware).
                let insets = container.safeAreaInsets
                let minX = insets.left
                let maxX = container.bounds.width - insets.right - dragStartFrameInContainer.width
                let minY = insets.top
                let maxY = container.bounds.height - insets.bottom - dragStartFrameInContainer.height

                // Clamp X by correcting transform.tx.
                if proposedFrame.minX < minX {
                    transform.tx += (minX - proposedFrame.minX)
                } else if proposedFrame.minX > maxX {
                    transform.tx -= (proposedFrame.minX - maxX)
                }

                // Clamp Y by correcting transform.ty.
                if proposedFrame.minY < minY {
                    transform.ty += (minY - proposedFrame.minY)
                } else if proposedFrame.minY > maxY {
                    transform.ty -= (proposedFrame.minY - maxY)
                }

                view.transform = transform
                view.alpha = 1.0

            case .ended, .cancelled, .failed:
                isUserDraggingBanner = false

                // Persist the final transform as the new baseline for the next drag.
                dragStartTransform = view.transform

                // Small spring to "settle" visually, but keep the final position.
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

        // DISMISS MODE: original swipe-to-dismiss behavior.
        let translation = g.translation(in: view)
        let dy = translation.y

        func applyTransform(for y: CGFloat) {
            switch presentedVPosition {
            case .top:
                // Dragging up (negative) moves the banner further up
                view.transform = CGAffineTransform(translationX: 0, y: min(0, y))
            case .bottom:
                // Dragging down (positive) moves the banner further down
                view.transform = CGAffineTransform(translationX: 0, y: max(0, y))
            case .center:
                // For center placement, allow a small vertical offset and scale
                let t = max(-80, min(80, y))
                let s = max(0.9, 1.0 - abs(t) / 800.0)
                view.transform = CGAffineTransform(translationX: 0, y: t).scaledBy(x: s, y: s)
            }
        }

        switch g.state {
        case .changed:
            applyTransform(for: dy)
            view.alpha = max(0.4, 1.0 - abs(view.transform.ty) / 120.0)

        case .ended, .cancelled:
            let vy = g.velocity(in: view).y

            let shouldDismiss: Bool = {
                switch presentedVPosition {
                case .top:
                    return (dy < -30) || (vy < -500)
                case .bottom:
                    return (dy > 30) || (vy > 500)
                case .center:
                    return abs(dy) > 40 || abs(vy) > 600
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
                    view.transform = .identity
                }
            }

        default:
            break
        }
    }

    private func clampCurrentTransformToBounds() {
        guard let view = hostController?.view else { return }
        guard let container = view.superview else { return }
        let currentFrame = view.frame

        let insets = container.safeAreaInsets
        let minX = insets.left
        let maxX = container.bounds.width - insets.right - currentFrame.width
        let minY = insets.top
        let maxY = container.bounds.height - insets.bottom - currentFrame.height

        let clampedOriginX = max(minX, min(currentFrame.minX, maxX))
        let clampedOriginY = max(minY, min(currentFrame.minY, maxY))

        let dx = clampedOriginX - currentFrame.minX
        let dy = clampedOriginY - currentFrame.minY

        if dx != 0 || dy != 0 {
            view.transform = view.transform.translatedBy(x: dx, y: dy)
        }
    }

    /// Handles tap events on the banner host view and forwards them to the configured `onTap` handler.
    @objc private func handleBannerTap() {
        guard !isDismissing else { return }
        onTap?(activeToken, state.stage)
    }
}
