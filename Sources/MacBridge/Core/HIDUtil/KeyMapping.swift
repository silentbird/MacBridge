import Foundation

/// A single src→dst key remap entry. Serializes to the exact key names
/// `hidutil` expects inside the `UserKeyMapping` array.
struct KeyMapping: Equatable, Hashable {
    let src: UInt64
    let dst: UInt64
}
