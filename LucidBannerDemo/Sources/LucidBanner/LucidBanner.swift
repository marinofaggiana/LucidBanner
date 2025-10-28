// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2025 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UIKit
import Combine

/// Shows a transient, SwiftUI-based banner in its own window above the status bar.
///
/// The banner is rendered inside a transparent `UIWindow` tied to the provided `scene` (or the
/// first active scene if `nil`). Only one banner is visible at a time:
/// - `.enqueue`: the new banner is queued and will appear after the current one is dismissed.
/// - `.replace`: the current banner is dismissed and the new one is shown next.
/// - `.drop`: the request is ignored if a banner is already visible.
///
/// The banner auto-sizes within `minWidth...maxWidth` (or `fixedWidth` if provided) and can be
/// positioned at the top/center/bottom (`vPosition`) with left/center/right alignment (`hAlignment`).
/// Horizontal/vertical margins are respected. When `blocksTouches` is `true`, a light scrim consumes
/// background interactions; otherwise, touches pass through except over the banner. A swipe gesture
/// can dismiss the banner if `swipeToDismiss` is enabled.
///
/// You can update the banner later using `update(...)` with the returned token. Tap events invoke
/// `onTapWithContext`, which provides the banner token, a monotonic revision number, and the current
/// `stage` string (useful to disambiguate tap intentions across state changes).
///
/// Token semantics:
/// - If the banner is shown immediately (no banner visible), this returns the **new token**.
/// - If `policy == .replace`, this returns the **new token** that will replace the current banner.
/// - If `policy == .enqueue`, this returns the **current active token** (the queued banner will receive
///   its own token, but the return value here remains the active one).
///
/// - Parameters:
///   - scene: Target `UIScene` (multiwindow/iPad). If `nil`, the first foreground scene is used.
///   - title: Main text of the banner. Empty/whitespace-only values are normalized to an empty string.
///   - subtitle: Optional secondary text below the title. Empty strings are treated as `nil`.
///   - footnote: Optional tertiary line below the subtitle. Empty strings are treated as `nil`.
///   - textColor: Color used for textual elements.
///   - systemImage: Optional SF Symbol name to display beside the text.
///   - imageColor: Tint for the SF Symbol.
///   - imageAnimation: Animation to apply to the icon (e.g., `.rotate`, `.breathe`).
///   - progress: Optional progress (0…1). Values `<= 0` hide the progress bar.
///   - progressColor: Tint color for the progress bar.
///   - fixedWidth: If set, forces the banner width. Otherwise the banner fits content within bounds.
///   - minWidth: Minimum width when auto-sizing (ignored if `fixedWidth` is set).
///   - maxWidth: Maximum width when auto-sizing (ignored if `fixedWidth` is set).
///   - vPosition: Vertical placement (`.top`, `.center`, `.bottom`).
///   - hAlignment: Horizontal alignment (`.left`, `.center`, `.right`).
///   - horizontalMargin: Horizontal inset from screen edges (when not center-aligned).
///   - verticalMargin: Vertical inset from safe areas at top/bottom.
///   - autoDismissAfter: Auto-dismiss delay in seconds; `0` disables auto-dismiss.
///   - swipeToDismiss: Enables swipe gesture to dismiss the banner.
///   - blocksTouches: If `true`, blocks touches behind the banner and shows a light scrim.
///   - stage: Arbitrary label for the current logical phase (e.g., `"uploading"`). Passed to tap handler.
///   - policy: How to handle the request when another banner is visible: `.enqueue`, `.replace`, or `.drop`.
///   - onTapWithContext: Called on tap with `(token, revision, stage)`.
///   - content: SwiftUI view builder bound to the shared `LucidBannerState`.
///
/// - Returns: An `Int` token identifying the banner instance you can later pass to `update(...)` or
///            `dismiss(for:)`. See “Token semantics” above for values returned under each policy.
///
/// - Note:
///   - This API is `@MainActor`; call it from the main thread.
///   - The banner will not appear if **all** of `title`, `subtitle`, `footnote`, and `progress` are empty/zero.

