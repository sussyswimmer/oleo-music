import SwiftUI

/// Album art that cross-fades when the image changes.
struct ArtworkImage: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.12))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: image.map { ObjectIdentifier($0) })
    }
}
