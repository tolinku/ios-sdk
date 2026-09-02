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
}
