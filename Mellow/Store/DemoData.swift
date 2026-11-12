import Foundation
import PivchikDomain

/// Примеры записей только для снимков экранов (аргумент запуска -seedDemo). На диск не пишутся.
enum DemoData {
    static func fill(_ s: inout Snapshot, now: Date) {
        let zone = TimeZone.current.identifier
        let cal = Cal.current
        let startOfToday = cal.startOfDay(for: now)
        let elapsedToday = max(60, now.timeIntervalSince(startOfToday))

        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            let base = cal.date(byAdding: .day, value: dayOffset, to: startOfToday) ?? startOfToday
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        /// Момент сегодня, который точно уже прошёл.
        func today(_ fraction: Double) -> Date { startOfToday.addingTimeInterval(elapsedToday * fraction) }
        func meta(_ date: Date) -> RecordMeta { RecordMeta(createdAt: date) }

        // Встроенные практики.
        var practiceID: [PracticeType: UUID] = [:]
        for type in PracticeType.allCases {
            let info = type.info
            var settings = PracticeSettings()
            settings.pattern = type.defaultPattern
            let rec = PracticeDefinitionRecord(meta: meta(at(-40, 9, 0)), type: type, title: info.title, settings: settings,
                                               isFavorite: type == .breathing46, isBuiltIn: true, sortOrder: info.sortOrder)
            practiceID[type] = rec.meta.id
            s.practices.append(rec)
        }
        s.settings.append(SettingsRecord(meta: meta(at(-40, 9, 0)), theme: AppStore.eveningTheme))

        // Истории.
        let h1 = HistoryRecord(meta: meta(at(-42, 10, 0)), title: "Тревога, когда нет связи",
                               details: "Долго нет ответа — и хочется проверять телефон.", startedAt: at(-42, 10, 0), status: .easier)
        let h2 = HistoryRecord(meta: meta(at(-23, 10, 0)), title: "Волнение перед встречами", startedAt: at(-23, 10, 0), status: .active)
        s.histories = [h1, h2]
        s.statusChanges.append(StatusChangeRecord(meta: meta(at(-2, 12, 0)), historyID: h1.meta.id, fromStatus: .active, toStatus: .easier, changedAt: at(-2, 12, 0)))

        func checkIn(_ date: Date, _ value: Int, _ note: String? = nil) {
            s.checkIns.append(CheckInRecord(meta: meta(date), observedAt: date, zoneID: zone, anxiety: value, note: note))
        }
        func episode(_ date: Date, _ minutes: Double, _ peak: Int, _ cause: String, _ symptoms: [String], _ history: UUID?, _ tags: [String] = []) {
            s.episodes.append(EpisodeRecord(meta: meta(date), startedAt: date, endedAt: date.addingTimeInterval(minutes * 60), zoneID: zone,
                                            peak: peak, cause: cause, bodySymptoms: symptoms, tags: tags,
                                            historyIDs: history.map { [$0] } ?? []))
        }
        func session(_ type: PracticeType, _ date: Date, _ minutes: Double, _ before: Int?, _ after: Int?, _ felt: FeltResult?,
                     history: UUID? = nil, conversation: UUID? = nil) {
            guard let pid = practiceID[type] else { return }
            s.sessions.append(PracticeSessionRecord(meta: meta(date), practiceID: pid, practiceType: type, startedAt: date,
                                                    endedAt: date.addingTimeInterval(minutes * 60), zoneID: zone,
                                                    plannedDuration: type.isTimed ? minutes * 60 : nil, activeDuration: minutes * 60,
                                                    status: .completed, before: before, after: after, feltResult: felt,
                                                    historyIDs: history.map { [$0] } ?? [], conversationID: conversation))
        }

        // Прошлые недели: тревожнее, чем текущая.
        let older: [(Int, [Int])] = [(-27, [7, 8]), (-26, [6]), (-24, [8, 7, 6]), (-22, [5, 6]), (-21, [7]), (-19, [8, 6]), (-18, [6, 5]),
                                     (-16, [7, 7]), (-15, [5]), (-13, [8, 7]), (-12, [6, 6, 5]), (-11, [7]), (-10, [5, 6]), (-9, [6]), (-8, [7, 5]), (-7, [6, 6])]
        for (offset, values) in older {
            for (i, v) in values.enumerated() { checkIn(at(offset, 10 + i * 4, 15), v) }
        }
        episode(at(-24, 20, 30), 40, 8, "Нет ответа", ["сердцебиение", "ком в горле"], h1.meta.id, ["связь", "вечер"])
        episode(at(-19, 21, 10), 35, 8, "Нет ответа", ["сердцебиение", "напряжение"], h1.meta.id, ["связь"])
        episode(at(-16, 9, 30), 25, 7, "Встреча впереди", ["напряжение"], h2.meta.id, ["работа"])
        episode(at(-13, 22, 0), 30, 8, "Нет ответа", ["сердцебиение"], h1.meta.id, ["связь", "вечер"])
        episode(at(-11, 19, 0), 20, 7, "Неясные планы", ["ком в горле"], nil)
        episode(at(-8, 10, 0), 20, 7, "Встреча впереди", ["напряжение", "дрожь"], h2.meta.id, ["работа"])

        // Последние семь дней, как в макете: 6 дней назад … сегодня.
        checkIn(at(-6, 18, 0), 7)
        episode(at(-6, 11, 0), 45, 9, "Нет ответа", ["сердцебиение", "ком в горле", "трудно дышать"], h1.meta.id, ["связь"])
        episode(at(-6, 21, 0), 30, 8, "Неясные планы", ["напряжение"], nil, ["вечер"])
        checkIn(at(-5, 10, 0), 6); checkIn(at(-5, 15, 0), 5); checkIn(at(-5, 21, 0), 5)
        episode(at(-5, 12, 0), 25, 6, "Нет ответа", ["сердцебиение"], h1.meta.id, ["связь"])
        // 4 дня назад — без записей: пробел, а не спокойный день.
        checkIn(at(-3, 9, 0), 4); checkIn(at(-3, 19, 0), 4)
        episode(at(-3, 13, 0), 20, 5, "Встреча впереди", ["напряжение"], h2.meta.id, ["работа"])
        checkIn(at(-2, 10, 0), 3); checkIn(at(-2, 20, 0), 3)
        checkIn(at(-1, 9, 30), 3); checkIn(at(-1, 14, 0), 2); checkIn(at(-1, 21, 0), 3)

        checkIn(today(0.35), 3, "Спокойное утро, кофе")
        let epToday = today(0.72)
        episode(epToday, 24, 7, "Нет ответа", ["сердцебиение", "ком в горле"], h1.meta.id, ["связь", "вечер"])
        s.episodes[s.episodes.count - 1].thoughts = "Долго нет ответа, тянет проверить телефон"
        let talk = ConversationRecord(meta: meta(today(0.8)), occurredAt: today(0.8), zoneID: zone, before: 7, after: 2,
                                      summary: "Разобрали, что молчание — не про меня", insights: "Молчание — не про меня. Могу подождать час.",
                                      historyIDs: [h1.meta.id])
        s.conversations.append(talk)
        session(.canNotKnow, today(0.88), 6, 7, 2, .easier, history: h1.meta.id, conversation: talk.meta.id)

        // Разговоры и практики раньше.
        s.conversations.append(ConversationRecord(meta: meta(at(-9, 20, 0)), occurredAt: at(-9, 20, 0), zoneID: zone, before: 8, after: 5,
                                                  summary: "Составили план: что делаю, пока жду.", historyIDs: [h1.meta.id]))
        s.conversations.append(ConversationRecord(meta: meta(at(-3, 14, 0)), occurredAt: at(-3, 14, 0), zoneID: zone, before: 6, after: 4,
                                                  summary: "Страшно не встреча, а пауза перед ней.", insights: "Страшно не встреча, а пауза перед ней.",
                                                  historyIDs: [h2.meta.id]))
        let breathing: [(Int, Int, Int)] = [(-26, 7, 4), (-22, 6, 3), (-19, 8, 5), (-16, 7, 4), (-13, 7, 5), (-10, 6, 3), (-8, 6, 6), (-5, 5, 3)]
        for (offset, b, a) in breathing {
            session(.breathing46, at(offset, 22, 40), 5, b, a, a < b ? .easier : .same, history: h1.meta.id)
        }
        session(.breathing46, at(-1, 22, 40), 5, 5, 3, .easier)
        session(.canNotKnow, at(-12, 21, 0), 5, 7, 3, .easier, history: h1.meta.id)
        session(.canNotKnow, at(-6, 12, 0), 5, 9, 5, .easier, history: h1.meta.id)
        session(.boxBreathing, at(-2, 8, 15), 3, nil, nil, .same)
        session(.breathing46, at(-3, 12, 30), 3, 5, 4, .easier, history: h2.meta.id)

        // Открытия, цели, победы, достижения, письма.
        s.insights.append(InsightRecord(meta: meta(at(-9, 20, 30)), text: "Я могу не знать и всё равно заниматься своим днём.", isFavorite: true, historyIDs: [h1.meta.id]))
        s.insights.append(InsightRecord(meta: meta(at(-5, 13, 0)), text: "Проверка телефона успокаивает на минуту, а потом тревога растёт.", historyIDs: [h1.meta.id]))
        s.insights.append(InsightRecord(meta: meta(at(-3, 14, 30)), text: "За час до встречи помогает дыхание 4–6.", historyIDs: [h2.meta.id]))

        let g1 = GoalRecord(meta: meta(at(-20, 10, 0)), title: "Реже проверять телефон", historyID: h1.meta.id)
        let g2 = GoalRecord(meta: meta(at(-10, 10, 0)), title: "Приходить без «репетиций» в голове", historyID: h2.meta.id)
        s.goals = [g1, g2]
        s.goalSteps.append(GoalStepRecord(meta: meta(at(-20, 10, 1)), goalID: g1.meta.id, title: "Час без проверки", isDone: true, doneAt: at(-14, 20, 0), order: 0))
        s.goalSteps.append(GoalStepRecord(meta: meta(at(-20, 10, 2)), goalID: g1.meta.id, title: "Вечер без проверки", isDone: true, doneAt: at(-4, 22, 0), order: 1))
        s.goalSteps.append(GoalStepRecord(meta: meta(at(-20, 10, 3)), goalID: g1.meta.id, title: "Не проверять после 22:00", order: 2))
        s.goalSteps.append(GoalStepRecord(meta: meta(at(-10, 10, 1)), goalID: g2.meta.id, title: "Одна встреча без подготовки", order: 0))

        s.smallWins.append(SmallWinRecord(meta: meta(at(-2, 22, 0)), text: "Спокойно уснула", occurredAt: at(-2, 22, 0), zoneID: zone))
        s.smallWins.append(SmallWinRecord(meta: meta(at(-1, 22, 50)), text: "Сделала дыхательную практику", occurredAt: at(-1, 22, 50), zoneID: zone))
        s.smallWins.append(SmallWinRecord(meta: meta(today(0.9)), text: "Справилась с тревогой без проверки", occurredAt: today(0.9), zoneID: zone, historyIDs: [h1.meta.id]))
        s.smallWins.append(SmallWinRecord(meta: meta(at(-4, 21, 0)), text: "Вернулась к книге", occurredAt: at(-4, 21, 0), zoneID: zone, historyIDs: [h1.meta.id]))

        s.achievements.append(AchievementRecord(meta: meta(at(-4, 21, 0)), type: .returnedToActivity, earnedAt: at(-4, 21, 0), sourceID: nil))

        let unlock = cal.date(byAdding: .day, value: 50, to: startOfToday) ?? now
        s.letters.append(FutureLetterRecord(meta: meta(now), body: "Привет. Как ты сейчас?", unlockAt: unlock))
        s.letters.append(FutureLetterRecord(meta: meta(at(-41, 12, 0)),
                                            body: "Привет. Если ты это читаешь, значит месяц позади, и ты справилась. Посмотри, сколько раз ты выбрала подышать, а не проверять.",
                                            unlockAt: at(-11, 9, 0), openedAt: at(-11, 10, 0)))
    }
}
