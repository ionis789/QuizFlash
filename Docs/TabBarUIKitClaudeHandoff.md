#
# QuizFlash Tab Bar UIKit Handoff
#

## Goal

Replace the current SwiftUI-driven custom tab bar motion with a more advanced UIKit-backed implementation whose animated capsule remains perceptually smooth even when the destination tab triggers heavy SwiftUI rendering.

The desired end state is:

- the bottom tab bar keeps the current QuizFlash glass / bottom chrome look
- the capsule slide and tap feedback feel premium and zero-lag
- the capsule animation is visually decoupled from `TabView` screen switching
- heavy screens such as `DeckView` must not drag down the first frames of the tab-bar motion
- the implementation should be robust, scalable, and production-grade

## Current Problem

The current custom tab bar is a SwiftUI overlay above a `TabView`. When the selected tab changes, the destination screen starts expensive SwiftUI work on the main thread. On light demo screens the tab bar animation looks fine, but in the real app the capsule animation becomes visibly less smooth.

Observed facts:

- with a simple standalone tab bar, there is effectively no lag
- with real QuizFlash screens, especially complex screens like `DeckView`, the animation loses smoothness
- the issue is not only the spring tuning; it is architectural coupling between visual motion and screen switching cost

## What I Need You To Build

Act as a very strong UIKit / Core Animation architect.

I want a UIKit-backed tab bar motion system that isolates the animated capsule from SwiftUI view recomposition caused by `TabView` selection changes.

A good direction would likely involve one of these:

- a `UIViewRepresentable` or `UIViewControllerRepresentable` that hosts the interactive capsule and tab-hit layer in UIKit
- a `CALayer` / `CAShapeLayer` driven capsule animation, updated independently from SwiftUI view layout churn
- a split between visual selection state and committed SwiftUI tab selection
- possibly a short orchestrated commit delay so the visual motion starts before the heavy screen switch is committed
- preserving current app routing semantics, tab visibility behavior, and native hidden-tab-bar handling

Do not propose a superficial SwiftUI-only spring tweak unless it is part of a deeper isolation architecture.

If you think the correct solution is to move the tab bar chrome almost entirely to UIKit while still exposing a SwiftUI API surface, say that clearly and implement it.

## Important Constraints

- Keep the current QuizFlash design language.
- Do not introduce search-bar behavior from the external reference file.
- Preserve current tab semantics:
  - tapping the current tab pops to root
  - child views can hide the custom tab bar through the existing visibility preference mechanism
  - the hidden native `UITabBar` must stay non-interactive
- Keep the build valid.
- Prefer a solution that is technically correct over one that is superficially smaller.

## Current Architecture Summary

### Root navigation

- `MainAppView` owns a `TabView(selection:)`
- each app tab has its own `NavigationStack` and `NavigationPath`
- the custom tab bar is rendered as a floating overlay above the `TabView`

### Current custom tab bar

- `CustomTabBar.swift` is pure SwiftUI
- the capsule itself animates with SwiftUI state (`dragOffset`, gesture state, etc.)
- the same interaction ultimately commits directly into the `TabView` binding

### Native UITabBar suppression

- the system `UITabBar` is visually hidden
- `NativeTabBarConfigurator` directly mutates the live UIKit tab bar to keep it hidden / non-interactive and to avoid phantom safe-area / tap issues

### Heavy screen that amplifies the issue

- `DeckView` is not lightweight
- its main shell uses `ScrollView` + `VStack`
- its card content subview uses `LazyVStack` and `LazyVGrid`
- tab switching into this screen still triggers meaningful work and layout pressure

## Files To Read First

These are the minimum important files:

- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/MainAppView.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/NavigationManager.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/TabBar/CustomTabBar.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/TabBar/AppTabBar.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/TabBar/NativeTabBarConfigurator.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/DesignSystem/Modifiers/View+Styles.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/DesignSystem/Theme/UIConstants.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Features/DeckDetails/Views/DeckView.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Features/DeckDetails/Views/DeckCardGridView.swift`

## Design-System / Shared-Component Context

Useful supporting files if you need exact bottom chrome styling or visibility behavior:

- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/DesignSystem/Components/BottomChromeContainer.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/DesignSystem/Components/EdgeShadowOverlay.swift`

## Skill / Repo Guidance

These repository-specific instruction files are worth reading before patching:

- `/Users/ionsocol/Documents/SWIFT/QuizFlash/.codex/skills/quizflash-ios-engineer/SKILL.md`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/.codex/skills/quizflash-ios-engineer/references/architecture.md`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/.codex/skills/quizflash-ios-engineer/references/project-map.md`

## External Motion Reference

This is the visual motion reference for the tab bar feel:

- `/Users/ionsocol/Downloads/TabBariOS26/TabBariOS26/View/CustomTabBar.swift`

Important:

- use only the simple tab-bar motion ideas from that file
- ignore search bar / keyboard / expandable search behavior completely

## Deliverable I Expect

Please return:

1. An architecture decision for how to isolate the capsule animation from heavy SwiftUI tab switches.
2. A concrete patch against the QuizFlash files above.
3. Exact explanation of why the new approach should outperform the current pure SwiftUI one.
4. Any tradeoffs or limitations.
5. Build / verification steps.

## Direct Prompt For Claude

You are a senior UIKit and Core Animation architect working inside a real iOS app with heavy SwiftUI screens.

I need you to redesign my QuizFlash custom tab bar so the animated capsule feels effectively zero-lag even when switching into complex screens. The current pure SwiftUI implementation animates fine in isolation, but it loses smoothness in the real app because the destination screen render competes with the tab-bar motion.

Do not give me a cosmetic spring tweak. I want a technically correct architecture that decouples the visual tab-bar animation from the cost of `TabView` screen switching.

You should prefer an advanced UIKit-backed approach if that is the right answer:

- `UIViewRepresentable` / `UIViewControllerRepresentable`
- dedicated UIKit interaction layer
- `CALayer` / `CAShapeLayer` or similar for the animated capsule
- separate visual state vs committed tab switch state
- careful orchestration of hit-testing and commit timing

Constraints:

- preserve QuizFlash's current glass / bottom chrome style
- preserve current routing semantics and per-tab navigation stacks
- preserve current custom tab bar visibility behavior
- keep native `UITabBar` hidden and non-interactive
- use the external reference only for the simple tab-bar motion feel, not the search bar

Read these files first:

- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/MainAppView.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/NavigationManager.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/TabBar/CustomTabBar.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/TabBar/AppTabBar.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/TabBar/NativeTabBarConfigurator.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/DesignSystem/Modifiers/View+Styles.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/DesignSystem/Theme/UIConstants.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Features/DeckDetails/Views/DeckView.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Features/DeckDetails/Views/DeckCardGridView.swift`
- `/Users/ionsocol/Downloads/TabBariOS26/TabBariOS26/View/CustomTabBar.swift`

I want a patch, not just theory. If the correct solution is to move the animated chrome to UIKit while keeping a SwiftUI wrapper API, do that.
