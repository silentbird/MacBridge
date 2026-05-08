import AppKit
import Combine
import CoreGraphics
import Foundation

/// Minimal CGEventTap wrapper. POC goal: when enabled, pressing "A" emits "B".
final class EventTapController: ObservableObject {
    @Published var enabled: Bool = false {
        didSet {
            if enabled {
                start()
            } else {
                stop()
            }
        }
    }

    @Published private(set) var statusText: String = "Idle"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Virtual key codes (US layout)
    // Ref: /System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/Headers/Events.h
    private let keyCodeA: Int64 = 0
    private let keyCodeB: Int64 = 11

    private func start() {
        guard tap == nil else { return }

        guard AccessibilityPermission.check(prompt: true) else {
            statusText = "Need Accessibility permission"
            // flip back — can't run without permission
            DispatchQueue.main.async { self.enabled = false }
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
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let controller = Unmanaged<EventTapController>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                return controller.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            statusText = "Failed to create event tap"
            DispatchQueue.main.async { self.enabled = false }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        self.tap = newTap
        self.runLoopSource = source
        statusText = "Active — press A, get B"
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
        statusText = "Idle"
    }

    private func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // macOS disables the tap on timeout or unexpected user input — re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == keyCodeA {
            event.setIntegerValueField(.keyboardEventKeycode, value: keyCodeB)
        }
        return Unmanaged.passUnretained(event)
    }
}