/// LucidBannerState holds all observable data shared with the SwiftUI view.
/// It is updated whenever the banner’s appearance or content changes.
@MainActor
public final class LucidBannerState: ObservableObject {
    @Published public var title: String
    @Published public var subtitle: String?
    @Published public var footnote: String?
    @Published public var textColor: UIColor

    @Published public var systemImage: String?
    @Published public var imageColor: UIColor
    @Published public var imageAnimation: LucidBanner.LucidBannerAnimationStyle

    @Published public var progress: Double?
    @Published public var progressColor: UIColor

    @Published public var stage: String?
    @Published public var flags: [String: Any] = [:]

    public init(title: String,
                subtitle: String? = nil,
                footnote: String? = nil,
                textColor: UIColor,
                systemImage: String? = nil,
                imageColor: UIColor,
                imageAnimation: LucidBanner.LucidBannerAnimationStyle,
                progress: Double? = nil,
                progressColor: UIColor,
                stage: String? = nil) {
        self.title = title
        self.subtitle = (subtitle?.isEmpty == true) ? nil : subtitle
        self.footnote = (footnote?.isEmpty == true) ? nil : footnote
        self.textColor = textColor

        self.systemImage = systemImage
        self.imageColor = imageColor
        self.imageAnimation = imageAnimation

        self.progress = progress
        self.progressColor = progressColor

        self.stage = stage
    }
}

// MARK: - Window

/// Custom UIWindow subclass that allows optional passthrough touches.
/// When `isPassthrough` is true, only the banner view intercepts touch events.
@MainActor
internal final class LucidBannerWindow: UIWindow {
    var isPassthrough: Bool = true
    weak var hitTargetView: UIView?

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

/// LucidBanner is a singleton manager for showing animated, SwiftUI-based banners.
/// Each banner is rendered in a transparent UIWindow above the status bar.
@MainActor
final public class LucidBanner: NSObject, UIGestureRecognizerDelegate {
    /// Shared instance used to show and update banners.
    public static let shared = LucidBanner()

    /// Determines what happens if a banner is already showing.
    public enum ShowPolicy {
        /// Replaces the current banner immediately.
        case replace
        /// Queues the new banner to be shown after the current one.
        case enqueue
        /// Drops the new banner entirely.
        case drop
    }

    /// Supported image animation styles.
    public enum LucidBannerAnimationStyle {
        case none, rotate, pulse, pulsebyLayer, breathe, bounce, wiggle, scale
    }

    public enum VerticalPosition {
        case top, center, bottom
    }

    public enum HorizontalAlignment {
        case left, center, right
    }

    /// Internal structure for queued banners.
    private struct PendingShow {
        let scene: UIScene?
        let title: String
        let subtitle: String?
        let footnote: String?
        let textColor: UIColor
        let systemImage: String?
        let imageColor: UIColor
        let imageAnimation: LucidBannerAnimationStyle
        let progress: Double?
        let progressColor: UIColor
        let fixedWidth: CGFloat?
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let vPosition: VerticalPosition
        let hAlignment: HorizontalAlignment
        let horizontalMargin: CGFloat
        let verticalMargin: CGFloat
        let autoDismissAfter: TimeInterval
        let swipeToDismiss: Bool
        let blocksTouches: Bool
        let stage: String?
        let onTapWithContext: ((_ token: Int, _ revision: Int, _ stage: String?) -> Void)?
        let viewUI: (LucidBannerState) -> AnyView
        let token: Int
    }

    // View factory
    private var contentView: ((LucidBannerState) -> AnyView)?

    private var scene: UIScene?
    private var blocksTouches = false
    private var window: LucidBannerWindow?
    private weak var scrimView: UIControl?
    private var hostController: UIHostingController<AnyView>?

    // Timers/flags
    private var dismissTimer: Task<Void, Never>?
    private var isAnimatingIn = false
    private var isDismissing = false
    private var pendingRelayout = false
    private var lockWidthUntilSettled = true

    // Size
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var minWidth: CGFloat = 220
    private var maxWidth: CGFloat = 420
    private let minHeight: CGFloat = 44
    private var fixedWidth: CGFloat?

    // Position
    private var vPosition: VerticalPosition = .top
    private var hAlignment: HorizontalAlignment = .center
    private var horizontalMargin: CGFloat = 12
    private var verticalMargin: CGFloat = 10

