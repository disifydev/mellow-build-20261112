import SwiftUI

/// Стеклянный таббар: активная вкладка шире и показывает подпись.
struct TabBar: View {
    @EnvironmentObject private var router: Router
    @Environment(\.palette) private var pal

    var body: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - 10) / CGFloat(AppTab.bar.count)
            HStack(spacing: 0) {
                ForEach(AppTab.bar, id: \.self) { tab in
                    item(tab, width: unit)
                }
            }
            .padding(5)
        }
        .frame(height: 66)
        .glass(33, strong: true)
    }

    private func item(_ tab: AppTab, width: CGFloat) -> some View {
        let on = router.tab.barTab == tab
        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { router.tab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon).font(.system(size: 17, weight: .semibold))
                Text(tab.title).txt(11, .semibold).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? pal.onFg : pal.fg)
            .frame(width: max(0, width), height: 54)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 27, style: .continuous).fill(pal.on).shadow(color: pal.shadow, radius: 7, x: 0, y: 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
