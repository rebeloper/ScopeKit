# ScopeKit

A SwiftUI utility library for isolating re-render scopes and observing state changes without introducing unwanted view updates.

---

## The Problem

### `ObservableObject` — coarse-grained re-renders

`ObservableObject` fires `objectWillChange` before any `@Published` property changes. Every view holding `@StateObject` or `@EnvironmentObject` re-renders in full — regardless of which property changed or whether the view even uses it.

```swift
class ViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var count: Int = 0
}

struct MyView: View {
    @EnvironmentObject var viewModel: ViewModel

    var body: some View {
        // Re-renders when count changes, even though this view only shows text.
        Text(viewModel.text)
    }
}
```

---

### `@Observable` — fine-grained but still coupled at the view level

`@Observable` (iOS 17+) tracks which properties are actually read during `body` evaluation and only re-renders when those specific properties change. Unread properties never cause re-renders.

However, if a view reads multiple properties in its `body`, it becomes a dependency of all of them.

```swift
@Observable
class ViewModel {
    var text: String = ""
    var count: Int = 0
}

struct MyView: View {
    @Environment(ViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack {
            // Reads viewModel.text → dependency registered.
            // Reads viewModel.count → also a dependency.
            // Typing in the TextField re-renders the whole view.
            // Tapping the button re-renders the whole view.
            Button { viewModel.count += 1 } label: {
                Text(viewModel.text)
            }
            TextField("Text", text: $viewModel.text)
        }
        .background { Color.random() } // flashes on every re-render
    }
}
```

The SwiftUI team's intended fix is view decomposition: break each element into its own named subview. That works, but it is verbose for simple cases.

---

## The Solution

ScopeKit provides four tools:

1. **`ScopeView`** — an inline isolated re-render scope. Only the scope re-renders when its accessed properties change. The parent and siblings are unaffected.
2. **`onChange(of:in:)`** — reacts to specific property value changes without registering a re-render dependency on the view it is attached to.
3. **`onReceive(of:in:)`** — fires on every `@Published` mutation, including same-value sets. `ObservableObject` only.
4. **`onFirstAppear(perform:)`** — a drop-in replacement for `onAppear` that fires only on the first appearance, ignoring subsequent disappear/reappear cycles.

`ScopeView`, `onChange`, and `onFirstAppear` work with both `@Observable` (iOS 17+) and `ObservableObject` (iOS 14+). All require the model to be injected via `.environment()` or `.environmentObject()` on an ancestor view.

All `action` and `content` closures are `@MainActor`. Callers using Swift 6 strict concurrency can safely capture `@MainActor`-isolated state in them without additional annotations.

---

## Usage

### Setup

Inject your model at a common ancestor:

```swift
struct ContentView: View {
    @State private var viewModel = ViewModel()             // @Observable, iOS 17+
    @StateObject private var legacyViewModel = LegacyViewModel() // ObservableObject, iOS 14+

    var body: some View {
        VStack { ... }
            .environment(viewModel)
            .environmentObject(legacyViewModel)
    }
}
```

---

### `ScopeView` — isolated rendering

Each `ScopeView` creates its own observation scope. It re-renders only when the properties it reads change. The parent view is never re-rendered due to model changes.

**With `@Observable` (iOS 17+):**

```swift
// Re-renders only when viewModel.text changes.
ScopeView(ViewModel.self) { _, projected in
    TextField("Text", text: projected.text)
        .textFieldStyle(.roundedBorder)
}

// Re-renders only when viewModel.count changes.
ScopeView(ViewModel.self) { viewModel, _ in
    Button { viewModel.count += 1 } label: {
        Text("\(viewModel.count)")
    }
}
```

The second closure parameter is `Bindable<Root>`, giving direct access to bindings via `projected.propertyName`.

**With `ObservableObject` (iOS 14+):**

```swift
ScopeView(LegacyViewModel.self) { _, projected in
    TextField("Text", text: projected.text)
        .textFieldStyle(.roundedBorder)
}
```

The second closure parameter is `EnvironmentObject<Root>.Wrapper`, used identically at the call site.

---

### `onChange(of:in:)` — react to value changes without re-rendering

Observes a specific property and calls `action` when its value changes. Same-value sets are ignored. The view this modifier is attached to is never re-rendered as a result.

**With `@Observable` (iOS 17+):**

```swift
.onChange(of: \.count, in: ViewModel.self) { oldValue, newValue in
    print("Count changed from \(oldValue) to \(newValue)")
}
```

