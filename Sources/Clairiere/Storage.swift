import Foundation
import Observation
import SwiftUI

struct DiskVolume: Sendable {
    var name: String
    var total: UInt64
    var available: UInt64

    var used: UInt64 { total > available ? total - available : 0 }

    static let empty = DiskVolume(name: "Disque", total: 0, available: 0)
}

struct CloudBatch: Identifiable, Sendable {
    var id: String
    var title: String
    var place: String
    var bytes: UInt64
    var fileCount: Int
    var paths: [String]
}

struct CloudScan: Sendable {
    var batches: [CloudBatch]
    var denied: [String]
}

enum ICloudScanner {
    static func roots() -> [String] {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let mobile = home.appendingPathComponent("Library/Mobile Documents")
        var result: [String] = []
        if let children = try? files.contentsOfDirectory(at: mobile, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for child in children where allowed(child.lastPathComponent) {
                var isDirectory: ObjCBool = false
                if files.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    result.append(child.path)
                }
            }
        }
        for name in ["Desktop", "Documents"] {
            let path = home.appendingPathComponent(name).resolvingSymlinksInPath().path
            let covered = result.contains { path == $0 || path.hasPrefix($0 + "/") }
            if !covered, files.fileExists(atPath: path) {
                result.append(path)
            }
        }
        return result
    }

    static func scan(roots: [String]) -> CloudScan {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .isDirectoryKey,
            .totalFileAllocatedSizeKey
        ]
        final class Bucket {
            var title: String
            var place: String
            var bytes: UInt64 = 0
            var paths: [String] = []
            init(title: String, place: String) {
                self.title = title
                self.place = place
            }
        }
        var groups: [String: Bucket] = [:]
        var denied: [String] = []

        for root in roots {
            let url = URL(fileURLWithPath: root)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                denied.append(placeName(root))
                continue
            }
            let place = placeName(root)
            while let item = enumerator.nextObject() as? URL {
                guard let values = try? item.resourceValues(forKeys: keys) else { continue }
                if values.isDirectory == true { continue }
                guard values.isUbiquitousItem == true else { continue }
                let allocated = UInt64(max(0, values.totalFileAllocatedSize ?? 0))
                guard allocated >= 8_192 else { continue }
                let relative = item.path.hasPrefix(root + "/") ? String(item.path.dropFirst(root.count + 1)) : item.lastPathComponent
                let parts = relative.split(separator: "/")
                let folder = parts.count >= 2 ? String(parts[0]) : "#root"
                let id = root + "/" + folder
                let bucket = groups[id] ?? Bucket(title: folderName(folder), place: place)
                bucket.bytes += allocated
                bucket.paths.append(item.path)
                groups[id] = bucket
            }
        }

        let batches = groups.map { id, bucket in
            CloudBatch(id: id, title: bucket.title, place: bucket.place, bytes: bucket.bytes, fileCount: bucket.paths.count, paths: bucket.paths)
        }.sorted { $0.bytes > $1.bytes }
        return CloudScan(batches: batches, denied: denied)
    }

    private static func allowed(_ name: String) -> Bool {
        let folded = name.lowercased()
        let banned = ["mail", "mobilesms", "photos", "photolibrary", "news"]
        return !banned.contains { folded.contains($0) }
    }

    static func placeName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name == "com~apple~CloudDocs" { return "iCloud Drive" }
        if name == "Desktop" { return "Bureau" }
        if name == "Documents" { return "Documents" }
        if let tail = name.split(separator: "~").last {
            return tail.replacingOccurrences(of: "-", with: " ")
        }
        return name
    }

    private static func folderName(_ raw: String) -> String {
        switch raw {
        case "Desktop": "Bureau"
        case "Documents": "Documents"
        case "Downloads": "Téléchargements"
        case "#root": "Fichiers sans dossier"
        default: raw
        }
    }
}

@MainActor
@Observable
final class DiskStore {
    var volume = DiskVolume.empty
    var batches: [CloudBatch] = []
    var scanning = false
    var evicting = false
    var progress = ""
    var message = "Les fichiers retirés restent dans iCloud. Il suffit de les ouvrir pour les récupérer."
    var denied: [String] = []
    var picked: Set<String> = []
    var confirmEvict = false
    var pendingPaths: [String] = []
    var pendingBytes: UInt64 = 0

