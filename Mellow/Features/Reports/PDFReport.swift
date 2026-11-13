import SwiftUI
import UIKit
import PivchikDomain

/// Какие разделы включить в PDF.
struct ReportSections: Equatable {
    var summary = true
    var chart = true
    var causes = true
    var episodes = true
    var stories = true
    var practices = true
    var insights = true
    var questions = true
    var fullConversations = false
}

/// PDF для психолога: A4, текст Involve, заголовки — шрифт приложения. Только записи и расчёты, без выводов.
@MainActor
enum PDFReport {
    static let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    static let margin: CGFloat = 48

    static func write(data: ReportData, sections: ReportSections, questions: String, thresholds: DayThresholds) throws -> URL {
        let chart = sections.chart ? chartImage(data.points) : nil
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format())
        let pdf = renderer.pdfData { ctx in
            let w = Writer(ctx: ctx)
            w.begin()
            w.title("Mellow — мои записи")
            w.caption("Период: \(data.periodTitle). Составлено \(Fmt.dayMonthYear.string(from: Date())).")
            w.caption("Шкала тревоги 0–10. Спокойный день — средняя до \(thresholds.calm), тревожный — оценка от \(thresholds.anxious). Дни без записей не считаются.")
            w.space(10)

            if sections.summary {
                w.heading("Сводка")
                for line in ReportText.summaryLines(data) { w.body(line) }
            }
            if let chart {
                w.heading("Тревога по \(data.points.count > 10 ? "неделям" : "дням")")
                w.image(chart)
                w.caption("Размер и высота бусины — средняя оценка. Пустой кружок — дней без записей.")
            }
            if sections.causes {
                w.heading("Причины и ощущения")
                if data.causes.isEmpty && data.symptoms.isEmpty { w.body("В эпизодах за период причины и ощущения не указаны.") }
                if !data.causes.isEmpty {
                    w.label("Частые причины")
                    w.body(data.causes.prefix(8).map { "\($0.value) — \($0.count)" }.joined(separator: "; "))
                }
                if !data.symptoms.isEmpty {
                    w.label("Ощущения в теле")
                    w.body(data.symptoms.prefix(8).map { "\($0.value) — \($0.count)" }.joined(separator: "; "))
                }
            }
            if sections.episodes {
                w.heading("Эпизоды")
                if data.episodes.isEmpty { w.body("Эпизодов за период нет.") }
                for e in data.episodes {
                    w.label(ReportText.episodeLine(e))
                    if !e.stories.isEmpty { w.field("История", e.stories.joined(separator: ", ")) }
                    if let c = e.cause { w.field("Причина", c) }
                    if let t = e.thoughts { w.field("Мысли", t) }
                    if !e.symptoms.isEmpty { w.field("Ощущения", e.symptoms.joined(separator: ", ")) }
                    if let c = e.coping { w.field("Что сделала", c) }
                    if let i = e.insight { w.field("Что поняла", i) }
                    w.space(6)
                }
            }
            if sections.stories {
                w.heading("Истории")
                if data.stories.isEmpty { w.body("Историй за период нет.") }
                for s in data.stories {
                    w.body("\(s.title) — \(s.status). Эпизодов за период: \(s.episodesInPeriod), всего: \(s.episodesTotal).")
                }
            }
            if sections.practices {
                w.heading("Практики и разговоры")
                if data.practices.isEmpty { w.body("Практик за период нет.") }
                for p in data.practices { w.body(ReportText.practiceLine(p)) }
                let c = data.conversationStats
                if c.count > 0 {
                    var line = "Разговоры с ИИ: \(c.count)"
                    if let m = c.meanChange, c.pairedCount >= PracticeAnalytics.minimumSample { line += ", в среднем " + ReportText.change(m) }
                    w.body(line + ".")
                }
                w.caption("Изменение после практики не доказывает, что его вызвала только она.")
            }
            if sections.insights {
                w.heading("Мои выводы")
                if data.insights.isEmpty { w.body("Выводов за период нет.") }
                for x in data.insights { w.body("«\(x)»") }
            }
            if sections.questions, let q = questions.nilIfEmpty {
                w.heading("Что я хочу обсудить")
                w.body(q)
            }
            if sections.fullConversations {
                w.heading("Разговоры полностью")
                let withText = data.conversations.filter { $0.text != nil }
                if withText.isEmpty { w.body("Текстов разговоров за период нет.") }
                for c in withText {
                    var head = Fmt.dayMonth.string(from: c.date)
                    if let b = c.before, let a = c.after { head += " · \(b) → \(a)" }
                    w.label(head)
                    w.body(c.text ?? "")
                    w.space(6)
                }
            }
            w.finish()
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mellow-report-\(Fmt.fileDate.string(from: Date())).pdf")
        try pdf.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    private static func format() -> UIGraphicsPDFRendererFormat {
        let f = UIGraphicsPDFRendererFormat()
        f.documentInfo = [kCGPDFContextTitle as String: "Mellow — мои записи", kCGPDFContextCreator as String: "Mellow"]
        return f
    }

    /// График «бусины» той же вью, что в приложении, — картинкой.
    private static func chartImage(_ points: [BeadPoint]) -> UIImage? {
        guard points.contains(where: { $0.hasData }) else { return nil }
        let view = BeadsChart(points: points, series: .average, selected: .constant(nil))
            .environment(\.palette, Palette.make(level: 2, tod: .day))
            .padding(.horizontal, 8)
            .frame(width: 500, height: 166)
            .background(Color(hex: 0xF4EFFA))
        let r = ImageRenderer(content: view)
        r.scale = 3
        return r.uiImage
    }

    /// Простая вёрстка сверху вниз с переносом на новую страницу.
    private final class Writer {
        let ctx: UIGraphicsPDFRendererContext
        var y: CGFloat = 0
        var pageNumber = 0
        var width: CGFloat { PDFReport.page.width - PDFReport.margin * 2 }
        var bottom: CGFloat { PDFReport.page.height - PDFReport.margin - 24 }

        let ink = UIColor(red: 0.118, green: 0.082, blue: 0.188, alpha: 1)
        let mute = UIColor(red: 0.118, green: 0.082, blue: 0.188, alpha: 0.62)
        let accent = UIColor(red: 0.725, green: 0.639, blue: 0.906, alpha: 1)

        init(ctx: UIGraphicsPDFRendererContext) { self.ctx = ctx }

        private func font(_ name: String, _ size: CGFloat, bold: Bool = false) -> UIFont {
            UIFont(name: name, size: size) ?? (bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size))
        }

        func begin() { newPage() }

        func newPage() {
            if pageNumber > 0 { footer() }
            ctx.beginPage()
            pageNumber += 1
            y = PDFReport.margin
        }

        func finish() { footer() }

        private func footer() {
            let text = "Mellow · личные записи, составлено из данных пользователя · стр. \(pageNumber)"
            let attrs: [NSAttributedString.Key: Any] = [.font: font("Involve-Regular", 8.5), .foregroundColor: mute]
            NSString(string: text).draw(at: CGPoint(x: PDFReport.margin, y: PDFReport.page.height - PDFReport.margin + 6), withAttributes: attrs)
        }

        private func ensure(_ height: CGFloat) {
            if y + height > bottom { newPage() }
        }

        private func draw(_ text: String, font f: UIFont, color: UIColor, indent: CGFloat = 0, after: CGFloat) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: style]
            // Длинный текст режем на куски, чтобы каждый помещался на страницу.
            for chunk in Writer.chunks(text) {
                let s = NSAttributedString(string: chunk, attributes: attrs)
                let box = s.boundingRect(with: CGSize(width: width - indent, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                let h = ceil(box.height)
                ensure(h)
                s.draw(with: CGRect(x: PDFReport.margin + indent, y: y, width: width - indent, height: h),
                       options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += h
            }
            y += after
        }

        private static func chunks(_ text: String) -> [String] {
            var out: [String] = []
            for para in text.components(separatedBy: "\n") {
                var rest = Substring(para)
                while rest.count > 900 {
                    let cut = rest.index(rest.startIndex, offsetBy: 900)
                    let space = rest[..<cut].lastIndex(of: " ") ?? cut
                    out.append(String(rest[..<space]))
                    rest = rest[space...].drop(while: { $0 == " " })
                }
                out.append(String(rest))
            }
            return out
        }

        func title(_ text: String) {
            draw(text, font: font(Theme.headingFontName, 26, bold: true), color: ink, after: 6)
        }

        func heading(_ text: String) {
            ensure(60)
            y += 12
            let bar = UIBezierPath(roundedRect: CGRect(x: PDFReport.margin, y: y + 3, width: 4, height: 15), cornerRadius: 2)
            accent.setFill()
            bar.fill()
            draw(text, font: font(Theme.headingFontName, 15, bold: true), color: ink, indent: 12, after: 6)
        }

        func label(_ text: String) {
            ensure(36)
            draw(text, font: font("Involve-SemiBold", 11), color: ink, after: 3)
        }

        func body(_ text: String) {
            draw(text, font: font("Involve-Regular", 10.5), color: ink, after: 5)
        }

        func field(_ name: String, _ value: String) {
            draw("\(name): \(value)", font: font("Involve-Regular", 10.5), color: ink, indent: 10, after: 3)
        }

        func caption(_ text: String) {
            draw(text, font: font("Involve-Regular", 9), color: mute, after: 4)
        }

        func space(_ h: CGFloat) { y += h }

        func image(_ img: UIImage) {
            let ratio = img.size.height / max(1, img.size.width)
            let h = width * ratio
            ensure(h + 8)
            img.draw(in: CGRect(x: PDFReport.margin, y: y, width: width, height: h))
            y += h + 6
        }
    }
}
