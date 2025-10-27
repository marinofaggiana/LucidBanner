# LucidBanner

Elegant, fully async SwiftUI banner system for iOS — lightweight, customizable, and concurrency-safe.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platform](https://img.shields.io/badge/platform-iOS_14+-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

---

## 🧭 Overview

LucidBanner provides smooth, customizable in-app banners for iOS, combining the flexibility of **SwiftUI** with **UIKit** precision.  
It renders each banner in its own transparent `UIWindow` above the status bar — independent from your main view hierarchy.

---

## ✨ Features

- Top / Center / Bottom positioning
- Left / Center / Right alignment
- Built-in animations (`rotate`, `pulse`, `breathe`, `bounce`, …)
- Live-updating progress bar
- Fully `@MainActor` and async-safe
- Tap, swipe, and automatic dismiss support

---

## 🚀 Example

```swift
import LucidBanner

let token = LucidBanner.shared.show(
    title: "Preparing upload",
    subtitle: "Large files require the app to stay open",
    systemImage: "gearshape.arrow.triangle.2.circlepath",
    imageColor: .systemBlue,
    imageAnimation: .rotate,
    vPosition: .bottom
) { state in
    ToastBannerView(state: state)
}

LucidBanner.shared.update(progress: 0.5, stage: "uploading", for: token)
LucidBanner.shared.dismiss(for: token)
```

---

© 2025 Marino Faggiana — Licensed under GPL-3.0-or-later
