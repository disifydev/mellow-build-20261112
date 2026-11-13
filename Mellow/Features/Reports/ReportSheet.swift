import SwiftUI
import PDFKit
import PivchikDomain

/// Выбор периода: готовый или свой, с двумя датами.
struct PeriodPicker: View {
    @EnvironmentObject private var store: AppStore
    @Binding var period: ReportPeriod
    @Binding var from: Date
    @Binding var to: Date
    var periods: [ReportPeriod] = ReportPeriod.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegControl(items: periods.map { ($0, $0.title) }, selection: $period)
            if period == .custom {
                DateRow(title: "С", date: $from, range: Date.distantPast...to, components: [.date])
                DateRow(title: "По", date: $to, range: from...Date(), components: [.date])
            }
        }
    }

    /// Итоговый интервал дней.
    static func range(store: AppStore, period: ReportPeriod, from: Date, to: Date) -> (from: LocalDay, to: LocalDay) {
        if period == .custom {
            let a = LocalDay(date: from, zoneID: store.zone)
            let b = LocalDay(date: to, zoneID: store.zone)
            return a <= b ? (a, b) : (b, a)
        }
        return period.range(today: store.today)
    }
}

/// Отчёт для психолога в PDF.
struct ReportSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal

    @State private var period: ReportPeriod = .month
    @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var sections = ReportSections()
    @State private var questions = ""
    @State private var preview: PreviewFile?
    @State private var error: String?
    @State private var autoOpened = false

    struct PreviewFile: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    var body: some View {
        SheetScroll {
            BigHeader(title: "Отчёт", subtitle: "для психолога", size: 30)
            PeriodPicker(period: $period, from: $from, to: $to)
            FieldGroup(title: "Что включить") {
                FlowLayout {
                    toggle("сводка", \.summary)
                    toggle("график", \.chart)
                    toggle("причины и ощущения", \.causes)
                    toggle("эпизоды", \.episodes)
                    toggle("истории", \.stories)
                    toggle("практики", \.practices)
                    toggle("выводы", \.insights)
                    toggle("вопросы для обсуждения", \.questions)
                    toggle("полный текст разговоров", \.fullConversations)
                }
            }
            if sections.questions {
                MField(title: "Вопросы для обсуждения", text: $questions, placeholder: "Что хочется обсудить на встрече", lines: 3)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 17, weight: .medium))
                Text(sections.fullConversations
                     ? "В отчёте личные записи и полные тексты разговоров. Перед отправкой посмотри предпросмотр."
                     : "В отчёте личные записи. Перед отправкой посмотри предпросмотр.")
                    .txt(13).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .card()
            CTAButton(title: "Предпросмотр PDF", icon: "doc.richtext", action: build)
            if let error { Cap(error) }
            Cap("Только цифры и твои записи — без выводов за тебя. Файл не уходит никуда сам: отправляешь только ты.")
        }
        .sheet(item: $preview, onDismiss: { AppStore.removeExportFiles() }) { file in
            Themed {
                PDFPreviewSheet(url: file.url)
            }
            .environmentObject(store)
        }
        .onDisappear { AppStore.removeExportFiles() }
        .onAppear {
            guard Launch.step == "preview", !autoOpened else { return }
            autoOpened = true
            questions = "Как замечать начало тревоги раньше?"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { build() }
        }
    }

    private func toggle(_ title: String, _ key: WritableKeyPath<ReportSections, Bool>) -> some View {
        Chip(text: title, isOn: sections[keyPath: key]) { sections[keyPath: key].toggle() }
    }

    private func build() {
        error = nil
        let r = PeriodPicker.range(store: store, period: period, from: from, to: to)
        let data = ReportData.build(store: store, from: r.from, to: r.to)
        do {
            let url = try PDFReport.write(data: data, sections: sections, questions: questions, thresholds: store.thresholds)
            preview = PreviewFile(url: url)
        } catch {
            self.error = "Не удалось собрать PDF."
        }
    }
}

/// Предпросмотр PDF и отправка через системное меню.
struct PDFPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                RoundButton(icon: "xmark", label: "Закрыть") { dismiss() }
                Spacer()
                Text("Предпросмотр").display(18)
                Spacer()
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .glass(22)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Отправить PDF")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            PDFKitView(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor.clear
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
