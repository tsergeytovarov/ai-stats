import SwiftUI

struct SyncIconButton: View {
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: BrandRadius.button, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.14 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.button, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
