import SwiftUI

struct StrataView: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if store.visibleGroups.isEmpty {
                empty
            } else {
                ForEach(Strata.allCases) { strata in
                    let rows = store.groups(in: strata)
                    if !rows.isEmpty {
                        section(strata, rows: rows)
                    }
                }
                footer
            }
        }
    }

    private func section(_ strata: Strata, rows: [AppGroup]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(strata.title)
                        .font(.system(size: 18, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.text)
                    Text(strata.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(Format.mem(rows.reduce(0) { $0 + $1.footprint }))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(strata.tint)
            }
            ForEach(rows) { group in
                GroupCard(group: group)
                    .id(group.id)
            }
        }
    }

    private var empty: some View {
        Panel {
            Text(store.query.isEmpty ? "Rien d’assez gros à montrer." : "Aucune app ne correspond à cette recherche.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        Text("Total affiché : \(Format.mem(store.visibleGroups.reduce(0) { $0 + $1.footprint })). Ce total peut dépasser la mémoire du Mac, parce qu’une partie est compressée. La barre du haut décrit tout l’ordinateur.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

struct GroupCard: View {
    @Environment(MemoryStore.self) private var store
    var group: AppGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                AppGlyph(group: group, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if group.isSelf {
                            Chip(text: "cette app", tint: Theme.leaf)
                        }
                    }
                    Text(group.narrative)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.mem(group.footprint))
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text(Format.share(group.footprint, of: max(store.snapshot.physical, 1)))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
            }

            SegmentBar(segments: group.segments)

            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Chip(text: chip, tint: group.strata.tint)
                }
                Spacer()
                if group.canQuit {
                    ActionButton(
                        title: "Fermer",
                        tint: Theme.leaf,
                        prominent: true,
                        helpText: group.menuBar
                            ? "Demande à l’icône de \(group.name) de quitter la barre. Raccourci : ⌘↩"
                            : "Demande à \(group.name) de se fermer. Raccourci : ⌘↩"
                    ) {
                        store.quit(group)
                    }
                    ActionButton(
                        title: "Forcer",
                        tint: Theme.coral,
                        helpText: "Ferme \(group.name) tout de suite. Raccourci : ⌘⇧↩"
                    ) {
                        store.forceRequest = .application(group.id)
                    }
                } else if let part = group.parts.first(where: \.canSignal) {
                    ActionButton(
                        title: "Fermer",
                        tint: Theme.gold,
                        prominent: true,
                        helpText: "Ferme \(part.name)."
                    ) {
                        store.stopPart(part)
                    }
                    ActionButton(
                        title: "Forcer",
                        tint: Theme.coral,
                        helpText: "Coupe \(part.name) immédiatement."
                    ) {
                        store.forceRequest = .process(pid: part.pid, title: part.name)
                    }
                } else {
                    Chip(text: "laisser ouvert", tint: Theme.coral)
                }
            }
        }
        .padding(14)
        .background(store.rowOn(group.id) ? Theme.cardRaised : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(store.rowOn(group.id) ? group.strata.tint.opacity(0.7) : Theme.line, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            store.cursorID = group.id
            store.selectedID = group.id
        }
        .contextMenu {
            if group.canQuit {
                Button("Fermer \(group.name)") { store.quit(group) }
                Button("Forcer la fermeture") { store.forceRequest = .application(group.id) }
            }
            Button("Voir le détail") {
                store.cursorID = group.id
                store.selectedID = group.id
            }
            if group.bundlePath != nil || group.parts.first?.path.isEmpty == false {
                Button("Révéler dans le Finder") { store.reveal(group) }
            }
        }
    }

    private var chips: [String] {
        var values: [String] = []
        let pages = group.parts.filter { $0.role == .pages }.count
        if pages > 0 {
            values.append(Format.count(pages, one: group.strata == .browsers ? "onglet" : "partie", many: group.strata == .browsers ? "onglets" : "parties"))
        } else if group.parts.count > 1 {
            values.append(Format.count(group.parts.count, one: "partie", many: "parties"))
        }
        if group.menuBar {
            values.append("barre de menus")
        }
        values.append(Format.cpu(group.cpu))
        if abs(group.driftPerMinute) > 30_000_000 && group.history.count >= 4 {
            values.append(Format.signedMem(group.driftPerMinute))
        }
        return values
    }
}
