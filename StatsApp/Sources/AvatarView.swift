import SwiftUI
import AppKit

/// Круглая аватарка из bytes (NSImage) или SF Symbol placeholder если данных нет.
struct AvatarView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        if let data, let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
