import Foundation

enum HIDUtilError: Error, Equatable {
    case commandFailed(exitCode: Int32, stderr: String)
}

/// Swift wrapper around `/usr/bin/hidutil` for applying modifier-key remaps.
///
/// Mapping lives in-kernel until reboot; MacBridge re-applies on launch and on
/// keyboard hot-plug. Requires no elevated privileges for
/// `UserKeyMapping` — it's a per-user setting.
enum HIDUtil {
    // MARK: - Public API

    /// Builds the `/usr/bin/hidutil` invocation for applying `mapping`, without running it.
    /// Useful for dry-run display and unit tests.
    static func applyCommand(
        mapping: [KeyMapping],
        vendorID: UInt32? = nil,
        productID: UInt32? = nil
    ) -> (executable: String, arguments: [String]) {
        (
            executable: "/usr/bin/hidutil",
            arguments: [
                "property",
                "--matching", matchingJSON(vendorID: vendorID, productID: productID),
                "--set", mappingSetJSON(mapping)
            ]
        )
    }

    /// Applies `mapping` to devices matching the given vendor/product IDs.
    /// Both nil = apply globally (use with caution — will affect MacBook's built-in keyboard).
    @discardableResult
    static func apply(
        mapping: [KeyMapping],
        vendorID: UInt32? = nil,
        productID: UInt32? = nil
    ) throws -> String {
        let cmd = applyCommand(mapping: mapping, vendorID: vendorID, productID: productID)
        return try run(executable: cmd.executable, arguments: cmd.arguments)
    }

    /// Clears any active user key mapping for the matched devices.
    static func clear(vendorID: UInt32? = nil, productID: UInt32? = nil) throws {
        try apply(mapping: [], vendorID: vendorID, productID: productID)
    }

    /// Renders the shell-ready command string (suitable for clipboard / docs / logs).
    static func shellString(
        mapping: [KeyMapping],
        vendorID: UInt32? = nil,
        productID: UInt32? = nil
    ) -> String {
        let cmd = applyCommand(mapping: mapping, vendorID: vendorID, productID: productID)
        return ([cmd.executable] + cmd.arguments.map(singleQuote)).joined(separator: " ")
    }

    // MARK: - JSON builders (exposed for tests)

    static func matchingJSON(vendorID: UInt32?, productID: UInt32?) -> String {
        var parts: [String] = []
        if let vendorID { parts.append("\"VendorID\":\(vendorID)") }
        if let productID { parts.append("\"ProductID\":\(productID)") }
        return "{" + parts.joined(separator: ",") + "}"
    }

    static func mappingSetJSON(_ mapping: [KeyMapping]) -> String {
        let entries = mapping.map { m in
            "{\"HIDKeyboardModifierMappingSrc\":\(hex(m.src))," +
            "\"HIDKeyboardModifierMappingDst\":\(hex(m.dst))}"
        }
        return "{\"UserKeyMapping\":[" + entries.joined(separator: ",") + "]}"
    }

    // MARK: - Internal

    private static func hex(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16)
    }

    /// POSIX-safe single-quote wrap for shell echoing.
    private static func singleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func run(executable: String, arguments: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()
        proc.waitUntilExit()

        let stdout = String(
            data: outPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if proc.terminationStatus != 0 {
            let stderr = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw HIDUtilError.commandFailed(
                exitCode: proc.terminationStatus,
                stderr: stderr
            )
        }

        return stdout
    }
}
