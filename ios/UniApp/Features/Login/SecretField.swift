import SwiftUI
import UIKit

struct SecretField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool
    @Binding var isFocused: Bool
    var keyboardType: UIKeyboardType = .default
    var contentType: UITextContentType = .password
    var onSubmit: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .medium))
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .white
        field.tintColor = UIColor(Theme.accentBright)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .go
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.text = text
        field.isSecureTextEntry = isSecure
        field.keyboardType = keyboardType
        field.textContentType = contentType
        field.accessibilityIdentifier = "login.secret"
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor.placeholderText])
        if field.text != text {
            field.text = text
        }
        if field.isSecureTextEntry != isSecure {
            let caret = field.selectedTextRange
            field.isSecureTextEntry = isSecure
            let current = field.text
            field.text = nil
            field.text = current
            field.selectedTextRange = caret ?? field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        }
        var needsReload = false
        if field.keyboardType != keyboardType {
            field.keyboardType = keyboardType
            needsReload = true
        }
        if field.textContentType != contentType {
            field.textContentType = contentType
            needsReload = true
        }
        if needsReload && field.isFirstResponder {
            field.reloadInputViews()
        }
        guard context.coordinator.focusState != isFocused else { return }
        context.coordinator.focusState = isFocused
        if isFocused && !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isFocused && field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SecretField
        var focusState: Bool

        init(parent: SecretField) {
            self.parent = parent
            self.focusState = parent.isFocused
        }

        @objc func editingChanged(_ field: UITextField) {
            sync(field)
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = (field.text ?? "") as NSString
            let updated = current.replacingCharacters(in: range, with: string)
            field.text = updated
            let offset = range.location + (string as NSString).length
            if let position = field.position(from: field.beginningOfDocument, offset: offset) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
            sync(field)
            return false
        }

        func textFieldDidChangeSelection(_ field: UITextField) {
            sync(field)
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            setFocused(true)
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            setFocused(false)
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        private func sync(_ field: UITextField) {
            let value = field.text ?? ""
            if parent.text != value {
                parent.text = value
            }
        }

        private func setFocused(_ value: Bool) {
            focusState = value
            guard parent.isFocused != value else { return }
            DispatchQueue.main.async { self.parent.isFocused = value }
        }
    }
}
