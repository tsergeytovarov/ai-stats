import XCTest
@testable import StatsApp

final class KeychainStoreTests: XCTestCase {
    var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = MemoryKeychainStore()
    }

    func testSetAndGetRoundtrip() throws {
        try store.set("secret-value", account: "test", service: "test-service")
        XCTAssertEqual(store.get(account: "test", service: "test-service"), "secret-value")
    }

    func testGetReturnsNilWhenMissing() {
        XCTAssertNil(store.get(account: "missing", service: "test-service"))
    }

    func testSetOverwritesExisting() throws {
        try store.set("old", account: "test", service: "svc")
        try store.set("new", account: "test", service: "svc")
        XCTAssertEqual(store.get(account: "test", service: "svc"), "new")
    }

    func testDeleteRemovesValue() throws {
        try store.set("v", account: "test", service: "svc")
        try store.delete(account: "test", service: "svc")
        XCTAssertNil(store.get(account: "test", service: "svc"))
    }

    func testDeleteMissingDoesNotThrow() throws {
        try store.delete(account: "never-existed", service: "svc")
    }

    func testDifferentServicesAreIsolated() throws {
        try store.set("a", account: "user", service: "svc-1")
        try store.set("b", account: "user", service: "svc-2")
        XCTAssertEqual(store.get(account: "user", service: "svc-1"), "a")
        XCTAssertEqual(store.get(account: "user", service: "svc-2"), "b")
    }
}
