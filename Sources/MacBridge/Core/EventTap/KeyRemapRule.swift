import CoreGraphics
import Foundation

/// Context passed to every rule invocation. Carries information about the
/// event's surroundings (e.g. frontmost app) so rules don't need to re-query.
struct KeyRemapContext {
    let frontmostBundleID: String?
}

enum KeyRemapSyntheticEvent {
    /// Marks events that MacBridge posted itself so the event tap does not
    /// remap them a second time when they re-enter the session stream.
    static let userData: Int64 = 0x4D_42_52_49_44_47_45  // "MBRIDGE"
}

enum KeyRemapResult: Equatable {
    case pass
    case suppress
}

/// A key-event rewrite rule. Rules may mutate an event in place or suppress it
/// after posting their own replacement. Multiple rules run in order; each sees
/// the event after previous rules' mutations.
protocol KeyRemapRule: AnyObject {
    func apply(to event: CGEvent, type: CGEventType, context: KeyRemapContext) -> KeyRemapResult
}
