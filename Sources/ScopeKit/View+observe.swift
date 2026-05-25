import Combine
import Observation
import SwiftUI

extension View {

    // MARK: - @Observable (iOS 17+)

    /// Observes a property on an `@Observable` type from the environment without
    /// registering that property as a re-render dependency of the view this modifier
    /// is attached to.
    ///
    /// - Important: The type must be injected into the environment with `.environment(_:)`
    ///   on an ancestor view before use.
    ///
    /// ```swift
    /// .onChange(of: \.count, in: ViewModel.self) { old, new in ... }
    /// ```
    @available(iOS 17, macOS 14, watchOS 10, tvOS 17, *)
    public func onChange<Root: AnyObject & Observable, Value: Equatable>(
        of keyPath: KeyPath<Root, Value>,
        in type: Root.Type,
        perform action: @escaping @MainActor (_ oldValue: Value, _ newValue: Value) -> Void
    ) -> some View {
        background(ObservableOnChangeObserver<Root, Value>(keyPath: keyPath, action: action))
    }

    // MARK: - ObservableObject (iOS 14+)

    /// Observes a property on an `ObservableObject` type from the environment without
    /// registering a re-render dependency on the view this modifier is attached to.
    ///
    /// - Important: The type must be injected into the environment with `.environmentObject(_:)`
    ///   on an ancestor view before use.
    /// - Note: The internal observer re-renders on every `objectWillChange` emission.
    ///   `action` is still only called when the specific property value changes.
    ///
    /// ```swift
    /// .onChange(of: \.count, in: LegacyViewModel.self) { old, new in ... }
    /// ```
    public func onChange<Root: ObservableObject, Value: Equatable>(
        of keyPath: KeyPath<Root, Value>,
        in type: Root.Type,
        perform action: @escaping @MainActor (_ oldValue: Value, _ newValue: Value) -> Void
    ) -> some View {
        background(ObservableObjectOnChangeObserver<Root, Value>(keyPath: keyPath, action: action))
    }

    /// Observes a `@Published` property on an `ObservableObject` type from the environment,
    /// calling `action` on every mutation — including same-value sets — without registering
    /// a re-render dependency on the view this modifier is attached to.
    ///
    /// Does not fire on first appear.
    ///
    /// - Important: The type must be injected into the environment with `.environmentObject(_:)`
    ///   on an ancestor view before use.
    ///
    /// ```swift
    /// .onReceive(of: \.$count, in: LegacyViewModel.self) { new in ... }
    /// ```
    public func onReceive<Root: ObservableObject, Value>(
        of keyPath: KeyPath<Root, Published<Value>.Publisher>,
        in type: Root.Type,
        perform action: @escaping @MainActor (Value) -> Void
    ) -> some View {
        background(ObservableObjectOnReceiveObserver<Root, Value>(keyPath: keyPath, action: action))
    }

}

// MARK: - Private observer views

@available(iOS 17, macOS 14, watchOS 10, tvOS 17, *)
private struct ObservableOnChangeObserver<Root: AnyObject & Observable, Value: Equatable>: View {
    @Environment(Root.self) private var root
    let keyPath: KeyPath<Root, Value>
    let action: @MainActor (Value, Value) -> Void

    var body: some View {
        Color.clear
            .onChange(of: root[keyPath: keyPath]) { action($0, $1) }
    }
}

// Delegates to the iOS 17 two-parameter onChange when available; falls back to
// a @State-tracked implementation on iOS 14–16 where only the new value is provided.
private struct ObservableObjectOnChangeObserver<Root: ObservableObject, Value: Equatable>: View {
    @EnvironmentObject private var root: Root
    let keyPath: KeyPath<Root, Value>
    let action: @MainActor (Value, Value) -> Void

    var body: some View {
        if #available(iOS 17, macOS 14, watchOS 10, tvOS 17, *) {
            Color.clear
                .onChange(of: root[keyPath: keyPath]) { action($0, $1) }
        } else {
            LegacyOnChangeObserver(keyPath: keyPath, action: action)
        }
    }
}

// @MainActor ensures Sendable conformance via actor isolation, satisfying @State's
// Sendable requirement under strict concurrency without an @unchecked annotation.
@MainActor
private final class ValueRef<T> {
    var value: T?
}

private struct LegacyOnChangeObserver<Root: ObservableObject, Value: Equatable>: View {
    @EnvironmentObject private var root: Root
    let keyPath: KeyPath<Root, Value>
    let action: @MainActor (Value, Value) -> Void
    @State private var store = ValueRef<Value>()

    var body: some View {
        Color.clear
            .onChange(of: root[keyPath: keyPath]) { newValue in
                guard let old = store.value else {
                    store.value = newValue
                    return
                }
                action(old, newValue)
                store.value = newValue
            }
            .onFirstAppear {
                store.value = root[keyPath: keyPath]
            }
    }
}

// Avoids dropFirst() on the publisher because Published<Value>.Publisher is a value
// type — dropFirst() returns a new publisher instance on every body evaluation,
// causing the subscription to reset and the skip counter to reset with it. A @State
// flag is used instead to skip the initial subscription emission, keeping the
// subscription stable across re-renders.
private struct ObservableObjectOnReceiveObserver<Root: ObservableObject, Value>: View {
    @EnvironmentObject private var root: Root
    let keyPath: KeyPath<Root, Published<Value>.Publisher>
    let action: @MainActor (Value) -> Void
    @State private var isFirstReceive = true

    var body: some View {
        Color.clear
            .onReceive(root[keyPath: keyPath]) { value in
                if isFirstReceive { isFirstReceive = false; return }
                action(value)
            }
    }
}


