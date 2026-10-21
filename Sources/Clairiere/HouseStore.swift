import Foundation
import Observation

@MainActor
@Observable
final class CleanupStore {
    var items: [JunkItem] = []
    var picked: Set<String> = []
    var scanning = false
    var ready = false
    var message = "Lecture des caches, journaux et corbeilles."
    var openID: String?
    @ObservationIgnored private var prepared = false
    @ObservationIgnored private var seeded = false

    var suggestedBytes: UInt64 {
        items.filter(\.suggested).reduce(0) { $0 + $1.bytes }
    }

    func prepare() {
        guard !prepared else { return }
        prepared = true
        Task { await scan() }
    }

    func scan() async {
        scanning = true
        let found = await Task.detached(priority: .utility) { HouseScan.cleanup() }.value
        items = found
        if !seeded {
            picked = Set(found.filter(\.suggested).map(\.id))
            seeded = true
        } else {
            let ids = Set(found.map(\.id))
            picked = picked.intersection(ids)
        }
        scanning = false
        ready = true
        if let openID, !found.contains(where: { $0.id == openID }) { self.openID = nil }
        message = found.isEmpty ? "Rien à montrer pour le moment." : "Cliquez sur une ligne pour voir ce qu’elle contient. Cochez, puis mettez à la Corbeille."
    }

    func toggleOpen(_ id: String) {
        openID = openID == id ? nil : id
    }

    func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    func pending(for ids: Set<String>) -> HousePending? {
        let chosen = items.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return nil }
        let trash = chosen.filter { !$0.permanent }.flatMap(\.paths)
        let destroy = chosen.filter(\.permanent).flatMap(\.paths)
        let bytes = chosen.reduce(UInt64(0)) { $0 + $1.bytes }
        let names = chosen.map(\.title).joined(separator: ", ")
        var message = "\(Format.mem(bytes)) · \(names)\n\n\(HouseScan.preview(trash + destroy))"
        if !destroy.isEmpty {
            message += "\n\nLa corbeille cochée sera vidée pour de bon. Le reste va dans la Corbeille, où vous pouvez le reprendre."
        } else {
            message += "\n\nTout va dans la Corbeille. Vous pouvez le reprendre ensuite."
        }
        return HousePending(
            title: destroy.isEmpty ? "Mettre à la Corbeille ?" : "Enlever ces éléments ?",
            message: message,
            trash: trash,
            destroy: destroy,
            snapshot: nil
        )
    }
}

@MainActor
@Observable
final class FileStore {
    var large: [FileItem] = []
    var folders: [FileItem] = []
    var downloads: [FileItem] = []
    var duplicates: [FileItem] = []
    var picked: Set<String> = []
    var scanning = false
    var ready = false
    var message = "Les gros fichiers apparaissent ici, à côté d’iCloud."
    @ObservationIgnored private var prepared = false

    var all: [FileItem] { large + folders + downloads + duplicates }

    func prepare() {
        guard !prepared else { return }
        prepared = true
        Task { await scan() }
    }

    func scan() async {
        scanning = true
        let found = await Task.detached(priority: .utility) { HouseScan.files() }.value
        large = found.large
        folders = found.folders
        downloads = found.downloads
        duplicates = found.duplicates
        let ids = Set(all.map(\.id))
        picked = picked.intersection(ids)
        message = found.note
        scanning = false
        ready = true
    }

    func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    func pending(for ids: Set<String>) -> HousePending? {
        let chosen = all.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return nil }
        let bytes = chosen.reduce(UInt64(0)) { $0 + $1.bytes }
        return HousePending(
            title: "Mettre à la Corbeille ?",
            message: "\(Format.mem(bytes)) iront dans la Corbeille. Rien n’est effacé pour de bon.\n\n\(HouseScan.preview(chosen.map(\.path)))",
            trash: chosen.map(\.path),
            destroy: [],
            snapshot: nil
        )
    }
}