    // Add this to LucidBanner's private properties
    // Keep the position used by the currently visible banner.
    // Prevents exit animation from picking up a new vPosition.
    private var presentedVPosition: VerticalPosition = .top

    // Queue
    private var queue: [PendingShow] = []

    // Debounce for swipe gestures right after presentation
    private var interactionUnlockTime: CFTimeInterval = 0
    private weak var panGestureRef: UIPanGestureRecognizer?

    // Shared state
    let state = LucidBannerState(title: "",
                                 subtitle: nil,
                                 footnote: nil,
                                 textColor: .label,
                                 systemImage: nil,
                                 imageColor: .label,
                                 imageAnimation: .none,
                                 progress: nil,
                                 progressColor: .label,
                                 stage: nil)

    // Config
    private var swipeToDismiss = true
    private var autoDismissAfter: TimeInterval = 0

    // Token/revision
    private var generation: Int = 0
    private var activeToken: Int = 0
    private var revisionForVisible: Int = 0
    private var onTapWithContext: ((_ token: Int, _ revision: Int, _ stage: String?) -> Void)?

    // MARK: - PUBLIC

    /// Displays a new banner window with the provided content and behavior.
    /// - Returns: A unique token identifying this banner instance.
    @discardableResult
    public func show<Content: View>(scene: UIScene? = nil,
                                    title: String,
                                    subtitle: String? = nil,
                                    footnote: String? = nil,
                                    textColor: UIColor = .label,
                                    systemImage: String? = nil,
                                    imageColor: UIColor = .label,
                                    imageAnimation: LucidBannerAnimationStyle = .none,
                                    progress: Double? = nil,
                                    progressColor: UIColor = .label,
                                    fixedWidth: CGFloat? = nil,
                                    minWidth: CGFloat = 220,
                                    maxWidth: CGFloat = 420,
                                    vPosition: VerticalPosition = .top,
                                    hAlignment: HorizontalAlignment = .center,
                                    horizontalMargin: CGFloat = 12,
                                    verticalMargin: CGFloat = 10,
                                    autoDismissAfter: TimeInterval = 0,
                                    swipeToDismiss: Bool = true,
                                    blocksTouches: Bool = false,
                                    stage: String? = nil,
                                    policy: ShowPolicy = .enqueue,
                                    onTapWithContext: ((_ token: Int, _ revision: Int, _ stage: String?) -> Void)? = nil,
                                    @ViewBuilder content: @escaping (LucidBannerState) -> Content) -> Int {
        // Normalize input WITHOUT touching shared state.
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = trimmedTitle.isEmpty ? "" : trimmedTitle

        let normalizedSubtitle: String? = {
            guard let s = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }()

        let normalizedFootnote: String? = {
            guard let f = footnote?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty else { return nil }
            return f
        }()

        let normalizedProgress: Double? = {
            guard let p = progress, p > 0 else { return nil }
            return p
        }()

        // If nothing meaningful to show, keep current token.
        let hasContent = !normalizedTitle.isEmpty
                       || (normalizedSubtitle != nil)
                       || (normalizedFootnote != nil)
                       || (normalizedProgress ?? 0) > 0
        guard hasContent else { return activeToken }

        // Use the state provided to the view factory (do NOT capture a stale instance).
        let viewFactory: (LucidBannerState) -> AnyView = { s in AnyView(content(s)) }

        // Pre-generate token for this banner.
        generation &+= 1
        let newToken = generation

        // Build the pending payload (no state mutation here).
        let pending = PendingShow(
            scene: scene,
            title: normalizedTitle,
            subtitle: normalizedSubtitle,
            footnote: normalizedFootnote,
            textColor: textColor,
            systemImage: systemImage,
            imageColor: imageColor,
            imageAnimation: imageAnimation,
            progress: normalizedProgress,
            progressColor: progressColor,
            fixedWidth: fixedWidth,
            minWidth: minWidth,
            maxWidth: maxWidth,
            vPosition: vPosition,
            hAlignment: hAlignment,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin,
            autoDismissAfter: autoDismissAfter,
            swipeToDismiss: swipeToDismiss,
            blocksTouches: blocksTouches,
            stage: stage,
            onTapWithContext: onTapWithContext,
            viewUI: viewFactory,
            token: newToken
        )

        // If a banner is visible or animating, do NOT touch state. Queue or replace.
        if window != nil || isAnimatingIn || isDismissing {
            switch policy {
            case .drop:
                // Explicitly drop: return current active token, nothing changes.
                return activeToken
            case .enqueue:
                queue.append(pending)
                // Still return the current active token (the queued one isn't visible yet).
                return activeToken
            case .replace:
                queue.removeAll()
                queue.append(pending)
                // Dismiss current; the queued 'pending' will be started in completion.
                dismiss { [weak self] in self?.dequeueAndStartIfNeeded() }
                // Return the token of the replacing banner immediately to avoid ambiguity.
                return newToken
            }
        }

        // No banner is visible: apply and present now.
        activeToken = newToken
        applyPending(pending)
        startShow(with: pending.viewUI)
        return newToken
    }

