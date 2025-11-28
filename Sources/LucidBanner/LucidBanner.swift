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
import Combine

// MARK: - Shared State

/// Shared observable state for a single LucidBanner instance.
/// This object is injected into the SwiftUI content and updated by the manager.
@MainActor
public final class LucidBannerState: ObservableObject {
    // MARK: - Text

    /// Main title text. `nil` means no title is shown.
    @Published public var title: String?

    /// Optional secondary text placed below the title.
    @Published public var subtitle: String?

    /// Optional small text used for status or extra information.
    @Published public var footnote: String?

    // MARK: - Icon & animation

    /// System symbol name used for the leading icon (e.g. `arrow.up.circle`).
    @Published public var systemImage: String?

    /// Current animation style applied to the icon.
    @Published public var imageAnimation: LucidBanner.LucidBannerAnimationStyle

    // MARK: - Progress

    /// Optional progress value in the `0...1` range. `nil` hides the progress view.
    @Published public var progress: Double?

    // MARK: - Misc

    /// Optional semantic stage identifier attached to the current banner payload.
    @Published public var stage: String?

    /// Arbitrary key–value storage for advanced scenarios (not interpreted by LucidBanner).
    @Published public var flags: [String: Any] = [:]

    /// Creates a new shared state object for a LucidBanner.
    ///
    /// Empty strings for `title`, `subtitle` and `footnote` are normalized to `nil`.
    ///
    /// - Parameters:
    ///   - title: Optional main title text.
    ///   - subtitle: Optional subtitle text.
    ///   - footnote: Optional small footnote text.
    ///   - systemImage: SF Symbol name for the icon.
    ///   - imageAnimation: Icon animation style.
    ///   - progress: Optional progress value (`0...1`).
    ///   - stage: Optional stage identifier string.
    public init(title: String? = nil,
                subtitle: String? = nil,
                footnote: String? = nil,
                systemImage: String? = nil,
                imageAnimation: LucidBanner.LucidBannerAnimationStyle,
                progress: Double? = nil,
                stage: String? = nil) {
        self.title = (title?.isEmpty == true) ? nil : title
        self.subtitle = (subtitle?.isEmpty == true) ? nil : subtitle
        self.footnote = (footnote?.isEmpty == true) ? nil : footnote
        self.systemImage = systemImage
        self.imageAnimation = imageAnimation
        self.progress = progress
        self.stage = stage
    }
}

// MARK: - Passthrough Window

/// Lightweight UIWindow subclass used only to display the banner.
///
/// It can optionally forward touch events to the underlying app (passthrough mode)
/// while still hosting the banner content on top of everything else.
@MainActor
internal final class LucidBannerWindow: UIWindow {
    /// When `true`, the window is mostly passthrough and forwards hits to `hitTargetView`.
    var isPassthrough: Bool = true

    /// View used as the region that can still receive touches when the window is passthrough.
    weak var hitTargetView: UIView?

    /// Closure invoked every time the window lays out its subviews (e.g. on rotation).
    var onLayoutChange: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutChange?()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isPassthrough else {
            return super.hitTest(point, with: event)
        }
        guard let target = hitTargetView else {
            return nil
        }

        let p = target.convert(point, from: self)
        return target.bounds.contains(p) ? super.hitTest(point, with: event) : nil
    }
}

