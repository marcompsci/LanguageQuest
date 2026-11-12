import XCTest
@testable import LQCore

/// Regression tests for fixes made during the App Store / TestFlight compliance audit.
final class ComplianceTests: XCTestCase {
    func testUnreadableSaveIsKeptAsideNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lq-\(UUID().uuidString)")
        let store = FileSaveStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let junk = Data("not json".utf8)
        try junk.write(to: dir.appendingPathComponent("family.json"))
        XCTAssertThrowsError(try store.load())
        let moved = store.quarantineUnreadable(now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(moved.map(\.lastPathComponent), ["family.unreadable-100.json"])
        XCTAssertEqual(try Data(contentsOf: moved[0]), junk, "original bytes preserved")
        XCTAssertNil(try store.load(), "fresh start after quarantine")
        try store.save(FamilySave())
        XCTAssertEqual(try Data(contentsOf: moved[0]), junk, "saving again never touches the quarantined file")
    }

    func testNoPlaceholderOrComingSoonTextInVillage() {
        for lang in ["es", "fr", "ja", "de", "it", "zh", "yo", "he", "egy", "am", "grc", "la", "hbo"] {
            for s in StarterVillage.signs {
                let t = s.text(lang).lowercased() + " " + s.english.lowercased()
                for bad in ["coming soon", "(bald)", "(presto)", "bientôt", "próximamente", "todo", "placeholder"] {
                    XCTAssertFalse(t.contains(bad), "\(lang): \(t)")
                }
            }
        }
    }

    func testLookoutOpensInStarterCourses() throws {
        let lib = try ContentLibrary.bundled("en-de")
        let prog = Progression(library: lib)
        let exit = try XCTUnwrap(StarterVillage.exits.first)
        var p = PlayerProfile(nickname: "", ageBand: .age13to15, courseId: "en-de", variant: "de-DE")
        XCTAssertFalse(prog.isExitOpen(exit, p.progress))
        for q in lib.allQuests { for a in q.activities { prog.complete(activity: a, outcome: .init(correct: true), profile: &p, now: Date()) } }
        XCTAssertTrue(prog.isExitOpen(exit, p.progress), "a 1-unit course can reach the lookout")
    }

    func testPrivacyInventoryCoversEveryOnDeviceDataType() {
        let all = PrivacyNotice.dataInventory.map { $0.data.lowercased() }.joined(separator: " ")
        for needle in ["nickname", "progress", "speech", "handwriting", "achievements", "purchase"] {
            XCTAssertTrue(all.contains(needle), needle)
        }
        XCTAssertFalse(all.contains("spanish variant"), "inventory is up to date for all languages")
        XCTAssertTrue(PrivacyNotice.dataInventory.allSatisfy { !$0.whereKept.lowercased().contains("server") })
    }

    func testPaidPlansStayOffInThisBuild() {
        XCTAssertFalse(StoreConfig.default.paidPlansEnabled, "turning purchases on needs the 3.1 checklist first")
    }
}

final class PrivacyPolicyTests: XCTestCase {
    func testPolicyShipsInsideTheAppAndMatchesDocs() throws {
        let inApp = PrivacyNotice.policyMarkdown()
        XCTAssertTrue(inApp.contains("# Language Quest Privacy Policy"))
        for needle in ["does not collect", "on-device", "Export", "Delete", "under 13", "Contact"] {
            XCTAssertTrue(inApp.contains(needle), needle)
        }
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../docs/privacy-policy.md").standardized
        XCTAssertEqual(try String(contentsOf: docs, encoding: .utf8), inApp, "docs/privacy-policy.md must match the in-app copy")
    }
}
