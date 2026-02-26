@MainActor
public final class LucidBannerRegistry {

    public static let shared = LucidBannerRegistry()

    private var instances: [String: LucidBanner] = [:]

    public func banner(for scene: UIWindowScene) -> LucidBanner {
        let id = scene.session.persistentIdentifier

        if let existing = instances[id] {
            return existing
        }

        let banner = LucidBanner()
        instances[id] = banner
        return banner
    }

    public func remove(for scene: UIWindowScene) {
        let id = scene.session.persistentIdentifier
        instances[id] = nil
    }
}
