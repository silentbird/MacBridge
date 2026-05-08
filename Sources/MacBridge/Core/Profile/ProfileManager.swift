import AppKit
import Combine
import Foundation

/// Orchestrates per-keyboard profile state: observes `KeyboardDetector`,
/// applies/clears `hidutil` mappings to match the stored preference for each
/// connected device, and cleans up on termination.
final class ProfileManager: ObservableObject {
    private let store: ProfileStoring
    private let detector: KeyboardDetector
    private var cancellables = Set<AnyCancellable>()

    /// VID-PID keys of devices whose mapping is currently applied in kernel.
    @Published private(set) var appliedKeyboards = Set<String>()
    @Published private(set) var lastError: String?

    init(store: ProfileStoring, detector: KeyboardDetector) {
        self.store = store
        self.detector = detector

        detector.$devices
            .sink { [weak self] devices in
                self?.syncMappings(for: devices)
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.cleanupAll()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public

    func profile(for device: KeyboardDevice) -> KeyboardProfile {
        store.profile(for: device)
    }

    func setSwapEnabled(_ enabled: Bool, for device: KeyboardDevice) {
        var profile = store.profile(for: device)
        profile.swapModifiers = enabled
        store.setProfile(profile, for: device)
        syncMappings(for: detector.devices)
    }

    func isApplied(_ device: KeyboardDevice) -> Bool {
        appliedKeyboards.contains(key(for: device))
    }

    /// Clears every mapping this session applied. Called on Quit button and on
    /// `NSApplication.willTerminateNotification` as a safety net.
    func cleanupAll() {
        for vidpid in appliedKeyboards {
            let parts = vidpid.split(separator: "-")
            guard parts.count == 2,
                  let vid = UInt32(parts[0], radix: 16),
                  let pid = UInt32(parts[1], radix: 16) else { continue }
            try? HIDUtil.clear(vendorID: vid, productID: pid)
        }
        appliedKeyboards.removeAll()
    }

    // MARK: - Private

    private func syncMappings(for devices: [KeyboardDevice]) {
        let currentKeys = Set(devices.map(key(for:)))

        for device in devices {
            let k = key(for: device)
            let shouldApply = store.profile(for: device).swapModifiers
            let currentlyApplied = appliedKeyboards.contains(k)

            if shouldApply && !currentlyApplied {
                applyMapping(for: device)
            } else if !shouldApply && currentlyApplied {
                clearMapping(for: device)
            }
        }

        // Forget about disconnected devices. No clear() needed — the device is
        // gone so there's nothing to un-map.
        appliedKeyboards = appliedKeyboards.intersection(currentKeys)
    }

    private func applyMapping(for device: KeyboardDevice) {
        do {
            try HIDUtil.apply(
                mapping: ModifierSwapPreset.winLayoutToMac,
                vendorID: device.vendorID,
                productID: device.productID
            )
            appliedKeyboards.insert(key(for: device))
            lastError = nil
        } catch {
            lastError = "apply \(device.productName): \(error)"
        }
    }

    private func clearMapping(for device: KeyboardDevice) {
        do {
            try HIDUtil.clear(
                vendorID: device.vendorID,
                productID: device.productID
            )
            appliedKeyboards.remove(key(for: device))
            lastError = nil
        } catch {
            lastError = "clear \(device.productName): \(error)"
        }
    }

    private func key(for device: KeyboardDevice) -> String {
        String(format: "%04X-%04X", device.vendorID, device.productID)
    }
}
