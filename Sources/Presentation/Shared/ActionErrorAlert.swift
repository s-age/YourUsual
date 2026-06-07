import SwiftUI

extension View {
    /// Presents a one-shot error alert bound to an optional message, clearing it on dismiss.
    func actionErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Action Failed",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }
}
