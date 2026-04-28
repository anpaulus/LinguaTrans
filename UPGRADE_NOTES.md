# LinguaBridge — Tahoe 26.2 Upgrade Notes
## From first response → Xcode 26.2 · Swift 6.2 · iOS 17+

---

## Files you REPLACE (2 files)

| File | Why |
|---|---|
| `ContentView.swift` | Swift 6.2 concurrency + iOS 26 onChange + `@MainActor` |
| `TranslationManager.swift` | **New file** — session management extracted here |

## Files you KEEP UNCHANGED (4 files)

| File | Status |
|---|---|
| `LinguaBridgeApp.swift` | ✅ No changes needed |
| `MultipeerManager.swift` | ✅ No changes needed |
| `SpeechManager.swift` | ✅ No changes needed |
| `TTSManager.swift` | ✅ No changes needed |
| `Info.plist` | ✅ No changes needed |

---

## The 4 changes explained

### 1. `@MainActor` on ContentView
Swift 6.2 strict concurrency makes data-race checks mandatory.
`TranslationSession` is `@MainActor`-isolated, so any function that calls
`session.translate()` must also be on the main actor. Marking the whole
`ContentView` struct `@MainActor` satisfies the compiler cleanly.

### 2. TranslationManager replaces inline session handling
The first response stored `activeSession: TranslationSession?` as a plain
`@State` variable in ContentView and updated it from the `.translationTask`
closure. Xcode 26 warns: *"Sending 'session' risks causing data races"*
because the Task{} that calls translate() could hop actors.
Solution: move all session storage into `@MainActor final class TranslationManager`.
Since the class is @MainActor and TranslationSession is @MainActor, no crossing.

### 3. Two `.translationTask` modifiers instead of one
The first response used one session and one Configuration, and swapped it
when the role changed — causing a "session not ready" race on first use.
Two persistent sessions (id→zh and zh→id) are primed at launch, removing
the race and eliminating any latency from reconfiguration mid-conversation.

### 4. `onChange(of:)` two-parameter closure
```swift
// OLD (deprecated in iOS 17, warning in Xcode 26):
.onChange(of: messages.count) { _ in ... }

// NEW (iOS 17+, Xcode 26 clean):
.onChange(of: messages.count) { _, _ in ... }
```

---

## Xcode project: one setting to change

**Target → General → Deployment Info → iOS: change from 15.0 → 17.0**

The Translation framework requires iOS 17 minimum. With Xcode 26.2 this
compiles cleanly for iPhone XR (which runs up to iOS 16 physically —
but you can still build and test on device via debug mode with iOS 17
by updating the device to iOS 17 first, iPhone XR supports iOS 17).

iPhone XR maximum iOS: **iOS 17** (Apple stopped updates after 17.x).
So iOS 17.0 as your deployment target matches the device perfectly.

---

## What you no longer need

- ❌ `TranslationService.swift` (MyMemory REST API) — delete it
- ❌ `Podfile` and CocoaPods — ML Kit is gone
- ❌ `GoogleMLKit/Translate` pod — completely removed

Apple's Translation framework is now the one and only translation engine:
free, offline, on-device, and fully integrated with iOS.
