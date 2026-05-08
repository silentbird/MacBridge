import Foundation

struct KeyboardDevice: Identifiable, Equatable, Hashable {
    let id: UInt64
    let vendorID: UInt32
    let productID: UInt32
    let productName: String
    let transport: Transport

    enum Transport: String {
        case usb = "USB"
        case bluetooth = "Bluetooth"
        case other = "Other"

        init(raw: String?) {
            switch raw?.lowercased() {
            case "usb": self = .usb
            case "bluetooth", "bluetooth low energy": self = .bluetooth
            default: self = .other
            }
        }
    }

    /// Presumed layout based on vendor signature. User can override in settings.
    var presumedLayout: KeyboardLayout {
        KeyboardLayout.classify(vendorID: vendorID, productName: productName)
    }

    var debugLabel: String {
        String(format: "%@ (VID=0x%04X, PID=0x%04X, %@)",
               productName, vendorID, productID, transport.rawValue)
    }
}
