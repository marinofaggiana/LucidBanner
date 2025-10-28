# LucidBanner

SwiftUI-based transient banners rendered in their own window above the status bar.
Designed and used in the **Nextcloud iOS** app. Author: **Marino Faggiana**.  
License: **GPL-3.0-or-later**. Version: **0.0.1**

## Features
- One-at-a-time display with queueing (`.enqueue`), replacement (`.replace`) or dropping (`.drop`)
- Top / Center / Bottom placement, left / center / right alignment, safe-area aware margins
- Swipe-to-dismiss (direction-aware), optional scrim that blocks touches
- Tap callback with `(token, revision, stage)` context
- Live `update(...)` for title/subtitle/footnote/icon/progress/colors
- Auto-dismiss timer
- Works with multi‑window scenes on iPad/iPhone (iOS 17+)

## Installation (Swift Package Manager)
- In Xcode, **File → Add Packages…**
- Enter the repo URL (your Git host) and choose the tag **0.0.1**
- Add the product **LucidBanner** to your target

Or in `Package.swift` of your app:

```swift
dependencies: [
    .package(url: "https://example.com/your-org/LucidBanner.git", from: "0.0.1")
]
```

## Quick Start

```swift
import LucidBanner
import SwiftUI

struct ContentView: View {
    @State private var token: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            Button("Show Top Banner") {
                token = LucidBanner.shared.show(
                    title: "Upload started",
                    systemImage: "arrow.up.circle",
                    imageAnimation: .rotate,
                    vPosition: .top,
                    autoDismissAfter: 2.5
                ) { state in
                    ToastBannerView(state: state)
                }
            }

            Button("Update Progress") {
                LucidBanner.shared.update(progress: 0.66, for: token)
            }

            Button("Dismiss") {
                LucidBanner.shared.dismiss(for: token)
            }
        }
        .padding()
    }
}
```

`ToastBannerView` is a lightweight SwiftUI view included in the package for testing.

## API Highlights

```swift
@discardableResult
public func show<Content: View>(
    scene: UIScene? = nil,
    title: String,
    subtitle: String? = nil,
    footnote: String? = nil,
    textColor: UIColor = .label,
    systemImage: String? = nil,
    imageColor: UIColor = .label,
    imageAnimation: LucidBanner.LucidBannerAnimationStyle = .none,
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
    @ViewBuilder content: @escaping (LucidBannerState) -> Content
) -> Int
```

- Returns the token of the **new** banner if shown immediately or replacing.
- Returns the **current active** token if enqueued.
- Returns the **current active** token if dropped.

## Credits

- Author: **Marino Faggiana**
- Built for: **Nextcloud iOS**

## License
GPL-3.0-or-later (see `LICENSE`).
