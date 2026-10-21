import SwiftUI

struct SidebarView: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Mark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clairière")
                        .font(.system(size: 20, weight: .medium, design: .default))
                        .foregroundStyle(Theme.text)
                    Text("mémoire et disque")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 28)

            appearanceToggle

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(store.band.tint).frame(width: 7, height: 7)
                    Text(store.band.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.band.tint)
                }
                Text(store.snapshot.physical == 0 ? "…" : Format.mem(store.snapshot.used))
                    .font(.system(size: 28, weight: .medium, design: .default))
                    .foregroundStyle(Theme.text)
                Text(store.snapshot.physical == 0 ? "lecture…" : "utilisés sur \(Format.mem(store.snapshot.physical))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                if store.snapshot.swapUsed > 0 {
                    Text("\(Format.mem(store.snapshot.swapUsed)) sur le disque")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(store.snapshot.swapUsed > 2_000_000_000 ? Theme.coral : Theme.gold)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Lens.allCases) { lens in
                        lensButton(lens)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button {
                store.showLighten = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wind")
                    Text("Libérer")
                    Spacer()
                    if !store.idleHeavy.isEmpty {
                        Text("\(store.idleHeavy.count)")
                            .font(.system(size: 11, weight: .bold, design: .default))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.leaf.opacity(0.18), in: Capsule())
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.leaf)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.leaf.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Fermer les apps peu utilisées")

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(store.status)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("La mémoire fait tourner les apps. Le disque garde vos fichiers.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(width: 248)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var appearanceToggle: some View {
        HStack(spacing: 2) {
            modeButton(title: "Sombre", symbol: "moon.fill", on: !store.lightTheme) {
                store.setAppearance(light: false)
            }
            modeButton(title: "Clair", symbol: "sun.max.fill", on: store.lightTheme) {
                store.setAppearance(light: true)
            }
        }
        .padding(3)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        .help("Choisir le thème clair ou sombre")
    }

    private func modeButton(title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(on ? Theme.text : Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(on ? Theme.cardRaised : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func lensButton(_ lens: Lens) -> some View {
        let selected = store.lens == lens
        return Button {
            store.lens = lens
        } label: {
            HStack(spacing: 10) {
                Image(systemName: lens.symbol)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lens.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(lens.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .foregroundStyle(selected ? Theme.text : Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Theme.cardRaised : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
