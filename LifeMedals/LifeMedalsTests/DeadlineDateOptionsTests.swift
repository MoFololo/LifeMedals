import XCTest
@testable import LifeMedals

final class DeadlineDateOptionsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    func testSelectableDatesRunFromTodayThroughSameDateNextMonth() throws {
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 12))
        )
        let dates = DeadlineDateOptions.selectableDates(
            relativeTo: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 32)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(dates.first)), 21)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(dates.last)), 9)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(dates.last)), 21)
    }

    func testExplicitDateWithinRangeIsPreservedAtEndOfDay() throws {
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 12))
        )
        let explicitDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 8))
        )
        let normalized = DeadlineDateOptions.normalized(
            explicitDate,
            relativeTo: referenceDate,
            calendar: calendar
        )

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: normalized)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 30)
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 59)
    }

    func testDatesOutsideRangeClampToNearestBoundary() throws {
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 12))
        )
        let futureDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))
        )
        let normalized = DeadlineDateOptions.normalized(
            futureDate,
            relativeTo: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.month, from: normalized), 9)
        XCTAssertEqual(calendar.component(.day, from: normalized), 21)
    }

    func testTomorrowDoesNotAlsoShowThisWeekend() throws {
        let saturday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 12))
        )
        let sunday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 23, minute: 59))
        )

        let labels = DeadlineDateOptions.relativeLabels(
            for: sunday,
            relativeTo: saturday,
            calendar: calendar
        )

        XCTAssertEqual(labels, [L10n.text("明天", english: "Tomorrow")])
    }
}
