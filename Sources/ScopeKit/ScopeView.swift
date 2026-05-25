import SwiftUI
import Observation

// MARK: - @Observable (iOS 17+)

/// Creates an isolated re-render scope for an `@Observable` type from the environment.
/// Only this view re-renders when accessed properties change — the parent and siblings
/// are unaffected.
///
/// - Important: The type must be injected into the environment with `.environment(_:)`
///   on an ancestor view before use.
///
/// ```swift
/// ScopeView(ViewModel.self) { viewModel, projected in
///     TextField("Text", text: projected.text)
/// }
/// ```
@available(iOS 17, macOS 14, watchOS 10, tvOS 17, *)
@MainActor @ViewBuilder
public func ScopeView<Root: AnyObject & Observable, Content: View>(
    _ type: Root.Type,
    @ViewBuilder content: @escaping @MainActor (Root, Bindable<Root>) -> Content
) -> some View {
    ObservableScope(type, content: content)
}

// MARK: - ObservableObject (iOS 14+)

/// Creates an isolated re-render scope for an `ObservableObject` type from the environment.
/// Only this view re-renders when `objectWillChange` fires — the parent and siblings
/// are unaffected.
///
/// - Important: The type must be injected into the environment with `.environmentObject(_:)`
///   on an ancestor view before use.
/// - Note: On iOS 17+ prefer the `@Observable` overload. If a type satisfies both
///   `ObservableObject` and `Observable`, the compiler may report an ambiguous call;
///   resolve it by casting the type to the desired protocol or calling the `@Observable`
///   overload directly.
///
/// ```swift
/// ScopeView(LegacyViewModel.self) { viewModel, projected in
///     TextField("Text", text: projected.text)
/// }
/// ```
@MainActor @ViewBuilder
public func ScopeView<Root: ObservableObject, Content: View>(
    _ type: Root.Type,
    @ViewBuilder content: @escaping @MainActor (Root, EnvironmentObject<Root>.Wrapper) -> Content
) -> some View {
    ObservableObjectScope(type, content: content)
}

// MARK: - Private implementations

@available(iOS 17, macOS 14, watchOS 10, tvOS 17, *)
private struct ObservableScope<Root: AnyObject & Observable, Content: View>: View {
    @Environment(Root.self) private var root
    let content: @MainActor (Root, Bindable<Root>) -> Content

    init(_ type: Root.Type, @ViewBuilder content: @escaping @MainActor (Root, Bindable<Root>) -> Content) {
        self.content = content
    }

    var body: some View {
        content(root, Bindable(root))
    }
}

private struct ObservableObjectScope<Root: ObservableObject, Content: View>: View {
    @EnvironmentObject private var root: Root
    let content: @MainActor (Root, EnvironmentObject<Root>.Wrapper) -> Content

    init(_ type: Root.Type, @ViewBuilder content: @escaping @MainActor (Root, EnvironmentObject<Root>.Wrapper) -> Content) {
        self.content = content
    }

    var body: some View {
        content(root, $root)
    }
}

