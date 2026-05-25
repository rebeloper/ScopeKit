import SwiftUI

extension View {
    /// Performs `action` only the first time this view appears.
    /// Unlike `onAppear`, subsequent appearances after a disappear/reappear
    /// cycle do not re-trigger the action, as long as the view's structural
    /// identity is stable. Assigning a new `id()` or list cell recycling will
    /// reset the guard and allow the action to fire again.
    public func onFirstAppear(perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(FirstAppearModifier(action: action))
    }
}

private struct FirstAppearModifier: ViewModifier {
    let action: @MainActor () -> Void
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            action()
        }
    }
}