    /// Updates the current banner’s content and appearance.
    ///
    /// Only applies if the banner with the given token is still active.
    /// Use this to change progress, image, or stage without dismissing.
    ///
    /// - Parameters:
    ///   - title: Optional new title.
    ///   - subtitle: Optional new subtitle.
    ///   - footnote: Optional new footnote.
    ///   - systemImage: Optional new icon.
    ///   - imageColor: Optional new tint color.
    ///   - imageAnimation: Optional new animation style.
    ///   - progress: Optional progress (0…1).
    ///   - stage: Optional new logical stage.
    ///   - onTapWithContext: Updated tap handler.
    ///   - token: Token of the banner to update.
    public func update(title: String? = nil,
                       subtitle: String? = nil,
                       footnote: String? = nil,
                       textColor: UIColor? = nil,
                       systemImage: String? = nil,
                       imageColor: UIColor? = nil,
                       imageAnimation: LucidBannerAnimationStyle? = nil,
                       progress: Double? = nil,
                       progressColor: UIColor? = nil,
                       stage: String? = nil,
                       onTapWithContext: ((_ token: Int, _ revision: Int, _ stage: String?) -> Void)? = nil,
                       for token: Int? = nil) {
        if (token != nil && token != activeToken) || window == nil {
            return
        }

        // Snapshot old values for change detection
        let oldTitle = state.title
        let oldSub = state.subtitle
        let oldFootnote = state.footnote
        let oldImage = state.systemImage
        let oldStage = state.stage

        // Normalize title/subtitle/footnote
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            state.title = trimmed.isEmpty ? "" : trimmed
        }
        if let subtitle {
            let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            state.subtitle = trimmed.isEmpty ? nil : trimmed
        }
        if let footnote {
            let trimmed = footnote.trimmingCharacters(in: .whitespacesAndNewlines)
            state.footnote = trimmed.isEmpty ? nil : trimmed
        }
        if let textColor {
            state.textColor = textColor
        }

        if let systemImage {
            state.systemImage = systemImage
        }
        if let imageColor {
            state.imageColor = imageColor
        }
        if let imageAnimation {
            state.imageAnimation = imageAnimation
        }

        // Clamp progress to [0,1] and hide when <= 0
        if let progress {
            let clamped = max(0, min(1, progress))
            state.progress = (clamped > 0) ? clamped : nil
        }
        if let progressColor {
            state.progressColor = progressColor
        }

        if let stage {
            state.stage = stage
        }
        if let onTapWithContext {
            self.onTapWithContext = onTapWithContext
        }

        hostController?.view.invalidateIntrinsicContentSize()

        // Detect what actually changed
        let textChanged = (oldTitle != state.title) || (oldSub != state.subtitle) || (oldFootnote != state.footnote)
        let imageChanged = (oldImage != state.systemImage)
        let stageChanged = (oldStage != state.stage)

        // Bump revision for any meaningful state change so tap handlers can disambiguate
        if textChanged || imageChanged || stageChanged {
            revisionForVisible &+= 1
        }

        // Re-measure only when text or image changed (stage-only changes shouldn't resize)
        if textChanged || imageChanged {
            remeasureAndSetWidthConstraint(animated: true, force: false)
        }
    }

