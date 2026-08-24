import XCTest
@testable import AscendKit

final class VitalsTests: XCTestCase {

    private let sessionID = UUID()

    private func hr(_ value: Double, minutesAgo: Int = 0, session: UUID? = nil) -> VitalsSample {
        VitalsSample(
            sessionID: session ?? sessionID,
            kind: .heartRate,
            value: value,
            recordedAt: Date(timeIntervalSince1970: 10_000 - Double(minutesAgo) * 60),
            source: .liveDuringWorkout
        )
    }

    func testHeartRateSummaryAveragesAndPeaks() {
        let summary = VitalsSummary.heartRate(
            for: sessionID,
            in: [hr(120), hr(140), hr(160)]
        )
        XCTAssertEqual(summary?.peak, 160)
        XCTAssertEqual(summary?.average, 140)
    }

    func testHeartRateAverageRoundsRatherThanTruncates() {
        // 100 and 101 average to 100.5, which should present as 101, not 100.
        let summary = VitalsSummary.heartRate(for: sessionID, in: [hr(100), hr(101)])
        XCTAssertEqual(summary?.average, 101)
    }

    func testHeartRateSummaryIgnoresOtherSessions() {
        let other = UUID()
        let summary = VitalsSummary.heartRate(
            for: sessionID,
            in: [hr(100), hr(200, session: other)]
        )
        XCTAssertEqual(summary?.peak, 100)
    }

    func testHeartRateSummaryIsNilWithoutData() {
        XCTAssertNil(VitalsSummary.heartRate(for: sessionID, in: []))
    }

    func testLatestReturnsTheMostRecentOfAKind() {
        let old = VitalsSample(kind: .bloodOxygen, value: 96,
                               recordedAt: Date(timeIntervalSince1970: 1000),
                               source: .periodicSpotCheck)
        let recent = VitalsSample(kind: .bloodOxygen, value: 98,
                                  recordedAt: Date(timeIntervalSince1970: 5000),
                                  source: .periodicSpotCheck)
        XCTAssertEqual(VitalsSummary.latest(.bloodOxygen, in: [old, recent])?.value, 98)
    }

    func testAvailableKindsIsInferredFromDataNotHardware() {
        // The point of this: capability comes from readings actually arriving,
        // because there is no reliable API for which Watch is paired.
        let samples = [hr(120),
                       VitalsSample(kind: .bloodOxygen, value: 97, source: .periodicSpotCheck)]
        XCTAssertEqual(VitalsSummary.availableKinds(in: samples), [.heartRate, .bloodOxygen])
        XCTAssertFalse(VitalsSummary.availableKinds(in: samples).contains(.wristTemperature))
    }

    func testAverageHeartRateRespectsTheDateWindow() {
        let samples = [hr(100, minutesAgo: 0), hr(200, minutesAgo: 600)]
        let recent = VitalsSummary.averageHeartRate(
            in: samples,
            from: Date(timeIntervalSince1970: 9_000),
            to: Date(timeIntervalSince1970: 11_000)
        )
        XCTAssertEqual(recent, 100)
    }

    /// The honesty rules that keep the UI from implying live SpO2 or a live
    /// temperature reading.
    func testEachKindDeclaresHowItIsActuallyObtained() {
        XCTAssertEqual(VitalsKind.heartRate.availability, .liveDuringWorkout)
        XCTAssertEqual(VitalsKind.bloodOxygen.availability, .periodicSpotCheck)
        XCTAssertEqual(VitalsKind.wristTemperature.availability, .overnightOnly)

        XCTAssertTrue(VitalsAvailability.overnightOnly.caveat.contains("not during a workout"))
        XCTAssertTrue(VitalsAvailability.periodicSpotCheck.caveat.contains("spot check"))
    }

    func testKindsCarryUnitsAndHardwareNotes() {
        XCTAssertEqual(VitalsKind.heartRate.unit, "bpm")
        XCTAssertEqual(VitalsKind.bloodOxygen.unit, "%")
        for kind in VitalsKind.allCases {
            XCTAssertFalse(kind.requiresWatch.isEmpty)
            XCTAssertFalse(kind.displayName.isEmpty)
        }
    }
}
