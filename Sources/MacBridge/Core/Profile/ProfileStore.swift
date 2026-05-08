import Foundation

protocol ProfileStoring {
    func profile(for device: KeyboardDevice) -> KeyboardProfile
    func setProfile(_ profile: KeyboardProfile, for device: KeyboardDevice)
}

/// UserDefaults-backed profile store. Key format: `keyboard.profile.<vid>-<pid>` (hex).
final class ProfileStore: ProfileStoring {
    private let defaults: UserDefaults
    private let keyPrefix = "keyboard.profile."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func profile(for device: KeyboardDevice) -> KeyboardProfile {
        let key = defaultsKey(for: device)
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(KeyboardProfile.self, from: data) {
            return decoded
        }
        return .default(for: device.presumedLayout)
    }

    func setProfile(_ profile: KeyboardProfile, for device: KeyboardDevice) {
        let key = defaultsKey(for: device)
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }

    private func defaultsKey(for device: KeyboardDevice) -> String {
        String(format: "%@%04X-%04X", keyPrefix, device.vendorID, device.productID)
    }
}
