import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AppTheme {
    static let accent = Color.green
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(KeyboardDismissOnTapModifier())
    }
}

#if canImport(UIKit)
private struct KeyboardDismissOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(KeyboardDismissTapInstaller())
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let recognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        context.coordinator.tapRecognizer = recognizer

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isUserInteractionEnabled = true
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var tapRecognizer: UITapGestureRecognizer?

        @objc
        func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            guard let window = recognizer.view?.window else { return }
            window.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard
                let firstResponder = UIApplication.shared.activeFirstResponder,
                firstResponder is UITextField || firstResponder is UITextView
            else {
                return false
            }

            guard let touchedView = touch.view else {
                return false
            }

            return !touchTargetsInteractiveView(touchedView)
        }

        private func touchTargetsInteractiveView(_ view: UIView) -> Bool {
            var current: UIView? = view
            while let target = current {
                if target is UIControl || target is UITextField || target is UITextView {
                    return true
                }
                if target is UINavigationBar || target is UITabBar || target is UIToolbar {
                    return true
                }
                current = target.superview
            }
            return false
        }
    }
}

private enum FirstResponderLocator {
    static var current: UIResponder?
}

private extension UIApplication {
    var activeFirstResponder: UIResponder? {
        FirstResponderLocator.current = nil
        sendAction(#selector(UIResponder.captureFirstResponder), to: nil, from: nil, for: nil)
        return FirstResponderLocator.current
    }
}

private extension UIResponder {
    @objc
    func captureFirstResponder() {
        FirstResponderLocator.current = self
    }
}
#else
private struct KeyboardDismissOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
#endif
