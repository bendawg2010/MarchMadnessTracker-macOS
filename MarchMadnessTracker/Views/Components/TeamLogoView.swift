import SwiftUI

struct TeamLogoView: View {
    let url: URL?
    var size: CGFloat = 20

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                case .failure:
                    fallbackIcon
                case .empty:
                    ProgressView()
                        .frame(width: size, height: size)
                        .scaleEffect(0.5)
                @unknown default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "basketball.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.8, height: size * 0.8)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}
