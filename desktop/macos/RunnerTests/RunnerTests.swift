import Cocoa
import FlutterMacOS
import XCTest
@testable import Xingyu

class RunnerTests: XCTestCase {
  func testKeychainRoundTripUpdatesAndDelete() throws {
    let key = "xingyu.selfcheck.\(UUID().uuidString)"
    defer { try? XingyuKeychain.delete(key) }
    try XingyuKeychain.write(key, value: "星屿 · 测试会话")
    XCTAssertEqual(try XingyuKeychain.read(key), "星屿 · 测试会话")
    try XingyuKeychain.write(key, value: "更新后的临时值")
    XCTAssertEqual(try XingyuKeychain.read(key), "更新后的临时值")
    try XingyuKeychain.delete(key)
    XCTAssertNil(try XingyuKeychain.read(key))
  }

  func testInvalidStorageKeyRejected() {
    XCTAssertThrowsError(try XingyuKeychain.query("../session"))
    XCTAssertThrowsError(try XingyuKeychain.query(""))
  }

  func testInvalidClipboardDataRejected() {
    XCTAssertThrowsError(try XingyuNativeBridge.validateImage(Data("not an image".utf8)))
  }
}
