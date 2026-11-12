import Foundation
@testable import PivchikDomain

let tbilisi = "Asia/Tbilisi"   // UTC+4, без перехода на летнее время

/// Дата по местному времени указанного пояса.
func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0, zone: String = tbilisi) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: zone)!
    return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

func meta(_ created: Date = at(2026, 11, 12), updated: Date? = nil, deleted: Date? = nil, test: Bool = false, id: UUID = UUID()) -> RecordMeta {
    RecordMeta(id: id, createdAt: created, updatedAt: updated, deletedAt: deleted, isTestData: test)
}

func checkIn(_ value: Int, _ date: Date, zone: String = tbilisi, tags: [String] = [], histories: [UUID] = [],
             part: DayPart? = nil, deleted: Bool = false) -> CheckInRecord {
    CheckInRecord(meta: meta(date, deleted: deleted ? date : nil), observedAt: date, zoneID: zone, dayPart: part,
                  anxiety: value, tags: tags, historyIDs: histories)
}

func session(practice: UUID = UUID(), type: PracticeType = .breathing46, _ date: Date = at(2026, 11, 12), before: Int? = nil,
             after: Int? = nil, duration: TimeInterval? = nil, status: SessionStatus = .completed,
             conversation: UUID? = nil, felt: FeltResult? = nil) -> PracticeSessionRecord {
    PracticeSessionRecord(meta: meta(date), practiceID: practice, practiceType: type, startedAt: date,
                          endedAt: date.addingTimeInterval(duration ?? 0), zoneID: tbilisi, activeDuration: duration,
                          status: status, before: before, after: after, feltResult: felt, conversationID: conversation)
}
