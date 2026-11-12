import SwiftUI
import PivchikDomain

/// Письма себе в будущее.
struct LettersView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: SheetRoute?

    private var letters: [FutureLetterRecord] {
        store.active.letters.filter { $0.canceledAt == nil }.sorted { $0.unlockAt > $1.unlockAt }
    }

    var body: some View {
        TabScroll(bottom: 30) {
            HStack {
                RoundButton(icon: "chevron.left", label: "Назад") { dismiss() }
                Spacer()
                RoundButton(icon: "plus", label: "Новое письмо") { sheet = .newLetter }
            }
            BigHeader(title: "Письма", subtitle: "себе в будущее")
            CatImage(name: "PivRead", width: 150).frame(maxWidth: .infinity)
            if letters.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Cap("Писем пока нет. Напиши себе несколько слов — письмо откроется в день, который ты выберешь.")
                    CTAButton(title: "Написать письмо", icon: "plus", small: true) { sheet = .newLetter }
                }
                .card()
            }
            ForEach(letters, id: \.meta.id) { letter in
                row(letter)
            }
        }
        .modifier(SheetHost(sheet: $sheet))
    }

    @ViewBuilder
    private func row(_ letter: FutureLetterRecord) -> some View {
        let now = Date()
        if let opened = letter.openedAt {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Lab("Открыто \(Fmt.dayMonth.string(from: opened))")
                    Spacer()
                    Image(systemName: "envelope.open").font(.system(size: 16, weight: .medium))
                }
                Text("«\(letter.body)»").txt(14.5).fixedSize(horizontal: false, vertical: true)
            }
            .card()
        } else if letter.isUnlocked(at: now) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Lab("Письмо можно открыть")
                    Spacer()
                    Image(systemName: "envelope").font(.system(size: 16, weight: .medium))
                }
                Cap("Написано \(Fmt.dayMonth.string(from: letter.meta.createdAt)).")
                CTAButton(title: "Открыть письмо", small: true) {
                    store.update(\Snapshot.letters, id: letter.meta.id) { $0.openedAt = Date() }
                    Haptics.success(store.settings.hapticsEnabled)
                }
            }
            .card()
        } else {
            let days = max(1, Int((letter.unlockAt.timeIntervalSince(now) / 86400).rounded(.up)))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Lab("Откроется \(Fmt.dayMonthYear.string(from: letter.unlockAt))")
                    Spacer()
                    Image(systemName: "lock").font(.system(size: 16, weight: .medium))
                }
                Cap("Написано \(Fmt.dayMonth.string(from: letter.meta.createdAt)). До открытия \(Fmt.count(days, "день", "дня", "дней")).")
                Chip(text: "отменить письмо", height: 30) {
                    Notifier.cancelLetter(id: letter.meta.id)
                    store.update(\Snapshot.letters, id: letter.meta.id) { $0.canceledAt = Date() }
                }
            }
            .card()
        }
    }
}

/// Новое письмо: текст и дата открытия. Напоминание приходит без текста письма.
struct NewLetterSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var unlock = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var remind = true

    private var minDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private var maxDate: Date {
        Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
    }

    var body: some View {
        SheetScroll {
            BigHeader(title: "Письмо", subtitle: "себе в будущее", size: 30)
            MField(title: "Текст письма", text: $text, placeholder: "Привет. Когда ты это прочитаешь…", lines: 5)
            DateRow(title: "Когда открыть", date: $unlock, range: minDate...maxDate, components: [.date])
            Toggle(isOn: $remind) { Text("Напомнить в этот день").txt(14.5) }
                .tint(Theme.mint)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .glass(18)
            Cap("В уведомлении текста письма не будет.")
            CTAButton(title: "Запечатать письмо", icon: "lock") {
                guard let body = text.nilIfEmpty else { return }
                let day = Calendar.current.startOfDay(for: unlock)
                let at = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
                let id = store.addLetter(body: body, unlockAt: at)
                if remind && !store.isDemo {
                    Notifier.requestPermission { granted in
                        if granted { Notifier.scheduleLetter(id: id, at: at) }
                    }
                }
                dismiss()
            }
            .opacity(text.trimmed.isEmpty ? 0.5 : 1)
        }
    }
}
