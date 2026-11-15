import XCTest
@testable import TolinkuSDK

/// The privacy manifest is the one file in this package that is checked by
/// someone other than us: App Store Connect answers an upload that uses a
/// required reason API without a declaration with ITMS-91053, and the developer
/// who gets that email has to work out which dependency caused it.
///
/// It also has the failure mode of any declaration kept beside the code it
/// describes, which is that the code moves and the declaration does not. So
/// these tests do not merely check the file parses.
/// `testEveryRequiredReasonAPIUsedIsDeclared` reads `Sources` for the APIs Apple requires a reason for and fails if one of
/// them is called without a matching entry, which is the check that still works
/// in a year.
final class PrivacyManifestTests: XCTestCase {

    /// The package root, found from this file rather than the working directory,
    /// which `swift test` does not guarantee.
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TolinkuSDKTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
    }

    private var manifestURL: URL {
        packageRoot.appendingPathComponent("Sources/TolinkuSDK/PrivacyInfo.xcprivacy")
    }

    private func manifest() throws -> [String: Any] {
        let data = try Data(contentsOf: manifestURL)
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        return try XCTUnwrap(parsed as? [String: Any], "manifest is not a dictionary")
    }

    // MARK: - The file exists and is a plist

    func testManifestExistsAndParses() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: manifestURL.path),
            "Sources/TolinkuSDK/PrivacyInfo.xcprivacy is missing. Without it an app "
                + "embedding this package inherits our UserDefaults calls with no declaration."
        )
        let plist = try manifest()
        XCTAssertNotNil(plist["NSPrivacyTracking"], "NSPrivacyTracking is not declared")
        XCTAssertNotNil(plist["NSPrivacyAccessedAPITypes"], "NSPrivacyAccessedAPITypes is not declared")
    }

    /// A manifest that Package.swift does not name is never copied into a
    /// bundle, so it reaches no app at all while looking entirely correct in the
    /// repository. This is the mistake that is invisible without a test.
    func testPackageManifestShipsTheFile() throws {
        let packageSwift = packageRoot.appendingPathComponent("Package.swift")
        let source = try String(contentsOf: packageSwift, encoding: .utf8)
        XCTAssertTrue(
            source.contains("PrivacyInfo.xcprivacy"),
            "Package.swift does not declare PrivacyInfo.xcprivacy as a resource, so Swift "
                + "Package Manager will not ship it and no consuming app will ever see it."
        )
    }

    // MARK: - What it says

    func testTrackingIsDeclaredFalse() throws {
        let plist = try manifest()
        XCTAssertEqual(
            plist["NSPrivacyTracking"] as? Bool, false,
            "NSPrivacyTracking must stay false. This SDK never reads the advertising "
                + "identifier and never joins a person's activity to another company's data. "
                + "If that changes, the change is a product decision, not a manifest edit."
        )
        XCTAssertEqual(
            (plist["NSPrivacyTrackingDomains"] as? [String])?.count, 0,
            "NSPrivacyTrackingDomains must stay empty while NSPrivacyTracking is false. "
                + "Apple treats a populated list with tracking false as a contradiction."
        )
    }

    /// Apple requires a reason for each of these API categories. If a source
    /// file starts calling one, this fails until the manifest declares it.
    ///
    /// The markers are deliberately coarse. A false positive here costs one
    /// manifest entry; a false negative costs an App Store rejection that
    /// arrives after the release has gone out.
    func testEveryRequiredReasonAPIUsedIsDeclared() throws {
        let markers: [(category: String, needles: [String])] = [
            ("NSPrivacyAccessedAPICategoryUserDefaults", ["UserDefaults"]),
            ("NSPrivacyAccessedAPICategoryFileTimestamp",
             ["attributesOfItem", ".creationDateKey", ".contentModificationDateKey",
              "NSFileCreationDate", "NSFileModificationDate"]),
            ("NSPrivacyAccessedAPICategorySystemBootTime",
             ["systemUptime", "mach_absolute_time", "NSProcessInfo.systemUptime"]),
            ("NSPrivacyAccessedAPICategoryDiskSpace",
             ["volumeAvailableCapacity", "systemFreeSize", "systemSize"]),
            ("NSPrivacyAccessedAPICategoryActiveKeyboards", ["activeInputModes"])
        ]

        let sources = packageRoot.appendingPathComponent("Sources/TolinkuSDK")
        let files = try FileManager.default
            .contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "found no Swift sources to scan at \(sources.path)")

        var corpus = ""
        for file in files {
            corpus += (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        }

        let plist = try manifest()
        let declared = Set(
            (plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? [])
                .compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        )

        for marker in markers {
            let used = marker.needles.contains { corpus.contains($0) }
            if used {
                XCTAssertTrue(
                    declared.contains(marker.category),
                    "Sources call a required reason API in \(marker.category) but the manifest "
                        + "does not declare it. Add it with a reason code from Apple's list, or "
                        + "App Store Connect will answer the next upload with ITMS-91053."
                )
            }
        }
    }

    /// Every declared category needs at least one reason code, and a reason code
    /// has a fixed shape. An entry with an empty reason array is treated as no
    /// declaration at all.
    func testEveryDeclaredCategoryCarriesAReasonCode() throws {
        let plist = try manifest()
        let entries = try XCTUnwrap(
            plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
            "NSPrivacyAccessedAPITypes is not an array of dictionaries"
        )
        XCTAssertFalse(entries.isEmpty, "the SDK calls UserDefaults, so this cannot be empty")

        for entry in entries {
            let category = (entry["NSPrivacyAccessedAPIType"] as? String) ?? "<unnamed>"
            let reasons = (entry["NSPrivacyAccessedAPITypeReasons"] as? [String]) ?? []
            XCTAssertFalse(
                reasons.isEmpty,
                "\(category) declares no reason code, which Apple reads as no declaration"
            )
            for reason in reasons {
                XCTAssertNotNil(
                    reason.range(of: #"^[0-9A-Z]{4}\.\d+$"#, options: .regularExpression),
                    "\"\(reason)\" in \(category) is not shaped like an Apple reason code (CA92.1)"
                )
            }
        }
    }

    /// Every data type the SDK sends has to stay declared. Dropping one leaves
    /// the developer embedding us describing less than we do in their own privacy
    /// label, which is the failure this file exists to prevent, and it is not
    /// visible in a diff of the plist alone.
    func testEveryDataTypeTheSDKSendsIsDeclared() throws {
        let plist = try manifest()
        let declared = Set(
            (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
                .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        )

        let expected = [
            // deferred.claimBySignals
            "NSPrivacyCollectedDataTypeOtherDataTypes": "deferred signal matching",
            // trackLinkOpen, track, and the ecommerce interaction events
            "NSPrivacyCollectedDataTypeProductInteraction": "analytics events",
            // ecommerce.search(term:)
            "NSPrivacyCollectedDataTypeSearchHistory": "ecommerce.search",
            // ecommerce.purchase, refund, beginCheckout
            "NSPrivacyCollectedDataTypePurchaseHistory": "ecommerce revenue events",
            // setUserId and the referral calls
            "NSPrivacyCollectedDataTypeUserID": "setUserId and referrals",
            // the optional userName on referrals.create and referrals.complete
            "NSPrivacyCollectedDataTypeName": "referral display names"
        ]

        for (type, cause) in expected {
            XCTAssertTrue(
                declared.contains(type),
                "\(type) is not declared, but \(cause) still sends it"
            )
        }
    }

    /// Each collected data type needs its purposes and both flags. Xcode's
    /// privacy report skips an incomplete entry silently.
    func testEveryCollectedDataTypeIsComplete() throws {
        let plist = try manifest()
        let types = (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]]) ?? []
        XCTAssertFalse(
            types.isEmpty,
            "no collected data types are declared. Without this the two checks below "
                + "pass on an empty array, which is how deleting the whole block goes unnoticed."
        )

        for type in types {
            let name = (type["NSPrivacyCollectedDataType"] as? String) ?? "<unnamed>"
            XCTAssertNotNil(
                type["NSPrivacyCollectedDataType"] as? String,
                "a collected data type entry has no NSPrivacyCollectedDataType"
            )
            XCTAssertNotNil(
                type["NSPrivacyCollectedDataTypeLinked"] as? Bool,
                "\(name) does not say whether it is linked to identity"
            )
            XCTAssertNotNil(
                type["NSPrivacyCollectedDataTypeTracking"] as? Bool,
                "\(name) does not say whether it is used for tracking"
            )
            let purposes = (type["NSPrivacyCollectedDataTypePurposes"] as? [String]) ?? []
            XCTAssertFalse(purposes.isEmpty, "\(name) declares no purpose")
        }
    }

    /// NSPrivacyTracking false and a data type marked as used for tracking are a
    /// contradiction, and Apple reads the per type flag.
    func testNoCollectedDataTypeClaimsTracking() throws {
        let plist = try manifest()
        let types = (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]]) ?? []
        XCTAssertFalse(types.isEmpty, "no collected data types are declared")
        for type in types {
            let name = (type["NSPrivacyCollectedDataType"] as? String) ?? "<unnamed>"
            XCTAssertEqual(
                type["NSPrivacyCollectedDataTypeTracking"] as? Bool, false,
                "\(name) is marked as used for tracking while NSPrivacyTracking is false"
            )
        }
    }
}
