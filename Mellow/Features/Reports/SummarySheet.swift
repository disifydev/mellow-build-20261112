import SwiftUI
import UIKit
import PivchikDomain

/// Сводка для ChatGPT: короткий структурированный текст. Ничего не отправляется автоматически —
/// текст можно поправить, скопировать или отправить самой.
struct SummarySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal

    @State private var period: ReportPeriod = .week
    @State private var from = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var excluded: Set<UUID> = []
    @State private var withInsights = true
    @State private var withPractices = true
    @State private var text = ""
    @State private var edited = false
    @State private var copied = false

    private var data: ReportData {
        let r = PeriodPicker.range(store: store, period: period, from: from, to: to)
        return ReportData.build(store: store, from: r.from, to: r.to)
    }

    var body: some View {
        let d = data
        SheetScroll {
            BigHeader(title: "Сводка", subtitle: "для ChatGPT", size: 30)
            PeriodPicker(period: $period, from: $from, to: $to)
            FieldGroup(title: "Эпизоды") {
                if d.episodes.isEmpty {
                    Cap("За этот период эпизодов нет.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(d.episodes.suffix(15).reversed().enumerated()), id: \.element.id) { i, e in
                            if i > 0 { Rectangle().fill(pal.edge).frame(height: 1) }
                            episodeRow(e)
                        }
                    }
                    .padding(.horizontal, 14)
                    .glass(18)
                }
            }
            FlowLayout {
                Chip(text: "выводы", isOn: withInsights) { withInsights.toggle() }
                Chip(text: "практики", isOn: withPractices) { withPractices.toggle() }
            }
            FieldGroup(title: edited ? "Текст (изменён вручную)" : "Текст — можно поправить") {
                TextEditor(text: Binding(get: { text }, set: { text = $0; edited = true }))
                    .txt(13.5)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 260)
                    .padding(10)
                    .glass(18)
                    .accessibilityLabel("Текст сводки")
            }
            if edited {
                Chip(text: "собрать заново", icon: "arrow.clockwise") {
                    edited = false
                    rebuild()
                }
            }
            HStack(spacing: 10) {
                CTAButton(title: copied ? "Скопировано" : "Скопировать", icon: copied ? "checkmark" : "doc.on.doc", small: true) {
                    UIPasteboard.general.string = text
                    copied = true
                    Haptics.success(store.settings.hapticsEnabled)
                }
                ShareLink(item: text) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .bold))
                        Text("Отправить").display(15)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .glass(30, strong: true)
                }
                .buttonStyle(PressStyle())
            }
            Cap("Ничего не отправляется само. Перед тем как вставить текст в чат, проверь, нет ли в нём лишнего.")
        }
        .onAppear(perform: rebuild)
        .onChange(of: period) { _, _ in excluded = []; rebuild() }
        .onChange(of: from) { _, _ in rebuild() }
        .onChange(of: to) { _, _ in rebuild() }
        .onChange(of: excluded) { _, _ in rebuild() }
        .onChange(of: withInsights) { _, _ in rebuild() }
        .onChange(of: withPractices) { _, _ in rebuild() }
    }

    private func episodeRow(_ e: ReportEpisode) -> some View {
        let on = !excluded.contains(e.id)
        return Button {
            if on { excluded.insert(e.id) } else { excluded.remove(e.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(on ? Theme.mint : pal.fg2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ReportText.episodeLine(e)).txt(13.5, .semibold)
                    if let c = e.cause ?? e.thoughts { Cap(c) }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "включён" : "не включён")
    }

    private func rebuild() {
        copied = false
        guard !edited else { return }
        text = SummaryText.make(data, excluded: excluded, insights: withInsights, practices: withPractices)
    }
}

enum SummaryText {
    static func make(_ d: ReportData, excluded: Set<UUID>, insights: Bool, practices: Bool) -> String {
        var out: [String] = []
        out.append("Это короткая сводка из моего дневника тревоги за период: \(d.periodTitle). Оценки — по шкале от 0 до 10.")
        out.append("")
        out.append("Общее:")
        for line in ReportText.summaryLines(d) { out.append("— " + line) }

        let episodes = d.episodes.filter { !excluded.contains($0.id) }
        if !episodes.isEmpty {
            out.append("")
            out.append("Эпизоды:")
            for (i, e) in episodes.enumerated() {
                var parts = ["\(i + 1)) " + ReportText.episodeLine(e) + "."]
                if let c = e.cause { parts.append("Причина: \(c).") }
                if let t = e.thoughts { parts.append("Мысли: \(t).") }
                if !e.symptoms.isEmpty { parts.append("В теле: \(e.symptoms.joined(separator: ", ")).") }
                if let c = e.coping { parts.append("Что помогло: \(c).") }
                if let x = e.insight { parts.append("Что поняла: \(x).") }
                out.append(parts.joined(separator: " "))
            }
        }
        if insights && !d.insights.isEmpty {
            out.append("")
            out.append("Мои выводы:")
            for x in d.insights.suffix(8) { out.append("— \(x)") }
        }
        if practices && !d.practices.isEmpty {
            out.append("")
            out.append("Практики:")
            for p in d.practices { out.append("— " + ReportText.practiceLine(p)) }
        }
        out.append("")
        out.append("Что я хочу обсудить: ")
        return out.joined(separator: "\n")
    }
}
