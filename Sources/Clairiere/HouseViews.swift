import AppKit
import SwiftUI

struct HomeView: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rien ne démarre tout seul. Ouvrez une tuile pour voir le détail. Vous confirmez toujours avant qu’on enlève quoi que ce soit.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile(
                    id: "home:memory",
                    title: "Mémoire",
                    symbol: "memorychip",
                    tint: store.band.tint,
                    value: store.snapshot.physical == 0 ? "Lecture…" : Format.mem(store.snapshot.used),
                    detail: store.band.headline
                ) { store.show(.memory) }

                tile(
                    id: "home:cleanup",
                    title: "Nettoyage",
                    symbol: "sparkles",
                    tint: Theme.leaf,
                    value: store.cleanup.ready ? Format.mem(store.cleanup.suggestedBytes) : "…",
                    detail: store.cleanup.ready ? "prêts à nettoyer" : "ouvrir pour mesurer"
                ) { store.show(.cleanup) }

                tile(
                    id: "home:storage",
                    title: "Stockage",
                    symbol: "internaldrive",
                    tint: Theme.gold,
                    value: store.disk.volume.total == 0 ? "Lecture…" : Format.mem(store.disk.volume.available),
                    detail: "libres sur le disque"
                ) { store.show(.storage) }

                tile(
                    id: "home:apps",
                    title: "Apps",
                    symbol: "square.grid.2x2",
                    tint: Theme.sky,
                    value: store.shelf.ready ? "\(store.shelf.apps.count)" : "…",
                    detail: store.shelf.ready ? appDetail : "ouvrir pour mesurer"
                ) { store.show(.apps) }

                tile(
                    id: "home:startup",
                    title: "Démarrage",
                    symbol: "bolt",
                    tint: Theme.gold,
                    value: store.boot.ready ? "\(store.boot.items.count)" : "…",
                    detail: store.boot.ready ? startupDetail : "ouvrir pour mesurer"
                ) { store.show(.startup) }

                tile(
                    id: "home:advisor",
                    title: "IA",
                    symbol: "wand.and.stars",
                    tint: Theme.sky,
                    value: store.advisor.items.isEmpty ? "Locale" : "\(store.advisor.items.count)",
                    detail: store.advisor.items.isEmpty ? "fichiers anciens" : "fichiers à regarder"
                ) { store.show(.advisor) }

                tile(
                    id: "home:idle",
                    title: "Peu utilisées",
                    symbol: "wind",
                    tint: Theme.leaf,
                    value: "\(store.idleHeavy.count)",
                    detail: "grosses apps peu actives"
                ) { store.show(.memory) }
            }
        }
        .onAppear {
            store.disk.prepareVolume()
        }
    }

    private var appDetail: String {
        if let note = store.shelf.macUpdate, note.contains("Mise à jour") { return note }
        let updates = store.shelf.apps.filter { $0.update != nil }.count
        if updates > 0 { return Format.count(updates, one: "mise à jour d’app", many: "mises à jour d’apps") }
        return "installées dans Applications"
    }

    private var startupDetail: String {
        let warnings = store.boot.items.filter { $0.warning != nil }.count
        if warnings > 0 { return Format.count(warnings, one: "élément à regarder", many: "éléments à regarder") }
        return "ouvertures et agents"
    }

    private func tile(id: String, title: String, symbol: String, tint: Color, value: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(store.cursorID == id ? Theme.leaf : Theme.line, lineWidth: store.cursorID == id ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .id(id)
    }
}

struct CleanupView: View {
    @Environment(MemoryStore.self) private var store

    private var rows: [JunkItem] {
        store.cleanup.items.filter { item in
            guard !store.query.isEmpty else { return true }
            if item.title.localizedStandardContains(store.query) || item.detail.localizedStandardContains(store.query) {
                return true
            }
            return item.parts.contains {
                $0.name.localizedStandardContains(store.query) || $0.path.localizedStandardContains(store.query)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.cleanup.scanning ? "Lecture…" : store.cleanup.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Actualiser") { Task { await store.cleanup.scan() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.leaf)
                    .disabled(store.cleanup.scanning)
            }
            ForEach(rows) { item in
                VStack(alignment: .leading, spacing: 0) {
                    CheckLine(
                        title: item.title,
                        detail: item.detail,
                        meta: Format.mem(item.bytes),
                        on: store.cleanup.picked.contains(item.id),
                        focused: store.cursorID == "junk:\(item.id)",
                        actionTitle: item.permanent ? "Vider" : "Corbeille",
                        expandable: item.parts.count > 1,
                        expanded: store.cleanup.openID == item.id,
                        reveal: { store.cleanup.toggleOpen(item.id) }
                    ) {
                        store.cleanup.toggle(item.id)
                    } action: {
                        store.pending = store.cleanup.pending(for: [item.id])
                    }
                    if showsParts(item) {
                        cleanupParts(item)
                    }
                }
                .id("junk:\(item.id)")
            }
            if !rows.isEmpty {
                HStack {
                    Spacer()
                    ActionButton(title: "Mettre la sélection à la Corbeille", tint: Theme.leaf, prominent: true, helpText: "Demande confirmation avant d’enlever les éléments cochés.") {
                        store.pending = store.cleanup.pending(for: store.cleanup.picked)
                    }
                    .disabled(store.cleanup.picked.isEmpty)
                    .opacity(store.cleanup.picked.isEmpty ? 0.45 : 1)
                }
            }
        }
        .onAppear { store.cleanup.prepare() }
    }

