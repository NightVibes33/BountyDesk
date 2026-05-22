import SwiftUI

extension View {
    func deskPanel(cornerRadius: CGFloat = 18) -> some View {
        self
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    func deskControl() -> some View {
        self
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}
