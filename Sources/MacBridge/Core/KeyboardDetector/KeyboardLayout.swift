import Foundation

enum KeyboardLayout: String, Codable, CaseIterable {
    case apple = "Apple"
    case windows = "Windows"
    case unknown = "Unknown"

    // Apple vendor: see https://www.usb.org/sites/default/files/vendor_ids050723.pdf
    private static let appleVendorID: UInt32 = 0x05AC

    /// Default classification from HID properties. Users may override per device.
    static func classify(vendorID: UInt32, productName: String) -> KeyboardLayout {
        if vendorID == appleVendorID {
            return .apple
        }
        // Everything else assumed Windows-style (HHKB/Keychron/IKBC/Logitech/etc.)
        // Rationale: Win-layout is the more common external keyboard on Mac,
        // and the user can override when we get it wrong.
        return .windows
    }
}
