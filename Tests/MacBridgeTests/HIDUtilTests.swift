import XCTest
@testable import MacBridge

final class HIDUtilTests: XCTestCase {
    // MARK: matchingJSON

    func testMatchingJSONNoFilter() {
        XCTAssertEqual(HIDUtil.matchingJSON(vendorID: nil, productID: nil), "{}")
    }

    func testMatchingJSONVendorOnly() {
        XCTAssertEqual(
            HIDUtil.matchingJSON(vendorID: 0x05AC, productID: nil),
            "{\"VendorID\":1452}"
        )
    }

    func testMatchingJSONVendorAndProduct() {
        XCTAssertEqual(
            HIDUtil.matchingJSON(vendorID: 0x05AC, productID: 0x027E),
            "{\"VendorID\":1452,\"ProductID\":638}"
        )
    }

    // MARK: mappingSetJSON

    func testMappingSetJSONEmpty() {
        XCTAssertEqual(HIDUtil.mappingSetJSON([]), "{\"UserKeyMapping\":[]}")
    }

    func testMappingSetJSONSingleEntry() {
        let mapping = [KeyMapping(src: HIDKeyUsage.leftAlt, dst: HIDKeyUsage.leftGUI)]
        XCTAssertEqual(
            HIDUtil.mappingSetJSON(mapping),
            "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0x7000000e2,\"HIDKeyboardModifierMappingDst\":0x7000000e3}]}"
        )
    }

    func testWinLayoutPresetHasFourSwapEntries() {
        let json = HIDUtil.mappingSetJSON(ModifierSwapPreset.winLayoutToMac)
        // 4 entries → 4 Src occurrences
        XCTAssertEqual(
            json.components(separatedBy: "HIDKeyboardModifierMappingSrc").count - 1,
            4
        )
        // all 4 modifier usages present
        XCTAssertTrue(json.contains("0x7000000e2"))
        XCTAssertTrue(json.contains("0x7000000e3"))
        XCTAssertTrue(json.contains("0x7000000e6"))
        XCTAssertTrue(json.contains("0x7000000e7"))
    }

    // MARK: applyCommand

    func testApplyCommandStructure() {
        let cmd = HIDUtil.applyCommand(
            mapping: ModifierSwapPreset.winLayoutToMac,
            vendorID: 0x1234,
            productID: 0x5678
        )
        XCTAssertEqual(cmd.executable, "/usr/bin/hidutil")
        XCTAssertEqual(cmd.arguments.count, 5)
        XCTAssertEqual(cmd.arguments[0], "property")
        XCTAssertEqual(cmd.arguments[1], "--matching")
        XCTAssertEqual(cmd.arguments[2], "{\"VendorID\":4660,\"ProductID\":22136}")
        XCTAssertEqual(cmd.arguments[3], "--set")
        XCTAssertTrue(cmd.arguments[4].hasPrefix("{\"UserKeyMapping\":["))
    }

    // MARK: shellString

    func testShellStringQuoting() {
        let s = HIDUtil.shellString(mapping: [], vendorID: 0x05AC, productID: nil)
        XCTAssertTrue(s.hasPrefix("/usr/bin/hidutil "))
        XCTAssertTrue(s.contains("'property'"))
        XCTAssertTrue(s.contains("'--matching'"))
        XCTAssertTrue(s.contains("'{\"VendorID\":1452}'"))
    }
}
