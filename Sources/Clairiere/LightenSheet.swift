import SwiftUI

struct LightenSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var armed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Libérer de la mémoire")
                        .font(.system(size: 28, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.text)
                    Text("Fermez les apps que vous utilisez très peu. La mémoire se libère tout de suite.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Fermer") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Apps peu utilisées")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text(store.lightenPicked.isEmpty ? "Aucune app cochée" : "Jusqu’à \(Format.mem(selectedBytes))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.leaf)
                }
                if store.idleHeavy.isEmpty {
                    Text("Aucune grosse app n’est peu utilisée pour l’instant. L’app au premier plan n’est jamais proposée. Si la liste est vide, patientez quelques secondes.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(store.idleHeavy) { group in
                                candidate(group)
                                    .id("idle:\(group.id)")
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
                HStack {
                    Spacer()
                    ActionButton(
                        title: store.lightenPicked.isEmpty ? "Choisir une app" : "Fermer la sélection",
                        tint: Theme.leaf,
                        prominent: !store.lightenPicked.isEmpty,
                        helpText: "Demande à chaque app cochée de se fermer normalement."
                    ) {
                        guard !store.lightenPicked.isEmpty else { return }
                        store.quitMany(store.lightenPicked)
                        dismiss()
                    }
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Option avancée")
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.text)
                Text(store.nudgeReason)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let report = store.nudgeReport {
                    Text(report)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.leaf)
                }
                HStack {
                    Spacer()
                    ActionButton(
                        title: store.isNudging ? "En cours…" : "Compresser les caches",
                        tint: store.nudgeAllowed ? Theme.gold : Theme.muted,
                        prominent: store.nudgeAllowed,
                        helpText: store.nudgeReason
                    ) {
                        guard store.nudgeAllowed, !store.isNudging else { return }
                        Task { await store.nudge() }
                    }
                    .disabled(!store.nudgeAllowed || store.isNudging)
                    .opacity(store.nudgeAllowed ? 1 : 0.55)
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(22)
        .frame(width: 640)
        .background(Theme.bg)
        .onAppear {
            guard !armed else { return }
            armed = true
            store.lightenPicked = Set(store.idleHeavy.filter { $0.footprint > 400_000_000 }.map(\.id))
        }
    }

    private var selectedBytes: UInt64 {
        store.idleHeavy.filter { store.lightenPicked.contains($0.id) }.reduce(0) { $0 + $1.footprint }
    }

    private func candidate(_ group: AppGroup) -> some View {
        HStack(spacing: 10) {
            Button {
                if store.lightenPicked.contains(group.id) {
                    store.lightenPicked.remove(group.id)
                } else {
                    store.lightenPicked.insert(group.id)
                }
            } label: {
                Image(systemName: store.lightenPicked.contains(group.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(store.lightenPicked.contains(group.id) ? Theme.leaf : Theme.muted)
            }
            .buttonStyle(.plain)
            AppGlyph(group: group, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(group.advice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Text(Format.mem(group.footprint))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
        }
        .padding(8)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
