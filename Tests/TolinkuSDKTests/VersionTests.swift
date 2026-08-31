import XCTest
@testable import TolinkuSDK

/// `Tolinku.sdkVersion` is sent in the User-Agent on every request, so a drift
/// from the released version silently misreports which SDK is in the field. The
/// Flutter SDK's constant sat at 0.1.0 through two releases before a guard like
/// this existed, and nothing about that failure was specific to Flutter.
///
/// Swift Package Manager takes its version from the git tag, so there is no
/// manifest to compare against. The CHANGELOG is the closest thing this package
/// has to a declared version, and it is edited as part of every release, so the
/// two drifting apart is the mistake worth catching.
final class VersionTests: XCTestCase {

    /// The package root, found from this file rather than the working directory,
    /// which `swift test` does not guarantee.
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TolinkuSDKTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
    }

    func testSdkVersionLooksLikeAVersion() {
        XCTAssertNotNil(
            Tolinku.sdkVersion.range(of: #"^\d+\.\d+\.\d+(-[\w.]+)?$"#, options: .regularExpression),
            "sdkVersion \"\(Tolinku.sdkVersion)\" is not a version number"
        )
    }

    func testSdkVersionMatchesTheNewestChangelogEntry() throws {
        let changelog = packageRoot.appendingPathComponent("CHANGELOG.md")
        let text = try String(contentsOf: changelog, encoding: .utf8)

        // The first "## <version>" heading, which is the release being prepared.
        var newest: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("## ") else { continue }
            newest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            break
        }

        let declared = try XCTUnwrap(newest, "no \"## <version>\" heading in CHANGELOG.md")
        XCTAssertEqual(
            Tolinku.sdkVersion,
            declared,
            "sdkVersion is \(Tolinku.sdkVersion) but the newest CHANGELOG entry is \(declared). "
                + "Bump both, or the User-Agent will name a version that was never released."
        )
    }

    func testUserAgentCarriesTheVersion() {
        // A constant nothing transmits identifies nothing. The web SDK shipped
        // without any version header at all until this was checked across SDKs.
        let client = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/TolinkuSDK/Client.swift")

        let source = (try? String(contentsOf: client, encoding: .utf8)) ?? ""
        XCTAssertTrue(
            source.contains("User-Agent"),
            "Client.swift no longer sets a User-Agent, so requests carry no SDK version"
        )
        XCTAssertTrue(
            source.contains("sdkVersion"),
            "the User-Agent no longer interpolates sdkVersion"
        )
    }
}
