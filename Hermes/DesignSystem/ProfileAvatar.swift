import SwiftUI
import UIKit

/// A bot's identity mark, matching Hermes Desktop:
/// 1. the bot's Studio avatar (Desktop's rendered blob face, or a photo);
/// 2. otherwise Desktop's profile glyph: a soft tint of the profile's
///    deterministic hue carrying its initial. The default profile, which has
///    no color of its own on Desktop, gets a neutral home glyph.
struct ProfileAvatar: View {
    var name: String
    var color: Color?
    var isDefault: Bool
    var size: CGFloat = 32
    var avatarData: String?

    init(profile: Profile?, size: CGFloat = 32) {
        name = profile?.name ?? "Hermes"
        isDefault = profile?.isDefault ?? (profile == nil)
        color = profile.map(IdentityColor.color(for:))
        self.size = size
        avatarData = profile?.avatarData
    }

    var body: some View {
        Group {
            if let avatar = AvatarImageCache.image(for: avatarData) {
                if avatar.isOpaque {
                    Image(uiImage: avatar.image).resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                } else {
                    // Blob faces carry their own silhouette; don't clip them.
                    Image(uiImage: avatar.image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: size, height: size)
                }
            } else {
                glyph
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var glyph: some View {
        let tint = isDefault ? Color.secondary : (color ?? .secondary)
        return RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tint.opacity(isDefault ? 0.12 : 0.18))
            .overlay {
                if isDefault {
                    Image(systemName: "house.fill")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
    }
}

/// Avatar with a status dot in the corner. Idle and unknown show no dot.
struct ProfileAvatarWithStatus: View {
    var profile: Profile?
    var size: CGFloat = 36

    var body: some View {
        ProfileAvatar(profile: profile, size: size)
            .overlay(alignment: .bottomTrailing) {
                if let status = profile?.status, status == .working || status == .needsAttention {
                    StatusDot(color: status.tint, pulsing: status == .working, size: max(7, size * 0.22))
                        .padding(2)
                        .background(Circle().fill(Color(uiColor: .systemBackground)))
                        .offset(x: 3, y: 3)
                }
            }
    }
}

/// Deterministic identity hue, ported from Desktop's `profileColor`:
/// `hsl(hash(name) % 360, 68%, 58%)`, where hash is `h * 31 + code unit`.
enum IdentityColor {
    nonisolated static func hue(for key: String) -> Double {
        var hash: UInt32 = 0
        for unit in key.utf16 { hash = hash &* 31 &+ UInt32(unit) }
        return Double(hash % 360) / 360
    }

    static func color(for profile: Profile) -> Color {
        // Simulation fixtures carry an explicit tint; real bots derive theirs.
        if profile.isBotMode != true && profile.tint != .slate { return profile.tint.color }
        let key = profile.profileKey ?? profile.name.lowercased().replacingOccurrences(of: " ", with: "-")
        // HSL(68%, 58%) expressed as HSB.
        return Color(hue: hue(for: key), saturation: 0.66, brightness: 0.866)
    }
}

/// Decodes `data:` avatar URIs once; rows re-render constantly.
enum AvatarImageCache {
    struct Avatar { var image: UIImage; var isOpaque: Bool }
    private static let cache = NSCache<NSString, Box>()
    private final class Box { let value: Avatar; init(_ value: Avatar) { self.value = value } }

    static func image(for dataURI: String?) -> Avatar? {
        guard let dataURI, !dataURI.isEmpty else { return nil }
        let key = "\(dataURI.count):\(dataURI.suffix(64))" as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        guard let raw = dataURI.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(raw)), let image = UIImage(data: data) else { return nil }
        let alpha = image.cgImage?.alphaInfo ?? .none
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(alpha)
        let avatar = Avatar(image: image, isOpaque: opaque)
        cache.setObject(Box(avatar), forKey: key)
        return avatar
    }
}

#Preview {
    HStack {
        ForEach(ProfileTint.allCases, id: \.self) { tint in
            ProfileAvatar(profile: Profile(id: tint.rawValue, name: tint.rawValue, role: "", summary: "", tint: tint,
                                           model: MockModels.sonnet, status: .idle, hostID: "", isDefault: false,
                                           skillIDs: [], toolsets: [], mcpServerIDs: []))
        }
    }
    .padding()
}
