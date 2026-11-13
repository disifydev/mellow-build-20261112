import SwiftUI
import UniformTypeIdentifiers
import AuthenticationServices
import PivchikDomain

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    @Environment(\.dismiss) private var dismiss

    @State private var sheet: SheetRoute?
    @State private var cover: CoverRoute?
    @State private var askDelete = false
    @State private var reminderOn = UserDefaults.standard.bool(forKey: Notifier.enabledKey)
    @State private var reminderTime = ProfileView.storedTime()
    @State private var notice: String?

    var body: some View {
        TabScroll(bottom: 30) {
            HStack {
                RoundButton(icon: "chevron.left", label: "Назад") { dismiss() }
                Spacer()
            }
            BigHeader(title: "Профиль", subtitle: "и настройки", size: 31)
            accountGroup
            remindersGroup
            thresholdsGroup.id("thresholds")
            linksGroup
            dataGroup.id("data")
            Button { cover = .help } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 18, weight: .medium))
                    VStack(alignment: .leading, spacing: 3) {
                        Lab("Если нужна срочная помощь")
                        Cap("Куда обратиться прямо сейчас")
                    }
                    Spacer(minLength: 0)
                }
                .card()
            }
            .buttonStyle(PressStyle())
            Cap("Данные хранятся только на этом устройстве. Своего сервера нет.")
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .modifier(SheetHost(sheet: $sheet))
        .modifier(CoverHost(cover: $cover))
        .confirmationDialog("Удалить все данные?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Сначала сохранить копию") { sheet = .backup }
            Button("Удалить всё", role: .destructive) {
                Notifier.cancelAll()
                reminderOn = false
                UserDefaults.standard.set(false, forKey: Notifier.enabledKey)
                store.wipe()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все записи, истории, практики и письма будут стёрты с этого устройства. Вернуть их можно только из резервной копии.")
        }
    }

    // MARK: Группы

    private var remindersGroup: some View {
        VStack(spacing: 0) {
            toggleRow("bell", "Вечерний итог: напоминание", Binding(get: { reminderOn }, set: { setReminder($0) }))
            if reminderOn {
                rowDivider
                HStack(spacing: 12) {
                    Image(systemName: "clock").font(.system(size: 17, weight: .medium)).frame(width: 22)
                    Text("Время напоминания").txt(14.5)
                    Spacer(minLength: 4)
                    DatePicker("Время напоминания", selection: Binding(get: { reminderTime }, set: { setTime($0) }), displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .environment(\.locale, Fmt.ru)
                }
                .padding(.vertical, 6)
            }
            if let notice {
                Cap(notice).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            }
            rowDivider
            toggleRow("speaker.wave.2", "Звук в практиках", Binding(get: { store.settings.soundEnabled }, set: { v in store.updateSettings { $0.soundEnabled = v } }))
            rowDivider
            toggleRow("iphone.radiowaves.left.and.right", "Вибрация", Binding(get: { store.settings.hapticsEnabled }, set: { v in store.updateSettings { $0.hapticsEnabled = v } }))
            rowDivider
            toggleRow("moon", "Тёмная тема вечером", Binding(get: { store.darkEvening }, set: { v in store.updateSettings { $0.theme = v ? AppStore.eveningTheme : "light" } }))
        }
        .card(16)
    }

    /// Необязательный вход через Apple.
    @ViewBuilder
    private var accountGroup: some View {
        if store.appleUserID != nil {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 20, weight: .medium)).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.appleName.map { "Вход через Apple: \($0)" } ?? "Вход через Apple выполнен").txt(14.5)
                    Cap("Записи хранятся на устройстве и к аккаунту не привязаны.")
                }
                Spacer(minLength: 4)
                Chip(text: "Выйти", height: 32) { store.signOutApple() }
            }
            .card(16)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                            store.signedInWithApple(credential)
                            notice = nil
                        }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            notice = "Не получилось войти через Apple. Можно попробовать позже — приложение работает и без входа."
                        }
                    }
                }
                .signInWithAppleButtonStyle(pal.isDark ? .white : .black)
                .frame(height: 50)
                .clipShape(Capsule())
                .accessibilityLabel("Войти через Apple")
                Cap("Необязательно. Нужно только чтобы приложение обращалось к тебе по имени. Записи остаются на устройстве.")
            }
            .card(16)
        }
    }

    private var thresholdsGroup: some View {
        let t = store.thresholds
        return VStack(alignment: .leading, spacing: 4) {
            Stepper(value: Binding(get: { t.calm }, set: { setThresholds(calm: $0, anxious: t.anxious) }), in: 0...9) {
                Text("Спокойный день: средняя до \(t.calm)").txt(14.5)
            }
            .padding(.vertical, 6)
            rowDivider
            Stepper(value: Binding(get: { t.anxious }, set: { setThresholds(calm: t.calm, anxious: $0) }), in: 1...10) {
                Text("Тревожный день: пик от \(t.anxious)").txt(14.5)
            }
            .padding(.vertical, 6)
            Cap("Порог спокойного дня всегда ниже порога тревожного.")
        }
        .card(16)
    }

    private var linksGroup: some View {
        VStack(spacing: 0) {
            linkRow("flag", "Цели") { sheet = .goals }
            rowDivider
            linkRow("envelope", "Письма себе") { cover = .letters }
            rowDivider
            linkRow("doc.text", "Как я изменилась за месяц") { cover = .month }
        }
        .card(16)
    }

    private var dataGroup: some View {
        VStack(spacing: 0) {
            linkRow("doc.richtext", "Отчёт для психолога (PDF)") { sheet = .report }
            rowDivider
            linkRow("bubble.left.and.text.bubble.right", "Сводка для ChatGPT") { sheet = .summary }
            rowDivider
            linkRow("doc", "Резервная копия и импорт") { sheet = .backup }
            rowDivider
            linkRow("trash", "Удалить все данные") { askDelete = true }
        }
        .card(16)
    }

    private var rowDivider: some View {
        Rectangle().fill(pal.edge).frame(height: 1)
    }

    private func toggleRow(_ icon: String, _ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).frame(width: 22)
                Text(title).txt(14.5)
            }
        }
        .tint(Theme.mint)
        .padding(.vertical, 8)
    }

    private func linkRow(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).frame(width: 22)
                Text(title).txt(14.5)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).opacity(0.5)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Действия

    private static func storedTime() -> Date {
        let d = UserDefaults.standard
        let hour = d.object(forKey: Notifier.hourKey) as? Int ?? 21
        let minute = d.object(forKey: Notifier.minuteKey) as? Int ?? 30
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func setThresholds(calm: Int, anxious: Int) {
        // Порог спокойного дня всегда строго меньше порога тревожного — проверяет ядро.
        guard DayThresholds(calm: calm, anxious: anxious).isValid else { return }
        store.updateSettings {
            $0.calmThreshold = calm
            $0.anxiousThreshold = anxious
        }
    }

    private func setReminder(_ on: Bool) {
        notice = nil
        if !on {
            reminderOn = false
            UserDefaults.standard.set(false, forKey: Notifier.enabledKey)
            Notifier.cancelEvening()
            return
        }
        Notifier.requestPermission { granted in
            if granted {
                reminderOn = true
                UserDefaults.standard.set(true, forKey: Notifier.enabledKey)
                schedule()
            } else {
                reminderOn = false
                notice = "Уведомления выключены. Их можно разрешить в настройках телефона."
            }
        }
    }

    private func setTime(_ date: Date) {
        reminderTime = date
        schedule()
    }

    private func schedule() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let hour = c.hour ?? 21
        let minute = c.minute ?? 30
        UserDefaults.standard.set(hour, forKey: Notifier.hourKey)
        UserDefaults.standard.set(minute, forKey: Notifier.minuteKey)
        Notifier.scheduleEvening(hour: hour, minute: minute)
    }
}

