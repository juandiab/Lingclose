import Foundation
import Testing
@testable import LingoScan

struct ArchiveSchedulePolicyTests {
    static let now = Date(timeIntervalSince1970: 1_793_200_000)
    static let day: TimeInterval = 24 * 3600

    @Test func withoutPreviousExportItIsFifteenMinutesFromNow() {
        let date = ArchiveSchedulePolicy.earliestBeginDate(now: Self.now, lastExport: nil, interval: Self.day)
        #expect(date == Self.now.addingTimeInterval(15 * 60))
    }

    @Test func overdueExportIsFifteenMinutesFromNow() {
        let last = Self.now.addingTimeInterval(-30 * 3600)
        let date = ArchiveSchedulePolicy.earliestBeginDate(now: Self.now, lastExport: last, interval: Self.day)
        #expect(date == Self.now.addingTimeInterval(15 * 60))
    }

    @Test func recentExportIsLastExportPlusInterval() {
        let last = Self.now.addingTimeInterval(-2 * 3600)
        let date = ArchiveSchedulePolicy.earliestBeginDate(now: Self.now, lastExport: last, interval: Self.day)
        #expect(date == last.addingTimeInterval(Self.day))
    }

    @Test(arguments: [nil, -1_000_000, -86_400, -86_000, -3_600, 0, 3_600] as [TimeInterval?])
    func neverInThePast(offset: TimeInterval?) {
        let last = offset.map { Self.now.addingTimeInterval($0) }
        let date = ArchiveSchedulePolicy.earliestBeginDate(now: Self.now, lastExport: last, interval: Self.day)
        #expect(date >= Self.now.addingTimeInterval(ArchiveSchedulePolicy.minimumLead))
    }

    @Test func doesNotResubmitWhenAPendingRequestIsEarlierOrEqual() {
        let desired = Self.now.addingTimeInterval(3600)
        #expect(ArchiveSchedulePolicy.shouldSubmit(desired: desired, pending: .none))
        #expect(!ArchiveSchedulePolicy.shouldSubmit(desired: desired, pending: .some(desired)))
        #expect(!ArchiveSchedulePolicy.shouldSubmit(desired: desired, pending: .some(Self.now)))
        #expect(!ArchiveSchedulePolicy.shouldSubmit(desired: desired, pending: .some(.none)))
        #expect(ArchiveSchedulePolicy.shouldSubmit(desired: desired, pending: .some(desired.addingTimeInterval(1))))
    }
}
