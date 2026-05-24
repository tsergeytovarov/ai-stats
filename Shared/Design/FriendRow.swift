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
    /// Прошлый rank для отображения ▲N / ▼N / NEW. nil → строка без значка
    /// (зарезервированное место сохраняется, чтобы соседние строки не прыгали).
    var previousRank: Int? = nil
    /// Если true — рисуется значок дельты. Outside-call sites (widget без данных)
    /// могут пропускать это поле, тогда дельта не выводится вообще.
    var showsRankDelta: Bool = false

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

            if showsRankDelta {
                rankDeltaView
            }

            Spacer()

            Text(valueText)
                .font(BrandFont.body)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var rankDeltaView: some View {
        Group {
            if let content = DropdownFormat.formatRankDelta(current: rank, previous: previousRank) {
                switch content.kind {
                case .new:
                    Text(NSLocalizedString("delta.new", comment: ""))
                        .foregroundStyle(.secondary)
                case .change(let magnitude, let direction):
                    let arrow = direction == .up ? "▲" : "▼"
                    Text("\(arrow)\(magnitude)")
                        .foregroundStyle(direction == .up ? Color.green : Color.red)
                }
            } else {
                Text(" ")   // reserve space — другие строки не должны двигаться
            }
        }
        .font(.system(.caption, design: .monospaced))
        .frame(width: 32, alignment: .leading)
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
