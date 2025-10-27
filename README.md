# LucidBanner

> Elegant, fully async SwiftUI banner system for iOS — lightweight, customizable, and concurrency-safe.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platform](https://img.shields.io/badge/platform-iOS_14+-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

---

## Overview

**LucidBanner** is a lightweight Swift package that provides beautiful, animated banners for iOS apps.  
It uses SwiftUI for rendering and UIKit for window management — giving you pixel-perfect banners that live *above* the status bar, automatically resize with content, and adapt to multitasking and orientation changes.

The system supports multiple policies (`enqueue`, `replace`, `drop`), touch blocking, swipe-to-dismiss gestures, and contextual updates with async operations.

---

## Features

- 🪶 **Pure SwiftUI + UIKit integration**
- 🧭 **Top, center, or bottom positioning**
- ↔️ **Left / Center / Right horizontal alignment**
- 🎞️ **Animated icons (`rotate`, `pulse`, `breathe`, …)**
- ⏳ **Built-in progress bar**
- 🧩 **Custom SwiftUI content**
- 🧠 **Concurrency-safe (`@MainActor`)**
- 🪟 **Independent UIWindow per banner**
- 🧍‍♂️ **Accessibility & Dynamic Type ready**

---

## Installation

Add **LucidBanner** via **Swift Package Manager**:
