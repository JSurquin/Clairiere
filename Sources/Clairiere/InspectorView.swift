import AppKit
import SwiftUI

struct InspectorView: View {
    @Environment(MemoryStore.self) private var store
    var group: AppGroup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    AppGlyph(group: group, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.strata.title.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(group.strata.tint)
                        Text(group.name)
                            .font(.system(size: 22, weight: .medium, design: .default))
                            .foregroundStyle(Theme.text)
                        Text(Format.mem(group.footprint))
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.text)
                    }
                }

                if group.history.count >= 2 {
                    Sparkline(points: group.history.map { Double($0.footprint) }, color: group.strata.tint)
                        .frame(height: 42)
                        .padding(.vertical, 4)
                }

                advice
                numbers
                parts
                actions
            }
            .padding(18)
        }
        .frame(width: 340)
        .background(Theme.bg)
    }

    private var advice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.narrative)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(group.advice)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(group.strata.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Mémoire", Format.mem(group.footprint))
            row("Vraiment en mémoire", Format.mem(group.resident))
            if group.footprint > group.resident {
                row("Déjà compressée", Format.mem(group.footprint - group.resident))
            }
            row("Plus haut atteint", Format.mem(group.parts.map(\.peak).max() ?? group.footprint))
            row("Activité", Format.cpu(group.cpu))
            if abs(group.driftPerMinute) > 1 {
                row("Évolution", Format.signedMem(group.driftPerMinute))
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var parts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ce qu’elle contient")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            if group.parts.count > 1 {
                Text("Le total additionne tous les morceaux. C’est une estimation, pas une mesure exacte.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(group.parts.prefix(14)) { part in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(part.role.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(part.role.tint)
                            .frame(width: 72, alignment: .leading)
                        Text(part.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Spacer()
                        Text(Format.mem(part.footprint))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.text)
                    }
                    HStack {
                        Text(Format.cpu(part.cpu))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                        if abs(part.driftPerMinute) > 20_000_000 {
                            Text(Format.signedMem(part.driftPerMinute))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(part.driftPerMinute > 0 ? Theme.coral : Theme.leaf)
                        }
                        Spacer()
                        if part.isMain && group.canQuit {
                            ActionButton(title: "Fermer l’app", tint: Theme.leaf, prominent: true, helpText: group.advice) {
                                store.quit(group)
                            }
                        } else if part.canSignal {
                            ActionButton(title: "Fermer cette partie", tint: Theme.gold, helpText: "Ferme seulement cette partie.") {
                                store.stopPart(part)
                            }
                            ActionButton(title: "Forcer", tint: Theme.coral, helpText: "Coupe ce processus immédiatement.") {
                                store.forceRequest = .process(pid: part.pid, title: part.name)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if group.parts.count > 14 {
                Text("\(group.parts.count - 14) parties plus petites restent dans le total.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if group.canQuit {
                ActionButton(title: "Fermer", tint: Theme.leaf, prominent: true, helpText: "Fermeture normale") {
                    store.quit(group)
                }
                ActionButton(title: "Forcer", tint: Theme.coral, helpText: "Fermeture immédiate") {
                    store.forceRequest = .application(group.id)
                }
            }
            ActionButton(title: "Finder", tint: Theme.sky, helpText: "Montre l’app dans le Finder") {
                store.reveal(group)
            }
            ActionButton(title: "Copier", tint: Theme.muted, helpText: "Copie le chemin") {
                let path = group.bundlePath ?? group.parts.first?.path ?? ""
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
                store.status = "Chemin copié."
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
        }
    }
}
