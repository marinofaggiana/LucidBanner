# LucidBanner

> Elegant, fully async SwiftUI banner system for iOS — lightweight, customizable, and concurrency-safe.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platform](https://img.shields.io/badge/platform-iOS_14+-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

---

## 🧭 Overview

**LucidBanner** is a Swift package that provides smooth, customizable in-app banners for iOS.  
It combines the flexibility of **SwiftUI** with the precision of **UIKit**, rendering each banner in its own transparent `UIWindow` — above the status bar, independent from your app hierarchy.

LucidBanner is fully **async/await safe** and runs entirely on the **main actor**, ensuring UI consistency even under concurrency.  
It supports queued banners, top/bottom/center placement, swipe gestures, progress bars, touch blocking, and tap callbacks with contextual information.

---

## ✨ Features

- 🪶 Pure **SwiftUI + UIKit** integration
- 🧭 **Top**, **Center**, or **Bottom** vertical positioning
- ↔️ **Left**, **Center**, or **Right** horizontal alignment
- 🎞️ Built-in icon animations (`rotate`, `pulse`, `breathe`, `bounce`, …)
- ⏳ Progress bar with live updates
- 🧩 Custom SwiftUI views with dynamic resizing
- 🧠 Fully `@MainActor` and concurrency-safe
- 🪟 Renders inside its own UIWindow (independent from your app UI)
- 🧍 Accessibility and Dynamic Type compliant

---

## 🚀 Installation

### Swift Package Manager (Xcode)
1. Open **File → Add Packages…**
2. Enter the URL:
   ```
   https://github.com/marinofaggiana/LucidBanner.git
   ```
3. Choose your target and click **Add Package**

---

## 💡 Quick Start

```swift
import LucidBanner

// 1. Show a banner
let token = LucidBanner.shared.show(
    title: "Preparing file upload",
    subtitle: "Large files require the app to remain open",
    systemImage: "gearshape.arrow.triangle.2.circlepath",
    imageColor: .systemBlue,
    imageAnimation: .rotate,
    progressColor: .systemBlue,
    vPosition: .bottom,
    hAlignment: .center
) { state in
    ToastBannerView(state: state)
}

// 2. Update its progress
LucidBanner.shared.update(
    progress: 0.65,
    stage: "uploading",
    for: token
)

// 3. Dismiss when done
LucidBanner.shared.dismiss(for: token)
```

---

## ⚙️ License

This project is licensed under the **MIT License**.  
See the [LICENSE](LICENSE) file for details.

© 2025 **Marino Faggiana**

---