// MARK: - Manager

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
        let stage: String?
        let onTap: ((_ token: Int, _ stage: String?) -> Void)?
        let viewUI: (LucidBannerState) -> AnyView
        let token: Int
    }

    /// View factory for the currently visible banner content.
    private var contentView: ((LucidBannerState) -> AnyView)?

    // Window/UI
    private var scene: UIWindowScene?
    private var blocksTouches = false
    private var window: LucidBannerWindow?
    private weak var scrimView: UIControl?
    private var hostController: UIHostingController<AnyView>?

    // Timers/flags
    private var dismissTimer: Task<Void, Never>?
    private var isAnimatingIn = false
    private var isDismissing = false

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

    /// Shared observable state injected into the SwiftUI banner content.
    let state = LucidBannerState(title: nil,
                                 subtitle: nil,
                                 footnote: nil,
                                 systemImage: nil,
                                 imageAnimation: .none,
                                 progress: nil,
                                 stage: nil)

    // Config
    private var swipeToDismiss = true
    private var autoDismissAfter: TimeInterval = 0

    // Token/revision
    private var generation: Int = 0
    private var activeToken: Int = 0
    private var revisionForVisible: Int = 0
    private var onTap: ((_ token: Int, _ stage: String?) -> Void)?

    // MARK: - Public API

    /// Presents a new banner with the provided SwiftUI content.
    ///
    /// If a banner is already visible, the behavior depends on `policy`:
    /// - `.enqueue`: the new banner is added to a queue and shown later.
    /// - `.replace`: the current banner is dismissed and the new one replaces it.
    /// - `.drop`: the new request is ignored.
    ///
    /// If the text and progress payload is empty, the call is ignored and the
    /// method returns the current `activeToken`.
    ///
    /// - Parameters:
    ///   - scene: Target `UIWindowScene` where the banner window should be attached.
    ///   - title: Optional main title text.
    ///   - subtitle: Optional secondary text.
    ///   - footnote: Optional small footnote text.
    ///   - systemImage: SF Symbol name for the leading icon.
    ///   - imageAnimation: Icon animation style.
    ///   - progress: Optional progress value (`0...1`).
    ///   - vPosition: Vertical position inside the window.
    ///   - hAlignment: Horizontal alignment inside the window.
    ///   - horizontalMargin: Horizontal padding from the edges when not full-width.
    ///   - verticalMargin: Vertical padding from the top/bottom.
    ///   - autoDismissAfter: Time interval after which the banner is automatically dismissed. `0` disables auto-dismiss.
    ///   - swipeToDismiss: Enables swipe-to-dismiss gesture if `true`.
    ///   - blocksTouches: When `true`, the window captures touches using a scrim.
    ///   - stage: Optional semantic stage identifier associated with the banner.
    ///   - policy: Policy applied when another banner is already visible.
    ///   - onTap: Callback invoked when the banner is tapped.
    ///   - content: SwiftUI view builder that receives the shared `LucidBannerState`.
    /// - Returns: A token that identifies this banner instance.
    @discardableResult
    public func show<Content: View>(scene: UIWindowScene?,
                                    title: String? = nil,
                                    subtitle: String? = nil,
                                    footnote: String? = nil,
                                    systemImage: String? = nil,
                                    imageAnimation: LucidBannerAnimationStyle = .none,
                                    progress: Double? = nil,
                                    vPosition: VerticalPosition = .top,
                                    hAlignment: HorizontalAlignment = .center,
                                    horizontalMargin: CGFloat = 12,
                                    verticalMargin: CGFloat = 10,
                                    autoDismissAfter: TimeInterval = 0,
                                    swipeToDismiss: Bool = true,
                                    blocksTouches: Bool = false,
                                    stage: String? = nil,
                                    policy: ShowPolicy = .enqueue,
                                    onTap: ((_ token: Int, _ stage: String?) -> Void)? = nil,
                                    @ViewBuilder content: @escaping (LucidBannerState) -> Content) -> Int {
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
            guard let progress,
                  progress > 0 else {
                return nil
            }
            return progress
        }()

        let hasContent = normalizedTitle != nil ||
                         normalizedSubtitle != nil ||
                         normalizedFootnote != nil ||
                         (normalizedProgress ?? 0) > 0

        guard hasContent else {
            return activeToken
        }

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
            stage: stage,
            onTap: onTap,
            viewUI: viewFactory,
            token: newToken
        )

        // If a window is active/animating, queue or replace according to policy
        if window != nil || isAnimatingIn || isDismissing {
            switch policy {
            case .drop:
                return activeToken
            case .enqueue:
                queue.append(pending)
                return activeToken
            case .replace:
                queue.removeAll()
                queue.append(pending)
                dismiss { [weak self] in self?.dequeueAndStartIfNeeded() }
                return newToken
            }
        }

        // No banner visible: present now
        activeToken = newToken
        applyPending(pending)
        startShow(with: pending.viewUI)
        return newToken
    }

    /// Updates the currently visible banner in place.
    ///
    /// Only the values that are not `nil` are applied. The `token` parameter can be
    /// used to ensure the update targets a specific banner instance.
    ///
    /// - Parameters:
    ///   - title: Optional new title text.
    ///   - subtitle: Optional new subtitle text.
    ///   - footnote: Optional new footnote text.
    ///   - systemImage: Optional new SF Symbol name.
    ///   - imageAnimation: Optional new icon animation style.
    ///   - progress: Optional new progress value (`0...1`).
    ///   - stage: Optional new stage identifier.
    ///   - onTap: Optional new tap callback.
    ///   - token: Optional banner token to target a specific instance.
    @MainActor
    public func update(title: String? = nil,
                       subtitle: String? = nil,
                       footnote: String? = nil,
                       systemImage: String? = nil,
                       imageAnimation: LucidBanner.LucidBannerAnimationStyle? = nil,
                       progress: Double? = nil,
                       stage: String? = nil,
                       onTap: ((_ token: Int, _ stage: String?) -> Void)? = nil,
                       for token: Int? = nil) {
        guard window != nil, (token == nil || token == activeToken) else {
            return
        }

        // --- Text fields ---

        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue = trimmed.isEmpty ? nil : trimmed
            state.title = newValue
        }

        if let subtitle {
            let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue = trimmed.isEmpty ? nil : trimmed
            state.subtitle = newValue
        }

        if let footnote {
            let trimmed = footnote.trimmingCharacters(in: .whitespacesAndNewlines)
            let newValue = trimmed.isEmpty ? nil : trimmed
            state.footnote = newValue
        }

        // --- Icon & animation ---

        if let systemImage {
            state.systemImage = systemImage
        }

        if let imageAnimation {
            state.imageAnimation = imageAnimation
        }

        // Progress: only clamp and toggle visibility; SwiftUI handles layout.
        if let progress {
            let clamped = max(0, min(1, progress))
            let newProgress: Double? = (clamped > 0) ? clamped : nil
            state.progress = newProgress
        }

        // --- Stage & tap callback ---
        if let stage {
            state.stage = stage
        }
        if let onTap {
            self.onTap = onTap
        }

        revisionForVisible &+= 1
    }

    /// Returns `true` if the given token still corresponds to a visible banner.
    ///
    /// - Parameter token: Banner token returned from `show(...)`.
    /// - Returns: `true` if the banner is currently alive and visible.
    public func isAlive(_ token: Int) -> Bool {
        token == activeToken && window != nil
    }

    // MARK: - Dismiss

    /// Dismisses the current banner, optionally running a completion handler afterwards.
    ///
    /// Dismissal is animated. If a queued banner exists, it will be presented
    /// automatically when the animation completes.
    ///
    /// - Parameter completion: Optional closure invoked after dismissal is fully completed.
    public func dismiss(completion: (() -> Void)? = nil) {
        dismissTimer?.cancel()
        dismissTimer = nil

        guard let window,
              let hostView = hostController?.view else {
            // No visible window: just clean up and call completion.
            hostController = nil
            self.window?.isHidden = true
            self.window = nil
            completion?()
            return
        }

        hostView.isUserInteractionEnabled = false
        panGestureRef?.isEnabled = false
        isDismissing = true

        let offsetY: CGFloat = {
            switch presentedVPosition {
            case .top:    return -window.bounds.height
            case .bottom: return  window.bounds.height
            case .center: return 0
            }
        }()

        UIView.animate(withDuration: 0.35,
                       delay: 0,
                       options: [.curveEaseIn, .beginFromCurrentState]) { [weak self] in
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
            self.isDismissing = false

            Task { @MainActor [weak self] in
                // Small delay to avoid immediate re-attachments jitter.
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                if self.window == nil, !self.isDismissing {
                    self.dequeueAndStartIfNeeded()
                }
                completion?()
            }
        }
    }

    /// Dismisses the banner associated with the given token, if it is still active.
    ///
    /// - Parameters:
    ///   - token: Banner token returned from `show(...)`.
    ///   - completion: Optional closure invoked after dismissal is fully completed.
    public func dismiss(for token: Int, completion: (() -> Void)? = nil) {
        guard token == activeToken else { return }
        dismiss(completion: completion)
    }

    // MARK: - Internals

    /// Starts the presentation of a banner using the provided view factory.
    private func startShow(with viewUI: @escaping (LucidBannerState) -> AnyView) {
        isAnimatingIn = true
        contentView = viewUI
        attachWindowAndPresent()
        scheduleAutoDismiss()
    }

    /// Applies the pending payload to the internal state and layout configuration.
    private func applyPending(_ p: PendingShow) {
        // Scene
        scene = p.scene

        // Text & image.
        state.title = p.title
        state.subtitle = p.subtitle
        state.footnote = p.footnote
        state.systemImage = p.systemImage
        state.imageAnimation = p.imageAnimation

        // Progress & stage
        state.progress = p.progress
        state.stage = p.stage

        // Layout & behavior
        autoDismissAfter = p.autoDismissAfter
        vPosition = p.vPosition
        hAlignment = p.hAlignment
        horizontalMargin = p.horizontalMargin
        verticalMargin = p.verticalMargin
        blocksTouches = p.blocksTouches
        swipeToDismiss = p.blocksTouches ? false : p.swipeToDismiss

        // Tap & revision
        onTap = p.onTap
        revisionForVisible = 0
    }

    /// Dequeues the next pending banner and starts showing it, if possible.
    private func dequeueAndStartIfNeeded() {
        guard !isAnimatingIn, !isDismissing, window == nil else { return }
        guard !queue.isEmpty else {
            return
        }

        let next = queue.removeFirst()
        isAnimatingIn = true
        activeToken = next.token

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyPending(next)
            self.presentedVPosition = next.vPosition
            self.startShow(with: next.viewUI)
        }
    }

    /// Attaches the banner window to the given scene and runs the intro animation.
    private func attachWindowAndPresent() {
        guard let scene = self.scene else {
            return
        }

        // Create custom banner window.
        let window = LucidBannerWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        window.isPassthrough = !blocksTouches
        window.accessibilityViewIsModal = blocksTouches

        // Build SwiftUI host view.
        let content = contentView?(state) ?? AnyView(EmptyView())
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear

        // Root container view.
        let root = UIView()
        root.backgroundColor = .clear
        root.translatesAutoresizingMaskIntoConstraints = false

        // Background scrim (optional overlay for blocking touches).
        let scrim = UIControl()
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.backgroundColor = UIColor.black.withAlphaComponent(blocksTouches ? 0.08 : 0.0)
        scrim.isUserInteractionEnabled = blocksTouches

        // Compose hierarchy.
        let rootViewController = UIViewController()
        rootViewController.view = root
        window.rootViewController = rootViewController

        root.addSubview(scrim)
        root.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        // Safe area layout guide used for positioning.
        let guide = root.safeAreaLayoutGuide
        let useSafeArea = LucidBanner.useSafeArea

        // --- Constraints ---
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

        // Gesture recognizers.
        window.hitTargetView = host.view

        if swipeToDismiss {
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

        // Accessibility.
        host.view.isAccessibilityElement = true
        host.view.accessibilityTraits.insert(.button)
        host.view.accessibilityLabel = "Banner"

        // Store references.
        self.window = window
        self.hostController = host
        self.scrimView = scrim

        // Rotation: SwiftUI + Auto Layout will re-layout automatically.
        window.onLayoutChange = nil

        // --- Presentation animation ---
        presentedVPosition = vPosition
        interactionUnlockTime = CACurrentMediaTime() + 0.25
        host.view.alpha = 0

        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        switch presentedVPosition {
        case .top:
            host.view.transform = CGAffineTransform(translationX: 0, y: -window.bounds.height)
        case .bottom:
            host.view.transform = CGAffineTransform(translationX: 0, y: window.bounds.height)
        case .center:
            host.view.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }

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
        }
    }

    /// Schedules automatic dismissal if `autoDismissAfter` is greater than zero.
    private func scheduleAutoDismiss() {
        dismissTimer?.cancel()
        let seconds = autoDismissAfter
        guard seconds > 0 else { return }
        let tokenAtSchedule = activeToken

        dismissTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.dismiss(for: tokenAtSchedule)
        }
    }

    // MARK: - Gestures

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

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

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if CACurrentMediaTime() < interactionUnlockTime { return false }

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

    /// Handles vertical pan gestures to dismiss or restore the banner.
    @objc private func handlePanGesture(_ g: UIPanGestureRecognizer) {
        guard let view = hostController?.view else { return }
        if CACurrentMediaTime() < interactionUnlockTime { return }

        let dy = g.translation(in: view).y

        func applyTransform(for y: CGFloat) {
            switch presentedVPosition {
            case .top:
                view.transform = CGAffineTransform(translationX: 0, y: min(0, y))
            case .bottom:
                view.transform = CGAffineTransform(translationX: 0, y: max(0, y))
            case .center:
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
                dismiss(for: activeToken)
            } else {
                UIView.animate(withDuration: 0.25,
                               delay: 0,
                               usingSpringWithDamping: 0.85,
                               initialSpringVelocity: 0.5,
                               options: [.curveEaseOut, .beginFromCurrentState]) {
                    view.alpha = 1
                    view.transform = .identity
                }
            }
        default:
            break
        }
    }

    /// Handles tap gestures on the banner and forwards them to the `onTap` callback.
    @objc private func handleBannerTap() {
        guard !isDismissing else { return }
        onTap?(activeToken, state.stage)
    }
}