    public func isAlive(_ token: Int) -> Bool {
        token == activeToken && window != nil
    }

    /// Dismisses the current banner with an exit animation coherent with its entry.
    /// - Parameter completion: Called after the animation finishes.
    public func dismiss(completion: (() -> Void)? = nil) {
        dismissTimer?.cancel()
        dismissTimer = nil

        guard let window,
              let hostView = hostController?.view else {
            hostController = nil
            self.window?.isHidden = true
            self.window = nil
            widthConstraint = nil
            heightConstraint = nil
            completion?()
            return
        }

        // Immediately disable interactions and swipe
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

            // Fully tear down current window
            self.hostController = nil
            window.isHidden = true
            self.window = nil
            self.widthConstraint = nil
            self.heightConstraint = nil
            self.isDismissing = false

            // Schedule next only after a short safety delay (to prevent reflash)
            Task { @MainActor [weak self] in
                // Give the render loop a full frame to release the old window
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                guard let self else { return }

                // Ensure window really gone before starting new
                if self.window == nil, !self.isDismissing {
                    self.dequeueAndStartIfNeeded()
                }
                completion?()
            }
        }
    }

    /// Dismisses a banner by token, if it is still active.
    ///
    /// - Parameters:
    ///   - token: The token returned from `show`.
    ///   - completion: Executed after the animation completes.
    public func dismiss(for token: Int, completion: (() -> Void)? = nil) {
        guard token == activeToken else {
            return
        }
        dismiss(completion: completion)
    }

    // MARK: - Private

    private func setSize(width: CGFloat?, height: CGFloat?, animated: Bool = true) {
        self.fixedWidth = width
        guard let window,
              let view = hostController?.view else {
            return
        }

        if let width {
            if let widthConstraint {
                widthConstraint.constant = width
            } else {
                let constraint = view.widthAnchor.constraint(equalToConstant: width)
                constraint.isActive = true
                widthConstraint = constraint
            }
        } else {
            remeasureAndSetWidthConstraint(animated: animated, force: true)
        }

        if let height {
            if let heightConstraint {
                heightConstraint.constant = height
            } else {
                let constraint = view.heightAnchor.constraint(equalToConstant: height)
                constraint.isActive = true
                heightConstraint = constraint
            }
        } else {
            heightConstraint?.isActive = false
            heightConstraint = nil
        }

        if animated {
            UIView.animate(withDuration: 0.2) { window.layoutIfNeeded() }
        } else {
            window.layoutIfNeeded()
        }
    }

    private func startShow(with viewUI: @escaping (LucidBannerState) -> AnyView) {
        lockWidthUntilSettled = true
        isAnimatingIn = true
        pendingRelayout = false
        contentView = viewUI

        if window == nil {
            attachWindowAndPresent()
        } else {
            replaceContentInternal(remeasureWidth: false)
            remeasureAndSetWidthConstraint(animated: false, force: true)
        }

        scheduleAutoDismiss()
    }

    // Apply all pending parameters to the live state right before presenting.
    // This centralizes state mutation so `show(...)` can stay side-effect free when enqueueing.
    private func applyPending(_ p: PendingShow) {
        self.scene = p.scene

        // Text & colors
        state.title = p.title
        state.subtitle = p.subtitle
        state.footnote = p.footnote
        state.textColor = p.textColor

        // Image & animation
        state.systemImage = p.systemImage
        state.imageColor = p.imageColor
        state.imageAnimation = p.imageAnimation

        // Progress & stage
        state.progress = p.progress
        state.progressColor = p.progressColor
        state.stage = p.stage

        // Layout & behavior
        self.autoDismissAfter = p.autoDismissAfter
        self.fixedWidth = p.fixedWidth
        self.minWidth = p.minWidth
        self.maxWidth = p.maxWidth
        self.vPosition = p.vPosition
        self.hAlignment = p.hAlignment
        self.horizontalMargin = p.horizontalMargin
        self.verticalMargin = p.verticalMargin
        self.blocksTouches = p.blocksTouches
        self.swipeToDismiss = p.blocksTouches ? false : p.swipeToDismiss

        // Tap & revision
        self.onTapWithContext = p.onTapWithContext
        self.revisionForVisible = 0
    }

    /// Dequeues the next pending banner and starts it, if possible.
    private func dequeueAndStartIfNeeded() {
        guard !isAnimatingIn, !isDismissing, window == nil else { return }
        guard !queue.isEmpty else { return }

        // Pop next banner in queue
        let next = queue.removeFirst()

        // Prevent race conditions: mark as animating before attach
        isAnimatingIn = true
        activeToken = next.token

        // Apply configuration and present after short delay
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyPending(next)

            // Ensure vPosition reset is honored
            self.presentedVPosition = next.vPosition
            self.startShow(with: next.viewUI)
        }
    }

    private func attachWindowAndPresent() {
        guard let scene: UIWindowScene = (self.scene as? UIWindowScene) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
        else {
            return
        }

        let window = LucidBannerWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        window.isPassthrough = !blocksTouches
        window.accessibilityViewIsModal = blocksTouches

        // Hosting SwiftUI
        let content = contentView?(state) ?? AnyView(EmptyView())
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear

        // Root (scrim + banner)
        let root = UIView()
        root.backgroundColor = .clear
        root.translatesAutoresizingMaskIntoConstraints = false

        let scrim = UIControl()
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.backgroundColor = UIColor.black.withAlphaComponent(blocksTouches ? 0.08 : 0.0)
        scrim.isUserInteractionEnabled = blocksTouches

        window.rootViewController = UIViewController()
        window.rootViewController?.view = root

        root.addSubview(scrim)
        root.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false

        var constraints: [NSLayoutConstraint] = []
        // Scrim full screen
        constraints += [
            scrim.topAnchor.constraint(equalTo: root.topAnchor),
            scrim.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ]

        // Vertical position
        switch vPosition {
        case .top:
            constraints.append(host.view.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor,
                                                              constant: verticalMargin))
        case .center:
            constraints.append(host.view.centerYAnchor.constraint(equalTo: root.centerYAnchor))
        case .bottom:
            constraints.append(host.view.bottomAnchor.constraint(equalTo: root.safeAreaLayoutGuide.bottomAnchor,
                                                                 constant: -verticalMargin))
        }

        // Horizontal alignment
        switch hAlignment {
        case .center:
            constraints.append(host.view.centerXAnchor.constraint(equalTo: root.centerXAnchor))
        case .left:
            constraints.append(host.view.leadingAnchor.constraint(equalTo: root.leadingAnchor,
                                                                  constant: horizontalMargin))
        case .right:
            constraints.append(host.view.trailingAnchor.constraint(equalTo: root.trailingAnchor,
                                                                   constant: -horizontalMargin))
        }

        // Min height
        constraints.append(host.view.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight))
        NSLayoutConstraint.activate(constraints)

        // Hugging/Compression
        host.view.setContentHuggingPriority(.required, for: .vertical)
        host.view.setContentCompressionResistancePriority(.required, for: .vertical)
        host.view.setContentHuggingPriority(.required, for: .horizontal)
        host.view.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Gestures
        window.hitTargetView = host.view
        var panGesture: UIPanGestureRecognizer?
        if swipeToDismiss {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            pan.cancelsTouchesInView = false
            pan.delegate = self                         // <<— important
            host.view.addGestureRecognizer(pan)
            panGesture = pan
            panGestureRef = pan                         // <<— keep a weak ref
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBannerTap))
        tap.cancelsTouchesInView = false
        if let panGesture { tap.require(toFail: panGesture) }
        host.view.addGestureRecognizer(tap)

        host.view.isAccessibilityElement = true
        host.view.accessibilityTraits.insert(.button)
        host.view.accessibilityLabel = state.title.isEmpty ? "Banner" : state.title

        self.window = window
        self.hostController = host
        self.scrimView = scrim

        if let width = fixedWidth {
            let c = host.view.widthAnchor.constraint(equalToConstant: width)
            c.isActive = true
            widthConstraint = c
        } else {
            remeasureAndSetWidthConstraint(animated: false, force: true)
        }

        // Snapshot the exact position used by this visible banner
        presentedVPosition = vPosition

        // Debounce swipe interactions for a short time after showing
        interactionUnlockTime = CACurrentMediaTime() + 0.25

        // Avoid flashing in wrong place: fade in after layout
        host.view.alpha = 0

        // Make visible so Auto Layout resolves final frames
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        // Set initial off-screen transform using the *actual* window bounds
        switch presentedVPosition {
        case .top:
            host.view.transform = CGAffineTransform(translationX: 0, y: -window.bounds.height)
        case .bottom:
            host.view.transform = CGAffineTransform(translationX: 0, y:  window.bounds.height)
        case .center:
            host.view.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }

        // Animate in
        UIView.animate(withDuration: 0.5,
                       delay: 0,
                       usingSpringWithDamping: 0.85,
                       initialSpringVelocity: 0.5,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            host.view.alpha = 1
            host.view.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            self.isAnimatingIn = false
            self.lockWidthUntilSettled = false
            if self.pendingRelayout {
                self.remeasureAndSetWidthConstraint(animated: true, force: true)
                self.pendingRelayout = false
            }
        }
    }

    private func replaceContentInternal(remeasureWidth: Bool) {
        guard let host = hostController else {
            return
        }
        let newView = contentView?(state) ?? AnyView(EmptyView())

        host.rootView = newView
        if remeasureWidth {
            remeasureAndSetWidthConstraint(animated: false, force: false)
        }
        window?.layoutIfNeeded()
    }

    private func remeasureAndSetWidthConstraint(animated: Bool, force: Bool) {
        guard let window,
              let host = hostController else {
            return
        }

        if isAnimatingIn && lockWidthUntilSettled && !force {
            pendingRelayout = true
            return
        }

        if fixedWidth != nil {
            return
        }

        state.flags["measuring"] = true
        defer { state.flags["measuring"] = false }

        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let availableWidth = window.bounds.width - (horizontalMargin * 2)
        let widthCap = min(max(0, availableWidth), maxWidth)
        let fitting = host.sizeThatFits(in: CGSize(width: widthCap, height: UIView.layoutFittingCompressedSize.height))
        let target = min(max(fitting.width, minWidth), widthCap)

        if let widthConstraint {
            let current = widthConstraint.constant
            let newWidth = (force ? target : max(target, current))
            guard abs(newWidth - current) > 0.5 else { return }
            widthConstraint.constant = newWidth
        } else {
            let constraint = host.view.widthAnchor.constraint(equalToConstant: target)
            constraint.isActive = true
            widthConstraint = constraint
        }

        if animated {
            UIView.animate(withDuration: 0.20) { window.layoutIfNeeded() }
        } else {
            UIView.performWithoutAnimation { window.layoutIfNeeded() }
        }
    }

    private func scheduleAutoDismiss() {
        dismissTimer?.cancel()
        let seconds = self.autoDismissAfter
        guard seconds > 0 else {
            return
        }
        let tokenAtSchedule = activeToken

        dismissTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            self?.dismiss(for: tokenAtSchedule)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Debounce: do not begin pan too soon after presentation
        if CACurrentMediaTime() < interactionUnlockTime {
            return false
        }

        // Directional guard: allow only meaningful initial direction
        if let pan = gestureRecognizer as? UIPanGestureRecognizer,
           let view = pan.view {
            let velocityY = pan.velocity(in: view).y
            switch presentedVPosition {
            case .top:
                return velocityY < 0   // swipe up only
            case .bottom:
                return velocityY > 0   // swipe down only
            case .center:
                // At center require a clear vertical intent
                let t = pan.translation(in: view)
                return abs(t.y) > abs(t.x) && abs(velocityY) > 150
            }
        }
        return true
    }

    @objc private func handlePanGesture(_ g: UIPanGestureRecognizer) {
        guard let view = hostController?.view else { return }

        // Safety: ignore gestures that start too early (debounce window)
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
                case .top:    return (dy < -30) || (vy < -500)
                case .bottom: return (dy >  30) || (vy >  500)
                case .center: return abs(dy) > 40 || abs(vy) > 600
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

    @objc private func handleBannerTap() {
        guard !isDismissing else { return }
        onTapWithContext?(activeToken, revisionForVisible, state.stage)
    }
}