    @ObservationIgnored private var prepared = false

    var downloadedBytes: UInt64 {
        batches.reduce(0) { $0 + $1.bytes }
    }

    func prepareVolume() {
        refreshVolume()
    }

    func prepare() {
        prepareVolume()
        guard !prepared else { return }
        prepared = true
        Task { await scan() }
    }

    func askEvict(_ batches: [CloudBatch]) {
        pendingPaths = batches.flatMap(\.paths)
        pendingBytes = batches.reduce(0) { $0 + $1.bytes }
        guard !pendingPaths.isEmpty else { return }
        confirmEvict = true
    }

    func toggleCloud(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    func refreshVolume() {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        volume = DiskVolume(
            name: values.volumeName ?? "Disque",
            total: UInt64(max(0, values.volumeTotalCapacity ?? 0)),
            available: UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
        )
    }

    func scan() async {
        guard !scanning, !evicting else { return }
        scanning = true
        batches = []
        denied = []
        let roots = ICloudScanner.roots().sorted { lhs, rhs in
            let lhsDrive = lhs.contains("CloudDocs")
            let rhsDrive = rhs.contains("CloudDocs")
            if lhsDrive != rhsDrive { return rhsDrive }
            return lhs < rhs
        }
        var collected: [CloudBatch] = []
        var blocked: [String] = []
        for (index, root) in roots.enumerated() {
            progress = "Lecture \(index + 1) sur \(roots.count) · \(ICloudScanner.placeName(root))"
            let found = await Task.detached(priority: .utility) {
                ICloudScanner.scan(roots: [root])
            }.value
            collected.append(contentsOf: found.batches)
            blocked.append(contentsOf: found.denied)
            batches = collected.sorted { $0.bytes > $1.bytes }
            denied = blocked
        }
        scanning = false
        progress = ""
        if batches.isEmpty {
            message = denied.isEmpty
                ? "Aucun fichier iCloud téléchargé n’occupe de place sur ce Mac."
                : "macOS ne laisse pas Clairière lire \(denied.joined(separator: ", ")). Dans Réglages Système, ouvrez Confidentialité et sécurité, puis Fichiers et dossiers, et autorisez Clairière."
        } else {
            message = "\(Format.mem(downloadedBytes)) de fichiers iCloud sont sur ce Mac. Les retirer libère le disque. Ils restent dans iCloud."
        }
    }

    func evict(paths: [String], bytes: UInt64) async {
        guard !evicting, !paths.isEmpty else { return }
        evicting = true
        let total = paths.count
        var removed = 0
        var failed = 0
        var index = 0
        while index < paths.count {
            let end = min(index + 40, paths.count)
            let slice = Array(paths[index..<end])
            let outcome = await Task.detached(priority: .utility) {
                var ok = 0
                var bad = 0
                for path in slice {
                    do {
                        try FileManager.default.evictUbiquitousItem(at: URL(fileURLWithPath: path))
                        ok += 1
                    } catch {
                        bad += 1
                    }
                }
                return (ok, bad)
            }.value
            removed += outcome.0
            failed += outcome.1
            index = end
            progress = "Retrait en cours, \(removed + failed) fichiers sur \(total)…"
        }
        evicting = false
        progress = ""
        refreshVolume()
        await scan()
        if removed == 0 {
            message = "macOS a refusé de retirer ces fichiers. Ils sont peut-être ouverts, ou déjà seulement dans iCloud."
        } else if failed == 0 {
            let left = downloadedBytes
            message = left > 0
                ? "\(Format.mem(bytes)) retirés de ce Mac. Ils restent dans iCloud. Il en reste \(Format.mem(left))."
                : "\(Format.mem(bytes)) retirés de ce Mac. Ils restent dans iCloud."
        } else {
            message = "\(removed) fichiers retirés de ce Mac. \(failed) sont restés, souvent parce qu’ils sont ouverts."
        }
    }
}

struct StorageView: View {
    @Environment(MemoryStore.self) private var store

    private var disk: DiskStore { store.disk }

