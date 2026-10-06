![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platform](https://img.shields.io/badge/platform-iOS_17+-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

<div align="center">
    <img src="LucidBanner.png" alt="Logo of LucidBanner" width="256" height="256" />
</div>

# LucidBanner

A scene-scoped, SwiftUI-based banner presentation system for iOS. LucidBanner renders transient content in a dedicated `UIWindow`, above the app interface, while keeping presentation lifecycle, queueing, gestures, layout, and updates outside the SwiftUI view.

Originally developed for the **Nextcloud iOS** app.  
Author: **Marino Faggiana** • License: **MIT**

> **Experimental API** — LucidBanner is under active development. Public APIs and behavior may change before a stable 1.0 release.

## Highlights

- **Scene-aware:** each `UIWindowScene` has an independent banner engine, queue, and token space.
- **Deterministic queueing:** choose `.enqueue`, `.replace`, or `.drop` for each presentation request.
- **Payload-driven configuration:** content, colors, layout, interactions, progress, stage, and timing are described by `LucidBannerPayload`.
- **Passive SwiftUI rendering:** the supplied SwiftUI view renders `LucidBannerState`; lifecycle logic stays in `LucidBanner`.
- **Incremental live updates:** apply `LucidBannerPayload.Update` patches to the active banner.
- **Flexible placement:** top, center, or bottom placement; stretch, centered, leading, and trailing horizontal layouts.
- **Interaction controls:** optional swipe-to-dismiss, draggable banners, touch blocking, and tap callbacks.
- **Presentation styles:** automatic, slide, scale, and fade transitions.
- **Variant support:** `LucidBannerVariantCoordinator` toggles a banner between standard and alternate variants, applies a resolver-provided payload update, and repositions the active host view.

## Requirements

- iOS 17.0+
- Swift 6.0+
- SwiftUI and UIKit

## Installation

LucidBanner includes a Swift Package manifest.

### Swift Package Manager

In Xcode, choose **File → Add Package Dependencies…**, enter the repository URL, select the desired version or branch, then add **LucidBanner** to the target.

For example, you can declare a tagged version from another package:

```swift
dependencies: [
    .package(url: "https://github.com/marinofaggiana/LucidBanner.git", from: "0.7.1")
]
```

The library product is named `LucidBanner`. This README describes the current source tree; when using a release tag, consult the README at that tag for its API and behavior.

## Quick start

Obtain the banner associated with your interface’s `UIWindowScene` from `LucidBannerRegistry`. The registry creates one `LucidBanner` instance per scene and keeps its queue isolated from other windows. Banner, registry, state, and variant coordinator APIs run on the main actor.

The example below selects the first foreground scene for a single-window app. In a multi-window app, pass the scene belonging to the view or view controller that triggered the request.

```swift
import SwiftUI
import UIKit
import LucidBanner

@MainActor
struct ContentView: View {
    @State private var token: Int?

    private var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    var body: some View {
        VStack(spacing: 16) {
            Button("Show banner") {
                guard let activeScene else { return }

                let banner = LucidBannerRegistry.shared.banner(for: activeScene)

                let payload = LucidBannerPayload(
                    title: "Upload started",
                    subtitle: "Keep the app active for best performance",
                    systemImage: "arrow.up.circle.fill",
                    imageAnimation: .pulse,
                    stage: .info,
                    backgroundColor: .clear,
                    textColor: .primary,
                    imageColor: .blue,
                    presentationStyle: .automatic,
                    vPosition: .top,
                    verticalMargin: 12,
                    horizontalLayout: .stretch(margins: 16),
                    respectsSafeArea: true,
                    autoDismissAfter: 3,
                    swipeToDismiss: true
                )

                token = banner.show(payload: payload, policy: .enqueue) { state in
                    UploadBannerView(state: state)
                }
            }

            Button("Update progress") {
                guard let activeScene, let token else { return }

                let banner = LucidBannerRegistry.shared.banner(for: activeScene)
                banner.update(
                    payload: .init(
                        subtitle: "Uploading…",
                        progress: 0.66,
                        stage: .info
                    ),
                    for: token
                )
            }

            Button("Dismiss") {
                guard let activeScene else { return }
                LucidBannerRegistry.shared.banner(for: activeScene).dismiss()
            }
        }
        .padding()
    }
}
```

### A SwiftUI banner view

The content closure receives the shared `LucidBannerState`. Read `state.payload` to render the active configuration. Keep presentation and dismissal lifecycle in `LucidBanner`; content-level interactions may deliberately call an external coordinator or callback, such as `LucidBannerVariantCoordinator.handleTap(_:)`.

`LucidBannerState` also publishes `variant`, which is `.standard` or `.alternate`. The variant coordinator changes it while preserving the same state object and token.

```swift
@MainActor
struct UploadBannerView: View {
    @ObservedObject var state: LucidBannerState

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage = state.payload.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(state.payload.imageColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                if let title = state.payload.title {
                    Text(title)
                        .font(.headline)
                }

                if let subtitle = state.payload.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                }

                if let footnote = state.payload.footnote {
                    Text(footnote)
                        .font(.footnote)
                }

                if let progress = state.payload.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
            }
            .foregroundStyle(state.payload.textColor)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .fill(state.payload.backgroundColor.opacity(0.18))
        }
        .shadow(radius: 12, y: 4)
    }
}
```

## Presentation policies

Use the policy parameter of `show(payload:policy:onTap:content:)` when another banner is visible or transitioning. With no active banner, all three policies present immediately.

Presentation requires a foreground-active scene. Calling `show` for an inactive scene clears queued requests, resets the visible banner without animation, and returns a new token without presenting it.

The optional `onTap` closure passed to `show` receives the active token and the current `LucidBanner.Stage`:

```swift
let token = banner.show(payload: payload, policy: .enqueue, onTap: { token, stage in
    print("Tapped banner \(token ?? -1), stage: \(stage?.rawValue ?? "none")")
}) { state in
    UploadBannerView(state: state)
}
```

| Policy | Behavior |
| --- | --- |
| `.enqueue` | Adds the request to the scene-local FIFO queue. |
| `.replace` | Clears queued requests, dismisses the current banner, then shows the new request. |
| `.drop` | Ignores the request while a banner is active or transitioning. When an active token exists, that token is returned; otherwise the newly generated token is returned even though no banner is queued. |

## Configuring a payload

`LucidBannerPayload` is a complete snapshot. It includes:

```swift
let payload = LucidBannerPayload(
    title: "Download complete",
    subtitle: "report.pdf is available offline",
    footnote: "Tap for details",
    systemImage: "checkmark.circle.fill",
    imageAnimation: .bounce,
    progress: 1,
    stage: .success,
    backgroundColor: .clear,
    textColor: .primary,
    imageColor: .green,
    presentationStyle: .slide,
    vPosition: .bottom,
    verticalMargin: 12,
    horizontalLayout: .centered(width: 320),
    respectsSafeArea: true,
    autoDismissAfter: 4,
    swipeToDismiss: true,
    blocksTouches: false,
    draggable: false
)
```

When `blocksTouches` is `true`, LucidBanner disables both dragging and swipe-to-dismiss for that presentation, even if their payload values are `true`.

### Layout options

```swift
// Full-width, with symmetric margins.
.stretch(margins: 16)

// Floating banner with an explicit width.
.centered(width: 320)

// Fixed-width banner anchored to an edge.
.leading(width: 280, offset: 12)
.trailing(width: 280, offset: 12)
```

Vertical position is `.top`, `.center`, or `.bottom`. Presentation style is `.automatic`, `.slide`, `.scale`, or `.fade`.

### Icon animation styles

`LucidBanner.LucidBannerAnimationStyle` is interpreted by your SwiftUI content; the engine does not apply symbol effects automatically. The simple `UploadBannerView` above renders a static symbol. The available values are `.none`, `.rotate`, `.pulse`, `.pulsebyLayer`, `.drawOn`, `.breathe`, `.bounce`, `.wiggle`, `.scale`, `.scaleUpbyLayer`, and `.variableColor`.

### Semantic stages

`LucidBanner.Stage` is an optional semantic value for application-specific rendering or behavior. The built-in values are `.success`, `.error`, `.info`, `.warning`, `.button`, and `.placeholder`; use `.custom("value")` for your own stage. `rawValue` converts a stage to a string and `init(rawValue:)` restores known values case-insensitively, otherwise creating `.custom`.

## Updating an active banner

Apply a partial patch with `LucidBannerPayload.Update`. Omitted values are unchanged. Progress is clamped to the `0...1` range; pass `Double.nan` to explicitly remove it.

`nil` means “leave unchanged” in an update patch. To clear an existing title, subtitle, or footnote, pass an empty or whitespace-only string; LucidBanner normalizes it to `nil`. `progress` can be cleared with `Double.nan`. The public patch initializer has no explicit clear operation for `systemImage` or `stage`.

```swift
banner.update(
    payload: .init(
        title: "Uploading",
        progress: 0.75,
        stage: .info,
        autoDismissAfter: 0
    ),
    for: token
)

// Explicitly hide a previously displayed progress indicator.
banner.update(payload: .init(progress: .nan), for: token)
```

Updates apply only to the active banner. A token returned for a queued request is not alive until that request is presented; updates for queued or stale tokens are ignored.

Use `isAlive(_:)` before performing delayed or asynchronous updates tied to a token:

```swift
guard banner.isAlive(token) else { return }
banner.update(payload: .init(progress: 0.9), for: token)
```

`Update` can also change `imageAnimation`, colors, `draggable`, `swipeToDismiss`, `blocksTouches`, `presentationStyle`, vertical position and margin, horizontal layout, safe-area behavior, and `autoDismissAfter`. `UpdateValue` is used only for progress: `.unchanged`, `.value(Double)`, or `.clear`.

## Dismissal and queue control

```swift
banner.dismiss()
await banner.dismissAsync()

banner.dismiss(after: 2)
await banner.dismissAsync(after: 2)

// Immediately removes the visible banner and clears queued requests.
banner.dismissAll(animated: false)
```

`dismiss()` advances to the next queued request after the current banner finishes dismissing. `dismissAll(animated:)` clears queued requests, cancels pending timers, and removes the visible banner. Pending dismissal completions are resolved during cleanup.

`dismiss(after:completion:)` and auto-dismiss share one timer per banner. Scheduling a new delay replaces the previous timer. Changing `autoDismissAfter` to a different positive value starts a new delay; changing it to `0` cancels the timer. Reapplying the same value does not restart the delay.

A delayed dismissal’s completion runs after dismissal, or when its delay is cancelled or its banner is no longer active. `dismissAsync(after:)` therefore also returns when the delay is cancelled; its return alone does not guarantee that the banner was dismissed.

To discard queued requests, call `dismissAll(animated:)` or present a replacement banner with `.replace`. Do not use `LucidBannerRegistry.remove(for:)` as a queue-reset mechanism while a banner may still be visible: it only removes the registry reference and does not dismiss the existing instance.

## Scene lifecycle

When a scene disconnects, reset its banner before removing the instance from the registry. `remove(for:)` only removes the registry reference:

```swift
func sceneDidDisconnect(_ scene: UIScene) {
    guard let windowScene = scene as? UIWindowScene else { return }
    LucidBannerRegistry.shared.banner(for: windowScene).dismissAll(animated: false)
    LucidBannerRegistry.shared.remove(for: windowScene)
}
```

LucidBanner dismisses the visible banner when the application enters the background. Queued requests and pending timers are cleared as part of the reset.

## Alternate variants

`LucidBannerVariantCoordinator` manages a standard/alternate visual state for one scene-scoped banner. It does not decide the alternate layout itself: your resolver receives the current window, host view, safe-area insets, state, and token, then returns an optional target point and payload update. Returning to the standard variant reapplies the stored payload through `LucidBannerPayload.Update(from:)`. The restoration helper restores absent optional values as well as presentation style.

```swift
let coordinator = LucidBannerVariantCoordinator(banner: banner)
let token = banner.show(payload: payload) { state in
    UploadBannerView(state: state)
        .onTapGesture {
            coordinator.handleTap(state)
        }
}

coordinator.register(token: token, resolveVariant: { context in
    .init(
        targetPoint: CGPoint(
            x: context.bounds.midX,
            y: context.safeAreaInsets.top + 60
        ),
        payloadUpdate: .init(
            title: "Expanded controls",
            horizontalLayout: .centered(width: 300)
        )
    )
})
```

The content above retains the coordinator through its tap handler. Returning to the standard variant restores the captured payload, including values changed while the alternate variant was active.

The banner engine remeasures content when the window bounds or safe area change. Call `notifyLayoutChanged(animated:)` when the alternate target position also needs to be recalculated; the coordinator additionally listens for device orientation changes.

## Runtime controls and inspection

```swift
// The UIWindowScene owned by this banner instance.
let scene = banner.windowScene

// Reposition the active banner in window coordinates.
banner.move(toX: 180, y: 96, for: token, animated: true)
banner.resetPosition(for: token, animated: true)

// Inspect the active banner.
let frame = banner.currentFrameInWindow(for: token)
let hostView = banner.currentHostView(for: token)
let state = banner.currentState(for: token)

// Adjust live interaction and layout behavior.
banner.setDraggingEnabled(false, for: token)
banner.setRespectsSafeArea(true, for: token, animated: true)
banner.requestRelayout(animated: true)
```

`move(toX:y:for:animated:)`, `resetPosition(for:animated:)`, `currentFrameInWindow(for:)`, `currentHostView(for:)`, and `setDraggingEnabled(_:for:)` use the active banner when their token is omitted. `currentState(for:)` returns `nil` for a stale or non-active token.

`setDraggingEnabled(_:for:)` enables or disables the installed pan gesture, which handles both dragging and swipe-to-dismiss. It only overrides the gesture’s enabled state and does not change the payload. Configure dragging and swipe-to-dismiss through `Update`; subsequent payload updates reapply the effective gesture configuration.

`setRespectsSafeArea(_:for:animated:)` updates both the active layout and `state.payload.respectsSafeArea`.

## Utility extensions

```swift
let cleanedTitle = rawTitle.trimmedNilIfEmpty
let onlyIfNonEmpty = rawTitle.nilIfEmpty
```

`trimmedNilIfEmpty` removes leading/trailing whitespace and returns `nil` for an empty result. `nilIfEmpty` only checks direct emptiness.

## License

MIT License. See `LICENSE`.
