import XCTest
@testable import GymKit

final class BodyMapKeyTests: XCTestCase {

    func testEmptyRegionsPicksRest() {
        XCTAssertEqual(BodyMapKey.bestMatch(for: []), .rest)
    }

    func testExactPresetMatchesItself() {
        for key in BodyMapKey.allCases where key != .rest {
            XCTAssertEqual(BodyMapKey.bestMatch(for: key.regions), key,
                           "\(key.rawValue) should match its own region set")
        }
    }

    /// The bug this guards: fullBody contains every region, so scoring by raw
    /// overlap made it win everything and a push day lit up the whole body.
    func testPushDayDoesNotPickFullBody() {
        let pushDay: Set<MuscleRegion> = [.chest, .frontDelt, .sideDelt, .triceps]
        XCTAssertEqual(BodyMapKey.bestMatch(for: pushDay), .push)
    }

    func testLegDayPicksLegs() {
        let legDay: Set<MuscleRegion> = [.quads, .hamstrings, .glutes, .calves]
        XCTAssertEqual(BodyMapKey.bestMatch(for: legDay), .legs)
    }

    func testSingleRegionPrefersNarrowestImage() {
        // Abs alone should land on core, not on the whole-body image.
        XCTAssertEqual(BodyMapKey.bestMatch(for: [.abs]), .core)
    }

    func testEverythingPicksFullBody() {
        XCTAssertEqual(BodyMapKey.bestMatch(for: Set(MuscleRegion.allCases)), .fullBody)
    }

    func testAssetNamesMatchExportedFiles() {
        // full-body is the one key whose file name differs from its raw value.
        XCTAssertEqual(BodyMapKey.fullBody.assetName, "full-body")
        XCTAssertEqual(BodyMapKey.push.assetName, "push")
    }

    func testEveryRegionIsReachableFromSomePreset() {
        let covered = BodyMapKey.allCases.reduce(into: Set<MuscleRegion>()) {
            $0.formUnion($1.regions)
        }
        XCTAssertEqual(covered, Set(MuscleRegion.allCases))
    }
}
