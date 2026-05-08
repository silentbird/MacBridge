import CoreGraphics
import Foundation

/// Context passed to every rule invocation. Carries information about the
/// event's surroundings (e.g. frontmost app) so rules don't need to re-query.
struct KeyRemapContext {
    let frontmostBundleID: String?
}

/// A key-event rewrite rule. Rules mutate the event in place. Multiple rules
/// run in order; each sees the event after previous rules' mutations.
protocol KeyRemapRule: AnyObject {
    func apply(to event: CGEvent, type: CGEventType, context: KeyRemapContext)
}
