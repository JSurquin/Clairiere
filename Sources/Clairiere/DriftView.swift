import SwiftUI

struct DriftView: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Seules les apps qui grossissent ou diminuent apparaissent ici. Une app lourde mais stable n’apparaît pas.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if store.sampleCount < 4 {
                Panel {
                    Text("Encore quelques secondes. Clairière compare plusieurs mesures pour voir ce qui grossit.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if store.driftingUp.isEmpty && store.driftingDown.isEmpty {
                Panel {
                    Text("Rien ne grossit vraiment. La mémoire est stable depuis l’ouverture de Clairière.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if !store.driftingUp.isEmpty {
                    driftSection("Ça gonfle", groups: store.driftingUp, tint: Theme.coral)
                }
                if !store.driftingDown.isEmpty {
                    driftSection("Ça diminue", groups: store.driftingDown, tint: Theme.leaf)
                }
            }
        }
    }

    private func driftSection(_ title: String, groups: [AppGroup], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundStyle(Theme.text)
            ForEach(groups) { group in
                driftRow(group, tint: tint)
                    .id(group.id)
            }
        }
    }

    private func driftRow(_ group: AppGroup, tint: Color) -> some View {
        HStack(spacing: 14) {
                    AppGlyph(group: group, size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(group.narrative)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                        Sparkline(points: group.history.map { Double($0.footprint) }, color: tint)
                            .frame(height: 28)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(Format.signedMem(group.driftPerMinute))
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(tint)
                        Text(Format.mem(group.footprint))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(store.rowOn(group.id) ? tint.opacity(0.8) : Theme.line, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    store.cursorID = group.id
                    store.selectedID = group.id
                }
    }
}