/// Экран «Если нужна срочная помощь».
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabScroll(bottom: 30) {
            HStack {
                RoundButton(icon: "chevron.left", label: "Назад") { dismiss() }
                Spacer()
            }
            BigHeader(title: "Срочная помощь", subtitle: "ты не одна", size: 31)
            Emblem(name: "PivLove", width: 150).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                Text("Mellow — дневник и инструменты самопомощи. Он не заменяет врача или психолога и не ставит диагнозов.")
                    .txt(15).fixedSize(horizontal: false, vertical: true)
                Sep()
                Text("Если тебе очень плохо или есть угроза жизни — обратись в местную экстренную службу или к близкому человеку прямо сейчас.")
                    .txt(15, .semibold).fixedSize(horizontal: false, vertical: true)
                Sep()
                Text("Единый номер экстренных служб во многих странах — 112. Позвонить можно даже без сим-карты.")
                    .txt(15).fixedSize(horizontal: false, vertical: true)
            }
            .card()
            Cap("Когда станет чуть легче, можно вернуться сюда и сделать один медленный выдох.")
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// Резервная копия: экспорт в JSON и импорт с предпросмотром.
struct BackupSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal
    @State private var fileURL: URL?
    @State private var importing = false
    @State private var preview: ImportPreview?
    @State private var message: String?

    struct ImportPreview {
        let merged: Snapshot
        let summary: ImportSummary
    }

    var body: some View {
        SheetScroll {
            BigHeader(title: "Резервная копия", subtitle: "все записи одним файлом", size: 30)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 17, weight: .medium))
                Text("В файле личные записи. Отправляй его только туда, куда хочешь сама.")
                    .txt(13).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .card()
            if let fileURL {
                ShareLink(item: fileURL) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .bold))
                        Text("Сохранить копию JSON").display(18)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .glass(30, strong: true)
                }
                .buttonStyle(PressStyle())
            } else {
                Cap("Не удалось подготовить файл копии.")
            }
            CTAButton(title: "Импорт из файла", icon: "square.and.arrow.down", small: true) { importing = true }
            if let preview {
                VStack(alignment: .leading, spacing: 8) {
                    H("Что изменится")
                    Cap("Добавится записей: \(preview.summary.added)")
                    Cap("Обновится: \(preview.summary.updated)")
                    Cap("Без изменений: \(preview.summary.unchanged)")
                    CTAButton(title: "Применить импорт", small: true) {
                        store.applyImport(preview.merged)
                        self.preview = nil
                        message = "Импорт выполнен. Повторный импорт того же файла ничего не меняет."
                    }
                    .padding(.top, 4)
                }
                .card()
            }
            if let message { Cap(message) }
            Cap("Повторный импорт не создаёт дублей: записи сопоставляются по идентификатору, остаётся более свежая версия.")
        }
        .onAppear(perform: prepare)
        .onDisappear {
            AppStore.removeExportFiles()
            fileURL = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.json]) { result in
            handle(result)
        }
    }

    private func prepare() {
        do {
            let data = try store.backupData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mellow-backup-\(Fmt.fileDate.string(from: Date())).json")
            // Файл копии шифруется системой, пока телефон заблокирован, и удаляется при закрытии листа.
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            fileURL = url
        } catch {
            fileURL = nil
        }
    }

    private func handle(_ result: Result<URL, Error>) {
        message = nil
        preview = nil
        guard case .success(let url) = result else {
            message = "Файл не выбран."
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let r = try store.previewImport(data)
            preview = ImportPreview(merged: r.merged, summary: r.summary)
        } catch let e as BackupError {
            switch e {
            case .notABackup: message = "Это не резервная копия Mellow или файл повреждён."
            case .newerSchema: message = "Копия сделана более новой версией приложения. Обнови Mellow и попробуй снова."
            }
        } catch {
            message = "Не удалось прочитать файл."
        }
    }
}
