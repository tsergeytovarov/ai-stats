import SwiftUI
import AppKit

struct FriendRow: View {
    let rank: Int
    let name: String
    let valueText: String
    let isMe: Bool
    /// Реальная аватарка (JPEG/PNG bytes). Если nil — рисуется brand-градиент.
    /// Defaults to nil — call sites без аватарок (например, widget) не трогаются.
    var avatarData: Data? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank).")
                .font(BrandFont.body)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 22, alignment: .leading)
                .monospacedDigit()

            avatar
                .frame(width: 22, height: 22)
                .shadow(color: isMe ? BrandColor.pink.opacity(0.5) : .clear, radius: 5)

            Text(name)
                .font(.system(size: 14, weight: isMe ? .semibold : .medium))
                .foregroundStyle(isMe ? TextColor.crumbAI : Color.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(valueText)
                .font(BrandFont.body)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarData, let img = NSImage(data: avatarData) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle().fill(avatarGradient)
        }
    }

    private var avatarGradient: LinearGradient {
        if isMe {
            return LinearGradient(colors: [BrandColor.pinkLight, BrandColor.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(
                colors: [BrandColor.pinkLight.opacity(0.8), BrandColor.cyanLight.opacity(0.8)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}
