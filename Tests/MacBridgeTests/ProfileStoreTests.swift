import XCTest
@testable import MacBridge

final class ProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: ProfileStore!

    override func setUp() {
        super.setUp()
        let suite = "ProfileStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        store = ProfileStore(defaults: defaults)
    }

    private func makeDevice(vid: UInt32, pid: UInt32, name: String, layout: KeyboardLayout) -> KeyboardDevice {
        KeyboardDevice(
            id: UInt64(vid) << 32 | UInt64(pid),
            vendorID: vid,
            productID: pid,
            productName: name,
            transport: .usb
        )
    }

    // MARK: - Defaults by layout

    func testDefaultForWindowsKeyboardSwaps() {
        let device = makeDevice(vid: 0x1234, pid: 0x5678, name: "Some Win Keyboard", layout: .windows)
        let profile = store.profile(for: device)
        XCTAssertTrue(profile.swapModifiers)
    }

    func testDefaultForAppleKeyboardDoesNotSwap() {
        let device = makeDevice(vid: 0x05AC, pid: 0x027E, name: "Apple Internal", layout: .apple)
        let profile = store.profile(for: device)
        XCTAssertFalse(profile.swapModifiers)
    }

    // MARK: - Persistence

    func testRoundTrip() {
        let device = makeDevice(vid: 0x1234, pid: 0x5678, name: "KBD", layout: .windows)
        store.setProfile(KeyboardProfile(swapModifiers: false), for: device)
        XCTAssertFalse(store.profile(for: device).swapModifiers)
    }

    func testStoredValueOverridesDefault() {
        // Apple keyboard → default false. Set true → read back true.
        let device = makeDevice(vid: 0x05AC, pid: 0x027E, name: "Apple", layout: .apple)
        store.setProfile(KeyboardProfile(swapModifiers: true), for: device)
        XCTAssertTrue(store.profile(for: device).swapModifiers)
    }

    func testDifferentDevicesIsolated() {
        let a = makeDevice(vid: 0x1234, pid: 0x0001, name: "A", layout: .windows)
        let b = makeDevice(vid: 0x1234, pid: 0x0002, name: "B", layout: .windows)
        store.setProfile(KeyboardProfile(swapModifiers: false), for: a)
        // a was explicitly set to false; b still has default (true for Windows)
        XCTAssertFalse(store.profile(for: a).swapModifiers)
        XCTAssertTrue(store.profile(for: b).swapModifiers)
    }
}
