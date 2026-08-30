import XCTest
@testable import TolinkuSDK

/// `destroy()` is the name every Tolinku SDK uses to tear down. This SDK
/// shipped it as `shutdown()`, so both work and code moved between platforms
/// compiles. `shutdown()` is meant for deprecation later, once moving off it is
/// a one-line change rather than a surprise.
///
/// An alias is worth having only while it stays identical, so these check the
/// resulting state rather than trusting that one still calls the other.
final class DestroyAliasTests: XCTestCase {

    override func tearDown() async throws {
        await Tolinku.destroy()
        try await super.tearDown()
    }

    func testDestroyClearsTheSharedInstance() async throws {
        try Tolinku.configure(apiKey: "tolk_pub_test", baseURL: "https://links.example.com")
        XCTAssertNotNil(Tolinku.shared)

        await Tolinku.destroy()
        XCTAssertNil(Tolinku.shared, "destroy() should clear the shared instance")
    }

    func testShutdownStillWorks() async throws {
        try Tolinku.configure(apiKey: "tolk_pub_test", baseURL: "https://links.example.com")

        await Tolinku.shutdown()
        XCTAssertNil(Tolinku.shared, "shutdown() must keep working alongside destroy()")
    }

    func testCanConfigureAgainAfterEitherName() async throws {
        try Tolinku.configure(apiKey: "tolk_pub_test", baseURL: "https://links.example.com")
        await Tolinku.destroy()
        try Tolinku.configure(apiKey: "tolk_pub_second", baseURL: "https://links.example.com")
        XCTAssertEqual(try Tolinku.requireShared().client.apiKey, "tolk_pub_second")

        await Tolinku.shutdown()
        try Tolinku.configure(apiKey: "tolk_pub_third", baseURL: "https://links.example.com")
        XCTAssertEqual(try Tolinku.requireShared().client.apiKey, "tolk_pub_third")
    }

    func testDestroyOnAnUnconfiguredSDKIsHarmless() async throws {
        await Tolinku.destroy()
        await Tolinku.destroy()
        XCTAssertNil(Tolinku.shared)
    }
}