**With `ObservableObject` (iOS 14+):**

```swift
.onChange(of: \.count, in: LegacyViewModel.self) { oldValue, newValue in
    print("Count changed from \(oldValue) to \(newValue)")
}
```

> **Note:** For `ObservableObject`, the internal observer re-renders on every `objectWillChange` emission. `action` is still only called when the specific property value changes.

---

### `onReceive(of:in:)` — react to every mutation (`ObservableObject` only, iOS 14+)

Calls `action` on every `@Published` mutation, including same-value sets. Uses the `$`-prefixed keypath syntax from `@Published`. Does not fire on first appear.

```swift
.onReceive(of: \.$count, in: LegacyViewModel.self) { newValue in
    print("Received count: \(newValue)")
}
```

This is not available for `@Observable`. The Observation framework is change-detection-based: `withObservationTracking` does not fire when the same value is set twice, by design.

---

### `onFirstAppear(perform:)` — run once on first appearance (iOS 14+)

Fires `action` only the first time the view appears. Unlike `onAppear`, subsequent appearances after a disappear/reappear cycle do not re-trigger it.

```swift
.onFirstAppear {
    viewModel.loadData()
}
```

> **Note:** The one-shot guarantee holds as long as the view's structural identity is stable. Assigning a new `id()` or list cell recycling will reset the guard and allow the action to fire again.

---

### Full example

```swift
// @Observable (iOS 17+)
struct ObservableFeatureView: View {
    var body: some View {
        VStack {
            ScopeView(ViewModel.self) { viewModel, _ in
                Button { viewModel.count += 1 } label: {
                    Text("Tap me").foregroundStyle(.white).bold()
                }
            }
            ScopeView(ViewModel.self) { _, projected in
                TextField("Name", text: projected.text)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .background { Color.blue.opacity(0.8) } // never re-renders
        .onChange(of: \.count, in: ViewModel.self) { old, new in
            print("Count changed: \(old) → \(new)")
        }
    }
}

// ObservableObject (iOS 14+)
struct LegacyFeatureView: View {
    var body: some View {
        VStack {
            ScopeView(LegacyViewModel.self) { viewModel, _ in
                Button { viewModel.count = 1 } label: {
                    Text("Tap me").foregroundStyle(.white).bold()
                }
            }
            ScopeView(LegacyViewModel.self) { _, projected in
                TextField("Name", text: projected.text)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .background { Color.blue.opacity(0.8) } // never re-renders
        .onChange(of: \.count, in: LegacyViewModel.self) { old, new in
            print("Count changed: \(old) → \(new)")
        }
        .onReceive(of: \.$count, in: LegacyViewModel.self) { newValue in
            print("Received: \(newValue)")
        }
    }
}
```

---

## Re-render behavior summary

| Pattern | Parent re-renders? | Scope re-renders? |
|---|---|---|
| `@Observable` + `ScopeView` | Never | Only when read properties change |
| `@Observable` + direct `@Environment` | On every read property change | — |
| `ObservableObject` + `ScopeView` | Never | On every `objectWillChange` |
| `ObservableObject` + direct `@EnvironmentObject` | On every `objectWillChange` | — |

---

## API summary

| API | System | Minimum OS | Notes |
|---|---|---|---|
| `ScopeView` | `@Observable` | iOS 17 | Second param is `Bindable<Root>` |
| `ScopeView` | `ObservableObject` | iOS 14 | Second param is `EnvironmentObject<Root>.Wrapper` |
| `onChange(of:in:)` | `@Observable` | iOS 17 | Fires on value changes only |
| `onChange(of:in:)` | `ObservableObject` | iOS 14 | Fires on value changes only |
| `onReceive(of:in:)` | `ObservableObject` only | iOS 14 | Fires on every mutation incl. same-value |
| `onFirstAppear(perform:)` | Any | iOS 14 | Fires once per structural identity lifetime |

---

## Performance notes

- Each `ScopeView`, `onChange(of:in:)`, and `onReceive(of:in:)` adds one hidden view node to the background layer. This is negligible for typical use.
- For `ObservableObject`, the internal `onChange` and `onReceive` observers re-render on every `objectWillChange` emission. `action` is guarded by value equality, but the re-render cost scales with the total number of `@Published` changes in the model.

---

## Requirements

- iOS 14+ / macOS 11+
- Swift 6.0+ (Xcode 16+)
- `@Observable` APIs require iOS 17+ / macOS 14+
- Compiled with Swift 6 strict concurrency (`swiftLanguageMode(.v6)`)