@MainActor
@Observable
final class AppShelf {
    var apps: [AppRecord] = []
    var picked: Set<String> = []
    var selectedID: String?
    var leftovers: [String] = []
    var leftoverPicked: Set<String> = []
    var scanning = false
    var ready = false
    var checkingUpdates = false
    var macUpdate: String?
    var message = "Lecture des applications."
    @ObservationIgnored private var prepared = false

    var selected: AppRecord? { apps.first { $0.id == selectedID } }

    func prepare() {
        guard !prepared else { return }
        prepared = true
        Task { await scan() }
    }

    func scan() async {
        scanning = true
        let found = await Task.detached(priority: .utility) { HouseScan.apps() }.value
        apps = found
        picked = picked.intersection(Set(found.map(\.id)))
        scanning = false
        ready = true
        message = found.isEmpty ? "Aucune app dans Applications." : "\(found.count) apps. Retirer montre d’abord les restes."
        await refreshUpdates()
    }

    func select(_ app: AppRecord) {
        selectedID = app.id
        let found = HouseScan.leftovers(bundleID: app.bundleID, name: app.name)
        leftovers = found
        leftoverPicked = Set(found)
    }

    func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    func toggleLeftover(_ path: String) {
        if leftoverPicked.contains(path) { leftoverPicked.remove(path) } else { leftoverPicked.insert(path) }
    }

    func removalPending(includeApp: Bool, extra: [String]) -> HousePending? {
        guard let app = selected else { return nil }
        if app.path.hasPrefix("/System") || app.bundleID == Bundle.main.bundleIdentifier { return nil }
        var paths = extra
        if includeApp { paths.insert(app.path, at: 0) }
        guard !paths.isEmpty else { return nil }
        let title = includeApp ? "Retirer \(app.name) ?" : "Remettre \(app.name) à zéro ?"
        let message = includeApp
            ? "L’app et les restes cochés iront à la Corbeille. Vous pouvez tout reprendre.\n\n\(HouseScan.preview(paths))"
            : "Seules les préférences cochées iront à la Corbeille. L’app reste installée.\n\n\(HouseScan.preview(paths))"
        return HousePending(title: title, message: message, trash: paths, destroy: [], snapshot: nil)
    }

    private func refreshUpdates() async {
        checkingUpdates = true
        let targets = apps.filter { $0.sparkle != nil }.prefix(12)
        for app in targets {
            guard let feed = app.sparkle else { continue }
            let note = await HouseScan.sparkleNote(feed: feed, current: app.version)
            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].update = note
            }
        }
        macUpdate = await Task.detached(priority: .utility) { HouseScan.macUpdate() }.value
        checkingUpdates = false
    }
}

@MainActor
@Observable
final class BootStore {
    var items: [BootRecord] = []
    var snapshots: [SnapshotRecord] = []
    var scanning = false
    var ready = false
    var message = "Lecture de ce qui s’ouvre avec le Mac."
    var maintenance = ""
    @ObservationIgnored private var prepared = false

    func prepare() {
        guard !prepared else { return }
        prepared = true
        Task { await scan() }
    }

    func scan() async {
        scanning = true
        let found = await Task.detached(priority: .utility) { HouseScan.boot() }.value
        items = found.items
        snapshots = found.snapshots
        message = found.note
        scanning = false
        ready = true
    }

    func toggle(_ record: BootRecord) async {
        guard !record.locked else { return }
        let text = await Task.detached(priority: .utility) {
            HouseScan.setAgentEnabled(record.disabled, record: record)
        }.value
        maintenance = text
        await scan()
    }

    func flushDNS() async {
        maintenance = "Vidage du cache DNS…"
        maintenance = await Task.detached(priority: .utility) { HouseScan.flushDNS() }.value
    }

    func snapshotPending(_ snapshot: SnapshotRecord) -> HousePending {
        HousePending(
            title: "Supprimer cet instantané ?",
            message: "Time Machine garde cet instantané local (\(snapshot.label)). Le supprimer libère parfois de la place. Vos fichiers actuels restent.",
            trash: [],
            destroy: [],
            snapshot: snapshot.id
        )
    }
}
