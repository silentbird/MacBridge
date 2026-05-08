import AppKit
import Foundation

/// Caches the bundle identifier of the frontmost application so the event-tap
/// callback doesn't pay `NSWorkspace.frontmostApplication` on every keystroke.
/// Updates on `didActivateApplicationNotification`.
final class FrontmostAppTracker {
    private(set) var bundleID: String?

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.bundleID = app?.bundleIdentifier ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func refresh() {
        bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