    private func showsParts(_ item: JunkItem) -> Bool {
        if store.cleanup.openID == item.id { return true }
        guard !store.query.isEmpty else { return false }
        let titleHit = item.title.localizedStandardContains(store.query) || item.detail.localizedStandardContains(store.query)
        if titleHit { return false }
        return item.parts.contains {
            $0.name.localizedStandardContains(store.query) || $0.path.localizedStandardContains(store.query)
        }
    }

    private func visibleParts(_ item: JunkItem) -> [JunkPart] {
        guard !store.query.isEmpty else { return item.parts }
        let hits = item.parts.filter {
            $0.name.localizedStandardContains(store.query) || $0.path.localizedStandardContains(store.query)
        }
        return hits.isEmpty ? item.parts : hits
    }

    private func cleanupParts(_ item: JunkItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Du plus lourd au plus léger.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
            ForEach(visibleParts(item)) { part in
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: part.path)])
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(part.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Text(HouseScan.pretty(part.path))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(Format.mem(part.bytes))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.text)
                    }
                }
                .buttonStyle(.plain)
                .help("Montrer dans le Finder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .padding(.leading, 28)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct FileLists: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Gros fichiers", "Plus de 50 Mo, hors bibliothèque. Rien n’est coché.", store.files.large, empty: "Aucun gros fichier pour le moment.")
            section("Dossiers lourds", "Votre maison, sans la bibliothèque, la musique ni Photos.", store.files.folders, empty: "Pas encore de dossier au-dessus de 50 Mo.")
            section("Téléchargements anciens", "Plus d’un mois. Ils restent décochés : vous les avez peut-être gardés.", store.files.downloads, empty: "Aucun ancien téléchargement de plus de 1 Mo.")
            section("Copies", "Même contenu. La copie la plus récente est gardée, les autres sont proposées.", store.files.duplicates, empty: "Aucune copie évidente dans Bureau, Documents et Téléchargements.")
            if !store.files.all.isEmpty {
                HStack {
                    Text(store.files.scanning ? "Lecture encore en cours…" : store.files.message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    ActionButton(title: "Mettre la sélection à la Corbeille", tint: Theme.leaf, prominent: true, helpText: "Met les fichiers cochés à la Corbeille.") {
                        store.pending = store.files.pending(for: store.files.picked)
                    }
                    .disabled(store.files.picked.isEmpty)
                    .opacity(store.files.picked.isEmpty ? 0.45 : 1)
                }
            } else if store.files.scanning {
                Text("Lecture de la maison…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .onAppear { store.files.prepare() }
    }

    private func section(_ title: String, _ detail: String, _ items: [FileItem], empty: String) -> some View {
        let shown = items.filter {
            store.query.isEmpty || $0.title.localizedStandardContains(store.query) || $0.note.localizedStandardContains(store.query)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundStyle(Theme.text)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            if shown.isEmpty {
                Text(empty).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            ForEach(shown) { item in
                CheckLine(
                    title: item.title,
                    detail: item.note,
                    meta: Format.mem(item.bytes),
                    on: store.files.picked.contains(item.id),
                    focused: store.cursorID == "file:\(item.id)",
                    actionTitle: "Corbeille"
                ) {
                    store.files.toggle(item.id)
                } action: {
                    store.pending = store.files.pending(for: [item.id])
                }
                .id("file:\(item.id)")
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct AppsView: View {
    @Environment(MemoryStore.self) private var store

    private var rows: [AppRecord] {
        store.shelf.apps.filter {
            store.query.isEmpty || $0.name.localizedStandardContains(store.query) || $0.bundleID.localizedStandardContains(store.query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.shelf.message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                    if let mac = store.shelf.macUpdate {
                        Text(mac)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.gold)
                    }
                }
                Spacer()
                if store.shelf.macUpdate?.contains("Mise à jour") == true {
                    Button("Ouvrir Réglages") { store.openSoftwareUpdate() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.leaf)
                }
                Button("Retirer la sélection") { store.pending = store.pendingCheckedApps() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .disabled(store.shelf.picked.isEmpty)
                Button("Actualiser") { Task { await store.shelf.scan() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.leaf)
                    .disabled(store.shelf.scanning)
            }
            ForEach(rows) { app in
                appRow(app).id("app:\(app.id)")
            }
        }
        .onAppear { store.shelf.prepare() }
    }

    private func appRow(_ app: AppRecord) -> some View {
        HStack(spacing: 10) {
            Button { store.shelf.toggle(app.id) } label: {
                Image(systemName: store.shelf.picked.contains(app.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(store.shelf.picked.contains(app.id) ? Theme.leaf : Theme.muted)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if app.quarantined {
                        Chip(text: "pas encore ouverte", tint: Theme.gold)
                    }
                }
                Text(appLine(app))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Text(Format.mem(app.bytes))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(store.cursorID == "app:\(app.id)" ? Theme.leaf : Theme.line, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            store.cursorID = "app:\(app.id)"
            store.shelf.select(app)
        }
    }

    private func appLine(_ app: AppRecord) -> String {
        var parts = [app.version.isEmpty ? "version inconnue" : "version \(app.version)", "ouverte \(Format.day(app.lastUsed))"]
        if let update = app.update { parts.append(update) }
        return parts.joined(separator: " · ")
    }
}

struct AppDetailView: View {
    @Environment(MemoryStore.self) private var store
    var app: AppRecord

    private var isSelf: Bool { app.bundleID == Bundle.main.bundleIdentifier }
    private var running: Bool {
        store.groups.contains { $0.bundlePath == app.path || ($0.bundleID != nil && $0.bundleID == app.bundleID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(app.name)
                .font(.system(size: 26, weight: .medium, design: .default))
                .foregroundStyle(Theme.text)
            Text(HouseScan.pretty(app.path))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .textSelection(.enabled)
            if isSelf {
                Text("C’est Clairière. Elle ne peut pas se retirer elle-même.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.gold)
            } else if running {
                Text("Cette app est ouverte. Fermez-la dans Mémoire avant de la retirer.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let update = app.update {
                Text(update)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.leaf)
                Button("Ouvrir la page de mise à jour") { Task { await store.openSparkle(app) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.leaf)
            }
            Text("Restes sur ce Mac")
                .font(.system(size: 16, weight: .medium, design: .default))
                .foregroundStyle(Theme.text)
            if store.shelf.leftovers.isEmpty {
                Text("Aucun reste évident à côté de l’app.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(store.shelf.leftovers, id: \.self) { path in
                    Button { store.shelf.toggleLeftover(path) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: store.shelf.leftoverPicked.contains(path) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Theme.leaf)
                            Text(HouseScan.pretty(path))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            VStack(spacing: 8) {
                ActionButton(title: "Montrer dans le Finder", tint: Theme.sky, prominent: false, helpText: "Ouvre le dossier de l’app.") {
                    store.reveal(app.path)
                }
                ActionButton(title: "Remettre à zéro", tint: Theme.gold, prominent: false, helpText: "Met seulement les préférences à la Corbeille.") {
                    let prefs = store.shelf.leftoverPicked.filter { $0.contains("/Preferences/") }
                    let extra = prefs.isEmpty
                        ? store.shelf.leftovers.filter { $0.contains("/Preferences/") }
                        : Array(prefs)
                    store.pending = store.shelf.removalPending(includeApp: false, extra: extra)
                }
                .disabled(isSelf)
                ActionButton(title: "Retirer", tint: Theme.coral, prominent: true, helpText: "Met l’app et les restes cochés à la Corbeille.") {
                    store.pending = store.shelf.removalPending(includeApp: true, extra: Array(store.shelf.leftoverPicked))
                }
                .disabled(isSelf || running || app.path.hasPrefix("/System"))
                .opacity(isSelf || running ? 0.45 : 1)
            }
        }
        .padding(22)
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }
}

struct StartupView: View {
    @Environment(MemoryStore.self) private var store

    private var rows: [BootRecord] {
        store.boot.items.filter {
            store.query.isEmpty || $0.name.localizedStandardContains(store.query) || $0.detail.localizedStandardContains(store.query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clairière n’est pas un antivirus. Elle liste ce qui s’ouvre tout seul : agents, ouvertures de session, apps mises en quarantaine, et quelques emplacements que les pubs utilisent souvent.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(store.boot.scanning ? "Lecture…" : store.boot.message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
            if !store.boot.maintenance.isEmpty {
                Text(store.boot.maintenance)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.leaf)
            }
            ForEach(rows) { item in
                bootRow(item).id("boot:\(item.id)")
            }
            quarantine
            maintenance
        }
        .onAppear { store.boot.prepare() }
    }

    private func bootRow(_ item: BootRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if item.locked { Chip(text: "laisser ouvert", tint: Theme.muted) }
                        if item.disabled { Chip(text: "désactivé", tint: Theme.gold) }
                    }
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Spacer()
                if item.locked && item.id.hasPrefix("login:") {
                    ActionButton(title: "Réglages", tint: Theme.sky, prominent: false, helpText: "Ouvre les ouvertures de session.") {
                        store.openLoginItems()
                    }
                } else if !item.locked {
                    ActionButton(
                        title: item.disabled ? "Réactiver" : "Désactiver",
                        tint: item.disabled ? Theme.leaf : Theme.gold,
                        prominent: true,
                        helpText: "Déplace le fichier. Vous pouvez revenir en arrière."
                    ) {
                        Task { await store.boot.toggle(item) }
                    }
                }
            }
            if let warning = item.warning {
                Text(warning)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(store.cursorID == "boot:\(item.id)" ? Theme.leaf : Theme.line, lineWidth: 1)
        )
    }

    private var quarantine: some View {
        let apps = store.shelf.apps.filter(\.quarantined)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Apps encore en quarantaine")
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundStyle(Theme.text)
            if apps.isEmpty {
                Text("Aucune app du dossier Applications n’a été téléchargée sans être ouverte.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(apps) { app in
                    HStack {
                        Text(app.name).foregroundStyle(Theme.text)
                        Spacer()
                        Button("Finder") { store.reveal(app.path) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.leaf)
                    }
                    .font(.system(size: 13))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var maintenance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entretien")
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundStyle(Theme.text)
            Text("Vider le cache DNS oublie les adresses de sites déjà vues. Les instantanés Time Machine sont listés, et jamais supprimés sans confirmation. Clairière ne répare pas les permissions.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ActionButton(title: "Vider le cache DNS", tint: Theme.sky, prominent: false, helpText: "Demande à macOS d’oublier les adresses de sites vues récemment.") {
                Task { await store.boot.flushDNS() }
            }
            if store.boot.snapshots.isEmpty {
                Text("Aucun instantané Time Machine local.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(store.boot.snapshots) { snapshot in
                HStack {
                    Text(snapshot.label)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button("Supprimer") { store.pending = store.boot.snapshotPending(snapshot) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.coral)
                }
                .id("snap:\(snapshot.id)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct HelpSheet: View {
    var close: () -> Void

    private let rows: [(String, String)] = [
        ("⌘1 à ⌘7", "Accueil, Mémoire, Nettoyage, Stockage, Apps, Démarrage, IA"),
        ("⌘F", "Recherche de l’onglet"),
        ("↑ ↓", "Ligne précédente ou suivante"),
        ("Entrée", "Ouvre le détail"),
        ("Espace", "Coche ou décoche"),
        ("⌘A", "Coche toute la liste"),
        ("⌘⇧A", "Décoche toute la liste"),
        ("⌘Retour", "Action de la ligne"),
        ("⌘⇧Retour", "Forcer la fermeture"),
        ("⌘O", "Montrer dans le Finder"),
        ("Échap", "Ferme le dialogue, le détail, puis la recherche"),
        ("⌘L", "Libérer de la mémoire"),
        ("⌘⇧T", "Petites apps"),
        ("⌘?", "Cette liste")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Raccourcis")
                    .font(.system(size: 28, weight: .medium, design: .default))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("Fermer", action: close)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
            }
            Text("Après une recherche, ↓ va au premier résultat et Échap sort du champ sans l’effacer. Un second Échap vide la recherche. Les raccourcis ⌘ marchent aussi pendant la saisie.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.leaf)
                        .frame(width: 130, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .padding(22)
        .frame(width: 640)
        .background(Theme.bg)
    }
}

struct CheckLine: View {
    var title: String
    var detail: String
    var meta: String
    var on: Bool
    var focused: Bool
    var actionTitle: String
    var expandable = false
    var expanded = false
    var reveal: () -> Void = {}
    var toggle: () -> Void
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.leaf : Theme.muted)
            }
            .buttonStyle(.plain)
            if expandable {
                Button(action: reveal) {
                    lineLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(expanded ? "Replier" : "Voir ce que ça contient")
            } else {
                lineLabel
                Spacer()
            }
            Text(meta)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
            ActionButton(title: actionTitle, tint: Theme.leaf, prominent: true, helpText: detail, action: action)
        }
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focused ? Theme.leaf : Color.clear, lineWidth: 1.5)
        )
    }

    private var lineLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if expandable {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
    }
}
