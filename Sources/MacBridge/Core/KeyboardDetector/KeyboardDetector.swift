import Combine
import Foundation
import IOKit
import IOKit.hid

/// Watches connected HID keyboards via `IOHIDManager`.
/// Publishes the current set and emits updates on hot-plug.
final class KeyboardDetector: ObservableObject {
    @Published private(set) var devices: [KeyboardDevice] = []

    // Diagnostics for debugging enumeration behavior.
    @Published private(set) var openResult: Int32 = 0
    @Published private(set) var initialEnumerationCount: Int = 0
    @Published private(set) var callbackConnects: Int = 0
    @Published private(set) var callbackRemoves: Int = 0
    @Published private(set) var lastSnapshot: String = ""

    var permissionDenied: Bool { openResult == kIOReturnNotPermitted }

    private let manager: IOHIDManager
    private var tracked: [ObjectIdentifier: KeyboardDevice] = [:]

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let detector = Unmanaged<KeyboardDetector>.fromOpaque(context).takeUnretainedValue()
            detector.deviceConnected(device)
        }, selfPtr)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let detector = Unmanaged<KeyboardDetector>.fromOpaque(context).takeUnretainedValue()
            detector.deviceRemoved(device)
        }, selfPtr)

        IOHIDManagerScheduleWithRunLoop(manager,
                                        CFRunLoopGetMain(),
                                        CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.openResult = result
        if result != kIOReturnSuccess {
            NSLog("IOHIDManagerOpen failed: 0x%x", result)
        }

        // Initial snapshot — even if Open failed, enumeration sometimes still works.
        if let cfSet = IOHIDManagerCopyDevices(manager) {
            let array = (cfSet as NSSet).allObjects
            self.initialEnumerationCount = array.count
            for obj in array {
                let cfObj = obj as CFTypeRef
                guard CFGetTypeID(cfObj) == IOHIDDeviceGetTypeID() else { continue }
                let device = cfObj as! IOHIDDevice
                deviceConnected(device)
            }
        }
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager,
                                          CFRunLoopGetMain(),
                                          CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - Callbacks

    private func deviceConnected(_ device: IOHIDDevice) {
        // Callbacks arrive on the run-loop thread we scheduled (main).
        // Avoiding DispatchQueue.main.async keeps state mutations synchronous
        // with the event that triggered them, and eliminates any ordering races.
        callbackConnects += 1
        guard let kb = makeKeyboardDevice(from: device) else {
            // Not a primary keyboard — e.g. a mouse that exposes media keys
            // via a secondary HID keyboard interface.
            return
        }
        tracked[ObjectIdentifier(device)] = kb
        lastSnapshot = kb.debugLabel
        refreshDevices()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        tracked.removeValue(forKey: ObjectIdentifier(device))
        callbackRemoves += 1
        refreshDevices()
    }

    private func refreshDevices() {
        // Many keyboards expose multiple HID interfaces (one for letter keys,
        // another for media/function keys). Collapse them into one row by
        // (vendor, product, name) — we key by ObjectIdentifier internally so
        // hot-plug still works, but the UI shows one entry per physical keyboard.
        var seen = Set<String>()
        var result: [KeyboardDevice] = []
        let sorted = tracked.values.sorted { $0.productName < $1.productName }
        for device in sorted {
            let key = "\(device.vendorID)-\(device.productID)-\(device.productName)"
            if seen.insert(key).inserted {
                result.append(device)
            }
        }
        devices = result
    }

    // MARK: - HID property extraction

    private func makeKeyboardDevice(from device: IOHIDDevice) -> KeyboardDevice? {
        // Filter: exclude devices that are secondary HID interfaces of a mouse.
        // Razer/Logitech mice expose a "keyboard" interface for macro remapping
        // that is structurally indistinguishable from a real keyboard at the HID
        // level (same usage pairs, same bInterfaceProtocol=1, full letter-key
        // elements). The only reliable signal is at the USB-device level:
        // the same IOUSBHostDevice has another interface with bInterfaceProtocol=2
        // (the mouse endpoint). If we find one, skip this device.
        if hasMouseSiblingInterface(device) { return nil }

        let vendorID = integerProperty(device, key: kIOHIDVendorIDKey).map(UInt32.init) ?? 0
        let productID = integerProperty(device, key: kIOHIDProductIDKey).map(UInt32.init) ?? 0
        let productName = stringProperty(device, key: kIOHIDProductKey) ?? "Unknown Keyboard"
        let transportRaw = stringProperty(device, key: kIOHIDTransportKey)
        let locationID = integerProperty(device, key: kIOHIDLocationIDKey) ?? 0

        // Unique id: prefer locationID (stable per physical port/bluetooth session);
        // fall back to a combination that at least varies with product.
        let id: UInt64
        if locationID != 0 {
            id = UInt64(locationID)
        } else if vendorID != 0 || productID != 0 {
            id = (UInt64(vendorID) << 32) | UInt64(productID)
        } else {
            // No identifying info at all — use Swift-side object identity so we
            // at least don't collapse two property-less devices into one row.
            id = UInt64(UInt(bitPattern: ObjectIdentifier(device).hashValue))
        }

        return KeyboardDevice(
            id: id,
            vendorID: vendorID,
            productID: productID,
            productName: productName,
            transport: .init(raw: transportRaw)
        )
    }

    private func integerProperty(_ device: IOHIDDevice, key: String) -> Int? {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int
    }

    /// Walks up from the HID device to its USBHostDevice and checks whether
    /// any sibling USB interface declares `bInterfaceProtocol = 2` (Mouse).
    /// Bluetooth devices don't live under USBHostDevice — they return `false`
    /// here, which is fine since BT keyboards aren't packaged with mice.
    private func hasMouseSiblingInterface(_ device: IOHIDDevice) -> Bool {
        let service = IOHIDDeviceGetService(device)
        guard service != IO_OBJECT_NULL else { return false }

        // Walk up until we find an IOUSBHostDevice (the physical USB device).
        var usbDevice: io_object_t = IO_OBJECT_NULL
        var current = service
        var retained: [io_object_t] = []
        for _ in 0..<10 {
            var parent: io_object_t = IO_OBJECT_NULL
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS,
                  parent != IO_OBJECT_NULL else { break }
            if IOObjectConformsTo(parent, "IOUSBHostDevice") != 0 {
                usbDevice = parent
                break
            }
            retained.append(parent)
            current = parent
        }
        defer {
            for obj in retained { IOObjectRelease(obj) }
            if usbDevice != IO_OBJECT_NULL { IOObjectRelease(usbDevice) }
        }
        guard usbDevice != IO_OBJECT_NULL else { return false }

        // Enumerate children (USB interfaces) and check their protocol byte.
        var iter: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(usbDevice, kIOServicePlane, &iter) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iter) }

        while case let child = IOIteratorNext(iter), child != IO_OBJECT_NULL {
            defer { IOObjectRelease(child) }
            let raw = IORegistryEntryCreateCFProperty(
                child,
                "bInterfaceProtocol" as CFString,
                kCFAllocatorDefault,
                0
            )
            if let proto = raw?.takeRetainedValue() as? Int, proto == 2 {
                return true
            }
        }
        return false
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }
}