    private var shownBatches: [CloudBatch] {
        disk.batches.filter {
            store.query.isEmpty || $0.title.localizedStandardContains(store.query) || $0.place.localizedStandardContains(store.query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            diskCard
            icloudCard
            FileLists()
        }
        .onAppear { disk.prepare() }
        .confirmationDialog(
            "Retirer ces fichiers de ce Mac ?",
            isPresented: Binding(get: { disk.confirmEvict }, set: { disk.confirmEvict = $0 }),
            titleVisibility: .visible
        ) {
            Button("Retirer de ce Mac") {
                let paths = disk.pendingPaths
                let bytes = disk.pendingBytes
                disk.pendingPaths = []
                disk.confirmEvict = false
                Task { await disk.evict(paths: paths, bytes: bytes) }
            }
            Button("Annuler", role: .cancel) {
                disk.pendingPaths = []
                disk.confirmEvict = false
            }
        } message: {
            Text("\(Format.mem(disk.pendingBytes)) sortiront de ce Mac, et rien d’autre. Ils restent dans iCloud, et reviennent si vous les ouvrez.")
        }
    }

    private var diskCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text(disk.volume.name)
                    .font(.system(size: 22, weight: .medium, design: .default))
                    .foregroundStyle(Theme.text)
                Text("Fermer une app libère la mémoire. Retirer un fichier iCloud libère le disque.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if disk.volume.total > 0 {
                    bar
                    HStack {
                        metric("Utilisé", Format.mem(disk.volume.used), Theme.gold)
                        metric("Disponible", Format.mem(disk.volume.available), Theme.leaf)
                        metric("Taille du disque", Format.mem(disk.volume.total), Theme.muted)
                    }
                }
            }
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            let ratio = disk.volume.total == 0 ? 0 : CGFloat(disk.volume.used) / CGFloat(disk.volume.total)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.wash)
                Capsule()
                    .fill(ratio > 0.9 ? Theme.coral : Theme.gold)
                    .frame(width: max(8, geo.size.width * min(1, ratio)))
            }
        }
        .frame(height: 14)
    }

    private var icloudCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fichiers iCloud sur ce Mac")
                            .font(.system(size: 18, weight: .medium, design: .default))
                            .foregroundStyle(Theme.text)
                        Text(disk.progress.isEmpty ? disk.message : disk.progress)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !disk.scanning && !disk.evicting {
                        Button("Actualiser") { Task { await disk.scan() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.leaf)
                    }
                }

                if disk.scanning && disk.batches.isEmpty {
                    Text("Lecture des dossiers iCloud…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }

                ForEach(shownBatches) { batch in
                    row(batch)
                        .id("cloud:\(batch.id)")
                }

                if !disk.batches.isEmpty {
                    HStack {
                        Spacer()
                        ActionButton(
                            title: "Retirer la sélection",
                            tint: Theme.gold,
                            prominent: !disk.picked.isEmpty,
                            helpText: "Retire de ce Mac seulement les dossiers cochés."
                        ) {
                            disk.askEvict(disk.batches.filter { disk.picked.contains($0.id) })
                        }
                        .disabled(disk.picked.isEmpty || disk.evicting)
                        .opacity(disk.picked.isEmpty ? 0.45 : 1)
                        ActionButton(
                            title: disk.evicting ? "Retrait…" : "Tout retirer de ce Mac",
                            tint: Theme.leaf,
                            prominent: true,
                            helpText: "Retire toutes les copies iCloud listées. Rien n’est supprimé d’iCloud."
                        ) {
                            disk.askEvict(shownBatches)
                        }
                        .disabled(disk.evicting || disk.scanning)
                    }
                }
            }
        }
    }

    private func row(_ batch: CloudBatch) -> some View {
        HStack(spacing: 10) {
            Button {
                disk.toggleCloud(batch.id)
            } label: {
                Image(systemName: disk.picked.contains(batch.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(disk.picked.contains(batch.id) ? Theme.leaf : Theme.muted)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(batch.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(batch.place) · \(Format.count(batch.fileCount, one: "fichier", many: "fichiers"))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(Format.mem(batch.bytes))
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(Theme.text)
            ActionButton(title: "Retirer", tint: Theme.leaf, prominent: true, helpText: "Retire ce dossier de ce Mac. Il reste dans iCloud.") {
                disk.askEvict([batch])
            }
            .disabled(disk.evicting)
        }
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(store.cursorID == "cloud:\(batch.id)" ? Theme.leaf : Color.clear, lineWidth: 1.5)
        )
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
