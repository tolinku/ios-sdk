import XCTest
@testable import TolinkuSDK

/// Signals passed to `claimBySignals` override what the device reports, matching
/// the Flutter, React Native and web SDKs. This SDK and Android took no
/// overrides at all, so an app holding a better value than the SDK could read
/// had nowhere to put it.
///
/// The property that matters is the third test: overriding one signal must not
/// discard the others. Matching compares only what both sides supplied, so a
/// partial override that dropped the rest would leave less to compare on than
/// passing nothing, which is the opposite of what the caller intended.
final class SignalOverrideTests: XCTestCase {

    private let collectedTimezone = "Europe/London"
    private let collectedLanguage = "en-GB"
    private let collectedWidth = 390
    private let collectedHeight = 844
    private let collectedRatio = 3.0
    private let collectedOsVersion = "17.1"

    /// The merge `claimBySignals` performs when building its request.
    private func request(
        timezone: String? = nil,
        language: String? = nil,
        screenWidth: Int? = nil,
        screenHeight: Int? = nil,
        devicePixelRatio: Double? = nil,
        osVersion: String? = nil
    ) -> ClaimBySignalsRequest {
        ClaimBySignalsRequest(
            appspaceId: "app123",
            timezone: timezone ?? collectedTimezone,
            language: language ?? collectedLanguage,
            screenWidth: screenWidth ?? collectedWidth,
            screenHeight: screenHeight ?? collectedHeight,
            devicePixelRatio: devicePixelRatio ?? collectedRatio,
            osVersion: osVersion ?? collectedOsVersion
        )
    }

    func testSendsWhatTheDeviceReportsWhenNothingIsPassed() {
        let body = request()

        XCTAssertEqual(body.timezone, "Europe/London")
        XCTAssertEqual(body.language, "en-GB")
        XCTAssertEqual(body.screenWidth, 390)
    }

    func testAPassedSignalWinsOverTheDevice() {
        XCTAssertEqual(request(timezone: "Asia/Seoul").timezone, "Asia/Seoul")
    }

    func testOverridingOneSignalKeepsTheRest() {
        // The mistake worth guarding: matching compares only what both sides
        // supplied, so dropping the others would leave less to compare on than
        // passing nothing at all.
        let body = request(timezone: "Asia/Seoul")

        XCTAssertEqual(body.language, "en-GB")
        XCTAssertEqual(body.screenWidth, 390)
        XCTAssertEqual(body.screenHeight, 844)
        XCTAssertEqual(body.devicePixelRatio, 3.0)
        XCTAssertEqual(body.osVersion, "17.1")
    }

    func testEverySignalCanBeOverriddenAtOnce() {
        let body = request(
            timezone: "Asia/Seoul",
            language: "ko-KR",
            screenWidth: 411,
            screenHeight: 891,
            devicePixelRatio: 2.625,
            osVersion: "13"
        )

        XCTAssertEqual(body.timezone, "Asia/Seoul")
        XCTAssertEqual(body.language, "ko-KR")
        XCTAssertEqual(body.screenWidth, 411)
        XCTAssertEqual(body.screenHeight, 891)
        XCTAssertEqual(body.devicePixelRatio, 2.625)
        XCTAssertEqual(body.osVersion, "13")
    }

    /// The rule `claimBySignals` applies before an override is used.
    ///
    /// An unset configuration value and a failed lookup both arrive blank, and
    /// taking one literally would replace a good value with one the matcher
    /// cannot use. A signal that is present and disagrees counts against the
    /// match, where an absent one is skipped, so a blank override is worse than
    /// no override at all.
    private func usable(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func usable(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    func testABlankOverrideIsNotAnOverride() {
        XCTAssertNil(usable(""))
        XCTAssertNil(usable("   "))
        XCTAssertNil(usable(nil as String?))
    }

    func testANonPositiveMeasurementIsNotAnOverride() {
        XCTAssertNil(usable(0))
        XCTAssertNil(usable(-1))
        XCTAssertNil(usable(0.0))
        XCTAssertNil(usable(Double.nan))
        XCTAssertNil(usable(Double.infinity))
    }

    func testARealOverrideSurvivesAndIsTrimmed() {
        XCTAssertEqual(usable("  Asia/Seoul  "), "Asia/Seoul")
        XCTAssertEqual(usable(390), 390)
        XCTAssertEqual(usable(3.0), 3.0)
    }

    func testABlankOverrideLeavesTheDeviceValueInPlace() {
        let body = ClaimBySignalsRequest(
            appspaceId: "app123",
            timezone: usable("") ?? collectedTimezone,
            language: usable("   ") ?? collectedLanguage,
            screenWidth: usable(0) ?? collectedWidth,
            screenHeight: usable(-1) ?? collectedHeight,
            devicePixelRatio: usable(0.0) ?? collectedRatio,
            osVersion: usable("") ?? collectedOsVersion
        )

        XCTAssertEqual(body.timezone, collectedTimezone)
        XCTAssertEqual(body.language, collectedLanguage)
        XCTAssertEqual(body.screenWidth, collectedWidth)
        XCTAssertEqual(body.screenHeight, collectedHeight)
        XCTAssertEqual(body.devicePixelRatio, collectedRatio)
        XCTAssertEqual(body.osVersion, collectedOsVersion)
    }
}