import XCTest
@testable import MacBridge

/// Pure unit tests for the onboarding decision logic. Avoids `Timer`-based
/// polling and TCC entirely by injecting a stub `PermissionProbe`.
final class OnboardingStateTests: XCTestCase {
    private var settings: AppSettings!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: shouldPresent

    func testShouldPresent_FirstLaunch_ReturnsTrueRegardlessOfPermissions() {
        // Permissions all granted but completed flag absent → still show
        // (this is the "fresh install" case).
        settings.onboardingCompleted = false
        XCTAssertTrue(
            OnboardingState.shouldPresent(settings: settings, probe: probeAll(true))
        )
    }

    func testShouldPresent_ReturningUser_AllGranted_ReturnsFalse() {
        settings.onboardingCompleted = true
        XCTAssertFalse(
            OnboardingState.shouldPresent(settings: settings, probe: probeAll(true))
        )
    }

    func testShouldPresent_ReturningUser_AnyMissing_ReturnsTrue() {
        settings.onboardingCompleted = true
        let cases: [PermissionProbe] = [
            PermissionProbe(accessibility: { false }, inputMonitoring: { true  }, postEvents: { true  }),
            PermissionProbe(accessibility: { true  }, inputMonitoring: { false }, postEvents: { true  }),
            PermissionProbe(accessibility: { true  }, inputMonitoring: { true  }, postEvents: { false }),
        ]
        for probe in cases {
            XCTAssertTrue(
                OnboardingState.shouldPresent(settings: settings, probe: probe),
                "Expected wizard to show when any one permission is missing"
            )
        }
    }

    // MARK: Initial step selection

    func testInitialStep_FirstLaunch_StartsAtWelcome() {
        settings.onboardingCompleted = false
        let state = OnboardingState(settings: settings, probe: probeAll(false))
        XCTAssertEqual(state.currentStep, .welcome)
    }

    func testInitialStep_ReturningUser_JumpsToPermissions() {
        // No reason to make a user re-read the welcome blurb just because a
        // permission got revoked across reboot.
        settings.onboardingCompleted = true
        let state = OnboardingState(settings: settings, probe: probeAll(false))
        XCTAssertEqual(state.currentStep, .permissions)
    }

    // MARK: Snapshot

    func testPermissionSnapshot_ReflectsProbe() {
        let probe = PermissionProbe(
            accessibility:   { true },
            inputMonitoring: { false },
            postEvents:      { true }
        )
        let state = OnboardingState(settings: settings, probe: probe)
        XCTAssertTrue(state.permissionStatus.accessibility)
        XCTAssertFalse(state.permissionStatus.inputMonitoring)
        XCTAssertTrue(state.permissionStatus.postEvents)
        XCTAssertFalse(state.permissionStatus.allGranted)
    }

    func testRefresh_PicksUpNewProbeValues() {
        // Start with all denied.
        var current = (acc: false, input: false, post: false)
        let probe = PermissionProbe(
            accessibility:   { current.acc },
            inputMonitoring: { current.input },
            postEvents:      { current.post }
        )
        let state = OnboardingState(settings: settings, probe: probe)
        XCTAssertFalse(state.permissionStatus.allGranted)

        current = (true, true, true)
        state.refresh()
        XCTAssertTrue(state.permissionStatus.allGranted)
    }

    // MARK: Completion

    func testMarkCompleted_PersistsIntoSettings() {
        settings.onboardingCompleted = false
        let state = OnboardingState(settings: settings, probe: probeAll(true))
        state.markCompleted()
        XCTAssertTrue(settings.onboardingCompleted)
        XCTAssertTrue(defaults.bool(forKey: "onboarding.completed"))
    }

    func testMarkCompleted_IsIdempotent() {
        settings.onboardingCompleted = true
        let state = OnboardingState(settings: settings, probe: probeAll(true))
        state.markCompleted()
        XCTAssertTrue(settings.onboardingCompleted)
    }

    // MARK: Helpers

    private func probeAll(_ value: Bool) -> PermissionProbe {
        PermissionProbe(
            accessibility:   { value },
            inputMonitoring: { value },
            postEvents:      { value }
        )
    }
}
