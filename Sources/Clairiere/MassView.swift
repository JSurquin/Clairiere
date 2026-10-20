import SwiftUI

struct MassView: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chaque barre est une app entière, onglets compris. Plus elle est longue, plus l’app utilise de mémoire.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if store.visibleGroups.isEmpty {
                Panel {
                    Text("Rien à comparer pour le moment.")
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(store.visibleGroups) { group in
                    massRow(group)
                        .id(group.id)
                }
            }
        }
    }

    private func massRow(_ group: AppGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppGlyph(group: group, size: 28)
                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(group.strata.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(group.strata.tint)
                Spacer()
                Text(Format.mem(group.footprint))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            GeometryReader { geo in
                let scale = max(Double(store.snapshot.physical), Double(store.visibleGroups.map(\.footprint).max() ?? 1), 1)
                let width = geo.size.width * CGFloat(Double(group.footprint) / scale)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.wash)
                    Capsule()
                        .fill(group.strata.tint.opacity(0.9))
                        .frame(width: max(8, width))
                }
            }
            .frame(height: 16)
        }
        .padding(12)
        .background(store.rowOn(group.id) ? Theme.cardRaised : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(store.rowOn(group.id) ? group.strata.tint.opacity(0.7) : Theme.line, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            store.cursorID = group.id
            store.selectedID = group.id
        }
    }
}
