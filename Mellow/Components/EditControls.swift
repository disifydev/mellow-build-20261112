import SwiftUI
import PivchikDomain

// MARK: Плашка «Удалено · Отменить»

/// Нижняя плашка после удаления: 5 секунд можно вернуть всё как было.
struct UndoToastBar: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.palette) private var pal

    var body: some View {
        VStack {
            if let t = store.toast {
                HStack(spacing: 10) {
                    Image(systemName: "trash").font(.system(size: 14, weight: .semibold)).opacity(0.7)
                    Text(t.text).txt(14.5, .semibold).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Button { store.undoDelete() } label: {
                        Text("Отменить").txt(14, .bold)
                            .foregroundStyle(pal.onFg)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Capsule().fill(pal.on))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint("Вернуть удалённое")
                }
                .foregroundStyle(pal.fg)
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .frame(height: 52)
                .glass(26, strong: true)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(t.id)
            }
        }
        .animation(.spring(duration: 0.35), value: store.toast)
    }
}

// MARK: Формы правки

/// Выбор нескольких историй чипами (запись может относиться к нескольким).
struct MultiStoryPicker: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selection: [UUID]

    var body: some View {
        if store.histories.isEmpty {
            Cap("Историй пока нет. Их можно создать на вкладке «Истории».")
        } else {
            FlowLayout {
                ForEach(store.histories, id: \.meta.id) { h in
                    Chip(text: h.title, isOn: selection.contains(h.meta.id)) {
                        if let i = selection.firstIndex(of: h.meta.id) {
                            selection.remove(at: i)
                        } else {
                            selection.append(h.meta.id)
                        }
                    }
                }
            }
        }
    }
}

/// Подпись «изменено ЧЧ:ММ» под формой или в строке.
struct EditedNote: View {
    let date: Date?
    var body: some View {
        if let date { Cap(Fmt.edited(date)) }
    }
}

/// Кнопка «Удалить» внизу формы правки.
struct DeleteRecordButton: View {
    var title: String = "Удалить запись"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "trash").font(.system(size: 14, weight: .semibold))
                Text(title).txt(14.5, .semibold)
            }
            .foregroundStyle(Theme.pink)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .glass(23)
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: Смахивание влево

/// Строка, которую можно смахнуть влево до кнопки «Удалить». Нажатие на строку — `onTap`.
struct SwipeToDelete<Content: View>: View {
    var startOpen: Bool = false
    var enabled: Bool = true
    let onTap: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var base: CGFloat = 0
    @State private var horizontal: Bool?
    private let open: CGFloat = -96

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button {
                    close()
                    onDelete()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash").font(.system(size: 16, weight: .semibold))
                        Text("Удалить").txt(12, .semibold)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(width: 84)
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.pink))
                }
                .buttonStyle(PressStyle())
                .opacity(min(1, Double(-offset / 60)))
                .accessibilityHidden(true)
            }
            content()
                .contentShape(Rectangle())
                .offset(x: offset)
                .onTapGesture {
                    if offset != 0 { close() } else { onTap() }
                }
                .simultaneousGesture(drag, including: enabled ? .all : .subviews)
        }
        .onAppear { if startOpen { offset = open; base = open } }
        .onChange(of: enabled) { _, on in if !on { close() } }
        .accessibilityAction(named: "Удалить") { onDelete() }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { g in
                if horizontal == nil {
                    horizontal = abs(g.translation.width) > abs(g.translation.height) * 1.3
                }
                guard horizontal == true else { return }
                offset = min(0, max(open * 1.6, base + g.translation.width))
            }
            .onEnded { g in
                defer { horizontal = nil }
                guard horizontal == true else { return }
                let target = (base + g.predictedEndTranslation.width) < open / 2 ? open : 0
                withAnimation(.spring(duration: 0.3)) { offset = target }
                base = target
            }
    }

    private func close() {
        withAnimation(.spring(duration: 0.3)) { offset = 0 }
        base = 0
    }
}
