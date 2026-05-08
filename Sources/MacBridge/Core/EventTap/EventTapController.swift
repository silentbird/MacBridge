import AppKit
import Combine
import CoreGraphics
import Foundation

/// Owns the global `CGEventTap` and runs a pipeline of `KeyRemapRule`s
/// against every key event. The tap is started/stopped based on whether
/// any feature that needs it is enabled.
final class EventTapController: ObservableObject {
    @Published private(set) var statusText: String = "Off"
    @Published var devABTestEnabled: Bool = false {
        didSet { reconcile() }
    }

    // Diagnostics — surface in the menu so we can see where the pipeline stalls.
    @Published private(set) var eventsSeen: Int = 0
    @Published private(set) var eventsRemapped: Int = 0
    @Published private(set) var lastFrontmost: String = "-"

    private let settings: AppSettings
    private let frontmost = FrontmostAppTracker()
    private var rules: [KeyRemapRule] = []
    private var cancellables = Set<AnyCancellable>()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(settings: AppSettings) {
        self.settings = settings

        rules = [
            CtrlSemanticRule(settings: settings, frontmost: frontmost),
            DevABTestRule(isEnabled: { [weak self] in self?.devABTestEnabled ?? false }),
        ]

        settings.$ctrlSemanticEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)

        reconcile()
        DispatchQueue.main.async { [weak self] in
            self?.reconcile()
        }
    }

    // MARK: - Lifecycle

    private var anyRuleWantsTap: Bool {
        settings.ctrlSemanticEnabled || devABTestEnabled
    }

    private func reconcile() {
        if anyRuleWantsTap {
            start()
        } else {
            stop()
        }
    }

    /// Re-attempt tap creation (e.g. after the user just granted Accessibility
    /// permission). No-op if tap is already running.
    func retryStart() {
        stop()
        reconcile()
    }

    /// Synchronize the running tap with the current settings. Useful when the
    /// menu is opened after app launch or after TCC permission changes.
    func refresh() {
        reconcile()
    }

    private func start() {
        guard tap == nil else { return }
        statusText = "Starting"

        // Silent check — do NOT show the system prompt here. TCC may report
        // "not trusted" even after the user granted us in System Settings if
        // the binary was re-signed (ad-hoc rebuild changes the signature hash).
        // Prompting here would spam a dialog every launch. The launch-time
        // `AccessibilityPermission.checkAndPromptIfNeeded()` + the menu's
        // "Re-check permissions" button own the user-facing prompt flow.
        guard AccessibilityPermission.isTrusted() else {
            statusText = "Need Accessibility — use 'Re-check permissions'"
            return
        }
        guard AccessibilityPermission.canListenToInput() else {
            statusText = "Need Input Monitoring — use 'Re-check permissions'"
            return
        }
        guard AccessibilityPermission.canPostEvents() else {
            statusText = "Need Event Posting — use 'Re-check permissions'"
            return
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<EventTapController>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                return controller.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            statusText = "Failed to create event tap — check Input Monitoring"
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        self.tap = newTap
        self.runLoopSource = source
        statusText = "Active"
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        statusText = "Off"
    }

    // MARK: - Callback

    private func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == KeyRemapSyntheticEvent.userData {
            return Unmanaged.passUnretained(event)
        }

        let context = KeyRemapContext(frontmostBundleID: frontmost.bundleID)
        let flagsBefore = event.flags.rawValue
        let keyBefore = event.getIntegerValueField(.keyboardEventKeycode)
        var suppressed = false
        for rule in rules {
            if rule.apply(to: event, type: type, context: context) == .suppress {
                suppressed = true
                break
            }
        }
        let changed = event.flags.rawValue != flagsBefore ||
                      event.getIntegerValueField(.keyboardEventKeycode) != keyBefore ||
                      suppressed

        // Diagnostics — hop to main queue since @Published must publish there.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.eventsSeen &+= 1
            if changed { self.eventsRemapped &+= 1 }
            self.lastFrontmost = context.frontmostBundleID ?? "-"
        }

        if suppressed {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
