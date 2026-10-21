import CryptoKit
import Darwin
import Foundation

struct JunkPart: Identifiable, Sendable, Hashable {
    var path: String
    var name: String
    var bytes: UInt64
    var id: String { path }
}

struct JunkItem: Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    var detail: String
    var bytes: UInt64
    var paths: [String]
    var suggested: Bool
    var permanent: Bool
    var parts: [JunkPart] = []
}

struct FileItem: Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    var path: String
    var bytes: UInt64
    var note: String
    var section: String
}

struct AppRecord: Identifiable, Sendable, Hashable {
    var id: String
    var name: String
    var path: String
    var bundleID: String
    var version: String
    var bytes: UInt64
    var lastUsed: Date?
    var sparkle: String?
    var quarantined: Bool
    var update: String?
}

struct BootRecord: Identifiable, Sendable, Hashable {
    var id: String
    var name: String
    var detail: String
    var path: String
    var label: String
    var disabled: Bool
    var locked: Bool
    var warning: String?
}

struct SnapshotRecord: Identifiable, Sendable, Hashable {
    var id: String
    var label: String
}

struct FileScanResult: Sendable {
    var large: [FileItem]
    var folders: [FileItem]
    var downloads: [FileItem]
    var duplicates: [FileItem]
    var note: String
}

struct BootScanResult: Sendable {
    var items: [BootRecord]
    var snapshots: [SnapshotRecord]
    var note: String
}

struct HousePending: Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var trash: [String]
    var destroy: [String]
    var snapshot: String?
}

enum HouseScan {
    static func cleanup() -> [JunkItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var items: [JunkItem] = []
        let browserNames: Set<String> = [
            "com.apple.Safari", "Google", "Firefox", "com.microsoft.edgemac",
            "company.thebrowser.Browser", "BraveSoftware"
        ]
        let caches = home.appending(path: "Library/Caches")
        let cacheChildren = children(caches).filter { !browserNames.contains($0.lastPathComponent) }
        if let item = folderItem(
            id: "caches",
            title: "Caches",
            detail: "Fichiers que les apps recréent toutes seules. Les caches des navigateurs sont à part.",
            urls: cacheChildren,
            suggested: true,
            permanent: false
        ) { items.append(item) }

        if let item = folderItem(
            id: "logs",
            title: "Journaux",
            detail: "Comptes-rendus d’apps. Ils se recréent si l’app en a encore besoin.",
            urls: children(home.appending(path: "Library/Logs")),
            suggested: true,
            permanent: false
        ) { items.append(item) }

        let orphans = orphanPreferences(home: home)
        let orphanParts = sizedParts(orphans)
        if !orphanParts.isEmpty {
            items.append(JunkItem(
                id: "orphans",
                title: "Préférences sans app",
                detail: "Réglages d’apps qui ne sont plus installées. Rien ne les recrée.",
                bytes: orphanParts.reduce(0) { $0 + $1.bytes },
                paths: orphanParts.map(\.path),
                suggested: false,
                permanent: false,
                parts: orphanParts.count > 1 ? orphanParts : []
            ))
        }

        let trash = children(home.appending(path: ".Trash"))
        if let item = folderItem(
            id: "trash",
            title: "Corbeille du Mac",
            detail: "Vider la corbeille supprime ces fichiers pour de bon.",
            urls: trash,
            suggested: true,
            permanent: true
        ) { items.append(item) }

        let mailTrash = mailTrashURLs(home: home)
        if let item = folderItem(
            id: "mail-trash",
            title: "Corbeille de Mail",
            detail: "Messages déjà mis à la corbeille dans Mail. Les vider est définitif.",
            urls: mailTrash,
            suggested: false,
            permanent: true
        ) { items.append(item) }

        for url in downloads(home: home, ext: "dmg").prefix(40) {
            items.append(JunkItem(
                id: "dmg:\(url.path)",
                title: url.lastPathComponent,
                detail: "Image disque dans Téléchargements. Elle n’est pas cochée : vous l’avez peut-être gardée.",
                bytes: sizeOf(url),
                paths: [url.path],
                suggested: false,
                permanent: false
            ))
        }

        items.append(contentsOf: reviewFolders(home: home))
        items.append(contentsOf: privacyItems(home: home))
        return items.filter { $0.bytes > 0 || !$0.paths.isEmpty }
    }

    static func files() -> FileScanResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .isDirectoryKey, .isRegularFileKey,
            .contentAccessDateKey, .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return FileScanResult(large: [], folders: [], downloads: [], duplicates: [], note: "La maison n’a pas pu être lue.")
        }

        var folderBytes: [String: UInt64] = [:]
        var large: [FileItem] = []
        var downloads: [FileItem] = []
        var dupes: [UInt64: [(path: String, date: Date)]] = [:]
        var seen = 0
        var partial = false
        let stale = Date().addingTimeInterval(-30 * 24 * 3600)
        let homePrefix = home.path.hasSuffix("/") ? home.path : home.path + "/"

        while let url = enumerator.nextObject() as? URL {
            seen += 1
            if seen > 80_000 {
                partial = true
                break
            }
            let name = url.lastPathComponent
            let rel = url.path.hasPrefix(homePrefix) ? String(url.path.dropFirst(homePrefix.count)) : url.path
            let top = rel.split(separator: "/").first.map(String.init) ?? name
            if top == "Library" || top == "Music" || top.hasPrefix(".")
                || name.hasSuffix(".photoslibrary") || name.hasSuffix(".musiclibrary") {
                enumerator.skipDescendants()
                continue
            }
            if name == "node_modules" || name == ".git" || name == ".build" || name == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: keys)
            let allocated = UInt64(max(0, values?.totalFileAllocatedSize ?? 0))
            if values?.isDirectory == true {
                folderBytes[top, default: 0] += allocated
                continue
            }
            guard values?.isRegularFile == true else { continue }
            folderBytes[top, default: 0] += allocated
            let insideApp = rel.split(separator: "/").contains { $0.hasSuffix(".app") }
            let modified = values?.contentModificationDate ?? .distantPast
            let accessed = values?.contentAccessDate ?? modified
            if top == "Downloads" && accessed < stale && allocated >= 1_048_576 && downloads.count < 60 {
                downloads.append(FileItem(
                    id: url.path,
                    title: name,
                    path: url.path,
                    bytes: allocated,
                    note: "Téléchargé il y a plus d’un mois. Rien n’est coché.",
                    section: "old"
                ))
            } else if !insideApp && allocated >= 50 * 1_048_576 && large.count < 400 {
                large.append(FileItem(
                    id: url.path,
                    title: name,
                    path: url.path,
                    bytes: allocated,
                    note: pretty(url.path),
                    section: "large"
                ))
            }
            let dupTop = top == "Desktop" || top == "Documents" || top == "Downloads" || top == "Bureau"
            if dupTop && !insideApp && allocated >= 1_048_576 && allocated < 4_000_000_000 {
                dupes[allocated, default: []].append((url.path, modified))
            }
        }

        large.sort { $0.bytes > $1.bytes }
        if large.count > 80 { large = Array(large.prefix(80)) }
        downloads.sort { $0.bytes > $1.bytes }

        let folders = folderBytes
            .filter { $0.value >= 50 * 1_048_576 }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { name, bytes in
                FileItem(
                    id: "folder:\(name)",
                    title: folderTitle(name),
                    path: home.appending(path: name).path,
                    bytes: bytes,
                    note: "Dossier de votre maison. La bibliothèque, la musique et les photos restent de côté.",
                    section: "folder"
                )
            }

        let duplicates = duplicateItems(from: dupes)
        var note = "Fichiers de plus de 50 Mo, dossiers lourds, téléchargements de plus d’un mois, et copies."
        if partial {
            note = "Lecture arrêtée après beaucoup de fichiers. Ce qui est déjà gros est affiché. Les dossiers de code ne sont pas comptés."
        }
        return FileScanResult(large: large, folders: folders, downloads: downloads, duplicates: duplicates, note: note)
    }

    static func apps() -> [AppRecord] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls: [URL] = []
        collectApps(in: URL(fileURLWithPath: "/Applications"), into: &urls, depth: 0)
        collectApps(in: home.appending(path: "Applications"), into: &urls, depth: 0)
        var seen: Set<String> = []
        var records: [AppRecord] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            let plist = url.appending(path: "Contents/Info.plist")
            let dict = NSDictionary(contentsOf: plist) as? [String: Any] ?? [:]
            let name = (dict["CFBundleDisplayName"] as? String)
                ?? (dict["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let bundleID = dict["CFBundleIdentifier"] as? String ?? ""
            let version = dict["CFBundleShortVersionString"] as? String ?? ""
            let sparkle = dict["SUFeedURL"] as? String
            let accessed = try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
            records.append(AppRecord(
                id: path,
                name: name,
                path: path,
                bundleID: bundleID,
                version: version,
                bytes: measure(url, cap: 40_000),
                lastUsed: accessed,
                sparkle: sparkle,
                quarantined: quarantined(path),
                update: nil
            ))
        }
        return records.sorted { $0.bytes > $1.bytes }
    }

    static func leftovers(bundleID: String, name: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appending(path: "Library")
        let folders = [
            "Application Support/\(bundleID)",
            "Application Support/\(name)",
            "Caches/\(bundleID)",
            "Preferences/\(bundleID).plist",
            "Logs/\(bundleID)",
            "Saved Application State/\(bundleID).savedState",
            "Containers/\(bundleID)",
            "HTTPStorages/\(bundleID)",
            "WebKit/\(bundleID)"
        ]
        return folders.map { library.appending(path: $0).path }.filter { FileManager.default.fileExists(atPath: $0) }
    }

    static func sparkleNote(feed: String, current: String) async -> String? {
        guard let url = URL(string: feed) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Clairiere", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let xml = String(data: data, encoding: .utf8) else { return nil }
        let version = firstMatch(xml, pattern: "sparkle:shortVersionString=\"([^\"]+)\"")
            ?? firstMatch(xml, pattern: "sparkle:version=\"([^\"]+)\"")
        guard let version, version != current, !current.isEmpty else { return nil }
        return "Version \(version) disponible. Clairière ne l’installe pas."
    }

    static func pageLink(feed: String) async -> URL? {
        guard let url = URL(string: feed) else { return URL(string: feed) }
        let request = URLRequest(url: url, timeoutInterval: 8)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let xml = String(data: data, encoding: .utf8) else { return url }
        if let link = firstMatch(xml, pattern: "<link>([^<]+)</link>"), let page = URL(string: link) {
            return page
        }
        return url
    }

    static func macUpdate() -> String? {
        let text = shell("/usr/sbin/softwareupdate", ["-l"], timeout: 28)
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if folded.contains("no new software") || folded.contains("aucune") { return "macOS est à jour." }
        if folded.contains("label") || folded.contains("software update found") || folded.contains("mise a jour") {
            let line = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty && !$0.hasPrefix("Software Update") }
            if let line, !line.isEmpty { return "Mise à jour macOS : \(line)" }
            return "Une mise à jour macOS est disponible."
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return nil
    }

    static func boot() -> BootScanResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var items: [BootRecord] = []
        let userAgents = home.appending(path: "Library/LaunchAgents")
        let disabledDir = home.appending(path: "Library/Application Support/Clairiere/Agents désactivés")
        items.append(contentsOf: agentRecords(in: userAgents, disabled: false))
        items.append(contentsOf: agentRecords(in: disabledDir, disabled: true))
        if let system = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Library/LaunchAgents"),
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) {
            for url in system where url.pathExtension == "plist" {
                if let record = agentRecord(url: url, disabled: false, forceLocked: true) {
                    items.append(record)
                }
            }
        }
        items.append(contentsOf: loginItems())
        let snapshots = timeMachineSnapshots()
        let warnings = items.filter { $0.warning != nil }.count
        let note = warnings == 0
            ? "Désactiver un agent le déplace. Réactiver le remet. macOS reste intouchable."
            : "\(warnings) élément\(warnings > 1 ? "s" : "") mérite\(warnings > 1 ? "nt" : "") un coup d’œil. Ce n’est pas un antivirus."
        return BootScanResult(items: items, snapshots: snapshots, note: note)
    }

    static func setAgentEnabled(_ enabled: Bool, record: BootRecord) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let agents = home.appending(path: "Library/LaunchAgents")
        let disabledDir = home.appending(path: "Library/Application Support/Clairiere/Agents désactivés")
        try? FileManager.default.createDirectory(at: disabledDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: record.path)
        let destination = (enabled ? agents : disabledDir).appending(path: source.lastPathComponent)
        let uid = getuid()
        if !enabled {
            _ = shell("/bin/launchctl", ["bootout", "gui/\(uid)", record.path], timeout: 8)
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            return "Le fichier n’a pas bougé. Il est peut-être ouvert."
        }
        if enabled {
            _ = shell("/bin/launchctl", ["bootstrap", "gui/\(uid)", destination.path], timeout: 8)
            return "\(record.name) se relancera. S’il ne revient pas, rouvrez la session."
        }
        return "\(record.name) est désactivé. Il reviendra si vous le réactivez."
    }

    static func flushDNS() -> String {
        _ = shell("/usr/bin/dscacheutil", ["-flushcache"], timeout: 8)
        _ = shell("/usr/bin/killall", ["-HUP", "mDNSResponder"], timeout: 8)
        return "Le cache DNS a été vidé."
    }

    static func deleteSnapshot(_ name: String) -> String {
        let text = shell("/usr/bin/tmutil", ["deletelocalsnapshots", name], timeout: 20)
        if text.localizedCaseInsensitiveContains("error") || text.localizedCaseInsensitiveContains("failed") {
            return "macOS a refusé de supprimer cet instantané. Time Machine le garde souvent tant qu’il sert."
        }
        return "Instantané retiré : \(name)."
    }

    static func apply(trash: [String], destroy: [String]) -> String {
        let fm = FileManager.default
        var trashed = 0
        var removed = 0
        var failed = 0
        for path in trash where fm.fileExists(atPath: path) {
            do {
                try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                trashed += 1
            } catch {
                failed += 1
            }
        }
        for path in destroy where fm.fileExists(atPath: path) {
            do {
                try fm.removeItem(at: URL(fileURLWithPath: path))
                removed += 1
            } catch {
                failed += 1
            }
        }
        if trashed == 0 && removed == 0 {
            return failed == 0 ? "Rien à enlever." : "macOS a refusé. Les fichiers sont peut-être ouverts."
        }
        var parts: [String] = []
        if trashed > 0 { parts.append("\(trashed) mis à la Corbeille") }
        if removed > 0 { parts.append("\(removed) supprimés pour de bon") }
        if failed > 0 { parts.append("\(failed) restés en place") }
        return parts.joined(separator: ". ") + "."
    }

    static func preview(_ paths: [String]) -> String {
        let names = paths.prefix(6).map { URL(fileURLWithPath: $0).lastPathComponent }
        var text = names.joined(separator: "\n")
        if paths.count > 6 { text += "\net \(paths.count - 6) autres" }
        return text
    }

    static func pretty(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "Maison" }
        if path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        return path
    }

    private static func reviewFolders(home: URL) -> [JunkItem] {
        let specs: [(String, String, String)] = [
            ("xcode-derived", "Données de construction Xcode", "Library/Developer/Xcode/DerivedData"),
            ("xcode-archives", "Archives Xcode", "Library/Developer/Xcode/Archives"),
            ("xcode-devices", "Données d’appareils Xcode", "Library/Developer/Xcode/iOS DeviceSupport"),
            ("ios-backups", "Sauvegardes iPhone", "Library/Application Support/MobileSync/Backup"),
            ("mail-downloads", "Pièces jointes Mail déjà téléchargées", "Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        ]
        return specs.compactMap { id, title, relative in
            let url = home.appending(path: relative)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let bytes = measure(url, cap: 20_000)
            guard bytes > 0 else { return nil }
            return JunkItem(
                id: id,
                title: title,
                detail: "À vérifier avant. Rien n’est coché. Photos, musique et mots de passe ne sont pas ici.",
                bytes: bytes,
                paths: [url.path],
                suggested: false,
                permanent: false,
                parts: inside(url)
            )
        }
    }

    private static func privacyItems(home: URL) -> [JunkItem] {
        let specs: [(String, String, String)] = [
            ("safari-cache", "Cache de Safari", "Library/Caches/com.apple.Safari"),
            ("chrome-cache", "Cache de Chrome", "Library/Caches/Google/Chrome"),
            ("firefox-cache", "Cache de Firefox", "Library/Caches/Firefox"),
            ("edge-cache", "Cache d’Edge", "Library/Caches/com.microsoft.edgemac"),
            ("safari-history", "Historique de Safari", "Library/Safari/History.db"),
            ("chrome-history", "Historique de Chrome", "Library/Application Support/Google/Chrome/Default/History")
        ]
        return specs.compactMap { id, title, relative in
            let url = home.appending(path: relative)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let bytes = sizeOf(url) > 0 ? sizeOf(url) : measure(url, cap: 8_000)
            guard bytes > 0 else { return nil }
            let history = id.hasSuffix("history")
            return JunkItem(
                id: id,
                title: title,
                detail: history
                    ? "Efface l’historique de navigation. Les mots de passe et le trousseau restent."
                    : "Cache du navigateur. Il se recrée. Les mots de passe restent.",
                bytes: bytes,
                paths: [url.path],
                suggested: false,
                permanent: false,
                parts: history ? [] : inside(url)
            )
        }
    }

    private static func duplicateItems(from groups: [UInt64: [(path: String, date: Date)]]) -> [FileItem] {
        var output: [FileItem] = []
        let candidates = groups.filter { $0.value.count > 1 && $0.value.count <= 8 }.sorted { $0.key > $1.key }
        for (_, files) in candidates.prefix(30) {
            let hashed = Dictionary(grouping: files) { fingerprint(path: $0.path, size: 0) }
            for (_, copies) in hashed where copies.count > 1 {
                let ordered = copies.sorted { $0.date > $1.date }
                let keeper = URL(fileURLWithPath: ordered[0].path).lastPathComponent
                for copy in ordered.dropFirst() where output.count < 40 {
                    let url = URL(fileURLWithPath: copy.path)
                    output.append(FileItem(
                        id: copy.path,
                        title: url.lastPathComponent,
                        path: copy.path,
                        bytes: sizeOf(url),
                        note: "Même contenu qu’une copie plus récente (\(keeper)). La plus récente est gardée.",
                        section: "duplicate"
                    ))
                }
            }
        }
        return output
    }

    private static func fingerprint(path: String, size: UInt64) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return path }
        defer { try? handle.close() }
        let measured = size > 0 ? size : (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        if measured <= 80_000_000, let data = try? handle.readToEnd() {
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        let head = (try? handle.read(upToCount: 1_048_576)) ?? Data()
        if measured > 1_048_576 {
            try? handle.seek(toOffset: measured - 1_048_576)
        }
        let tail = (try? handle.readToEnd()) ?? Data()
        var blob = head
        blob.append(tail)
        let digest = SHA256.hash(data: blob)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func folderItem(id: String, title: String, detail: String, urls: [URL], suggested: Bool, permanent: Bool) -> JunkItem? {
        let parts = sizedParts(urls)
        guard !parts.isEmpty else { return nil }
        let bytes = parts.reduce(UInt64(0)) { $0 + $1.bytes }
        return JunkItem(
            id: id,
            title: title,
            detail: detail,
            bytes: bytes,
            paths: parts.map(\.path),
            suggested: suggested,
            permanent: permanent,
            parts: parts.count > 1 ? parts : []
        )
    }

    /// Dossiers ou fichiers à l’intérieur, du plus lourd au plus léger.
    private static func inside(_ url: URL) -> [JunkPart] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        let parts = sizedParts(children(url))
        return parts.count > 1 ? parts : []
    }

    private static func sizedParts(_ urls: [URL]) -> [JunkPart] {
        urls.compactMap { url in
            let bytes = sizeOf(url)
            guard bytes > 0 else { return nil }
            return JunkPart(path: url.path, name: readableName(url.lastPathComponent), bytes: bytes)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private static func readableName(_ raw: String) -> String {
        let stem = raw.hasSuffix(".plist") ? String(raw.dropLast(".plist".count)) : raw
        guard stem.contains(".") else { return stem }
        let skip: Set<String> = ["com", "org", "net", "io", "co", "app", "me", "client", "helper", "mac", "osx", "desktop", "agent"]
        let bits = stem.split(separator: ".").map(String.init).filter { bit in
            !skip.contains(bit.lowercased()) && bit.count > 1
        }
        guard let pick = bits.last else { return stem }
        if pick == pick.lowercased() {
            return pick.prefix(1).uppercased() + pick.dropFirst()
        }
        return pick
    }

    private static func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    private static func downloads(home: URL, ext: String) -> [URL] {
        let folder = home.appending(path: "Downloads")
        return children(folder).filter { $0.pathExtension.lowercased() == ext }
    }

    private static func orphanPreferences(home: URL) -> [URL] {
        let prefs = home.appending(path: "Library/Preferences")
        let installed = bundleIDs()
        return children(prefs).filter { url in
            guard url.pathExtension == "plist" else { return false }
            let id = url.deletingPathExtension().lastPathComponent
            if id.hasPrefix("com.apple.") || id.hasPrefix("loginwindow") || id.contains("clairiere") { return false }
            return !installed.contains(id)
        }
    }

    private static func bundleIDs() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls: [URL] = []
        collectApps(in: URL(fileURLWithPath: "/Applications"), into: &urls, depth: 0)
        collectApps(in: home.appending(path: "Applications"), into: &urls, depth: 0)
        var ids: Set<String> = []
        for url in urls {
            let dict = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist"))
            if let id = dict?["CFBundleIdentifier"] as? String { ids.insert(id) }
        }
        return ids
    }

    private static func mailTrashURLs(home: URL) -> [URL] {
        let mail = home.appending(path: "Library/Mail")
        guard let enumerator = FileManager.default.enumerator(at: mail, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var found: [URL] = []
        var seen = 0
        while let url = enumerator.nextObject() as? URL {
            seen += 1
            if seen > 4_000 { break }
            let name = url.lastPathComponent
            if name == "Deleted Messages" || name == "Trash.mbox" || name == "Deleted Messages.mbox" {
                found.append(url)
                enumerator.skipDescendants()
            }
        }
        return found
    }

    private static func collectApps(in dir: URL, into urls: inout [URL], depth: Int) {
        guard depth < 3, let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }
        for url in entries {
            if url.pathExtension == "app" {
                urls.append(url)
            } else if depth < 2 {
                var directory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
                    collectApps(in: url, into: &urls, depth: depth + 1)
                }
            }
        }
    }

    private static func agentRecords(in dir: URL, disabled: Bool) -> [BootRecord] {
        children(dir).compactMap { url in
            guard url.pathExtension == "plist" else { return nil }
            return agentRecord(url: url, disabled: disabled, forceLocked: false)
        }
    }

    private static func agentRecord(url: URL, disabled: Bool, forceLocked: Bool) -> BootRecord? {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        var program = dict["Program"] as? String ?? ""
        if program.isEmpty, let args = dict["ProgramArguments"] as? [String] {
            program = args.first ?? ""
        }
        let locked = forceLocked || !FileManager.default.isWritableFile(atPath: url.path) || url.path.hasPrefix("/System")
        return BootRecord(
            id: url.path,
            name: label,
            detail: program.isEmpty ? HouseScan.pretty(url.path) : HouseScan.pretty(program),
            path: url.path,
            label: label,
            disabled: disabled,
            locked: locked,
            warning: suspicion(program: program, label: label)
        )
    }

    private static func suspicion(program: String, label: String) -> String? {
        let blob = (program + " " + label).lowercased()
        let adware = ["mackeeper", "mackeeper", "advanced mac cleaner", "mac auto fixer", "genioo"]
        if adware.contains(where: { blob.contains($0) }) {
            return "Ce nom revient souvent dans des pubs agressives. Vérifiez avant de le laisser démarrer."
        }
        if program.contains("/private/tmp") || program.contains("/tmp/") || program.contains("/Downloads/") {
            return "Le programme est dans un dossier inhabituel pour un démarrage."
        }
        if !program.isEmpty && !FileManager.default.fileExists(atPath: program) {
            return "Le programme indiqué n’est plus là."
        }
        return nil
    }

    private static func loginItems() -> [BootRecord] {
        let text = shell("/usr/bin/sfltool", ["dumpbtm"], timeout: 8)
        guard !text.isEmpty else { return [] }
        var items: [BootRecord] = []
        var name = ""
        var url = ""
        func flush() {
            guard !name.isEmpty else { return }
            let path = url.hasPrefix("file://") ? (URL(string: url)?.path ?? url) : url
            items.append(BootRecord(
                id: "login:\(name):\(path)",
                name: name,
                detail: "S’ouvre avec votre session. Pour le retirer, ouvrez Réglages Système.",
                path: path,
                label: name,
                disabled: false,
                locked: true,
                warning: nil
            ))
            name = ""
            url = ""
        }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { flush(); continue }
            if line.hasPrefix("Name:") { name = line.dropFirst(5).trimmingCharacters(in: .whitespaces).description }
            if line.hasPrefix("URL:") { url = line.dropFirst(4).trimmingCharacters(in: .whitespaces).description }
        }
        flush()
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func timeMachineSnapshots() -> [SnapshotRecord] {
        let text = shell("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 12)
        return text.split(separator: "\n").compactMap { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            guard value.contains("com.apple") else { return nil }
            let date = value.replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
            return SnapshotRecord(id: date, label: date.replacingOccurrences(of: "-", with: " "))
        }
    }

    private static func folderTitle(_ name: String) -> String {
        switch name {
        case "Downloads": "Téléchargements"
        case "Desktop": "Bureau"
        case "Documents": "Documents"
        case "Movies": "Films"
        case "Pictures": "Images"
        case "Applications": "Applications"
        case "Public": "Public"
        default: name
        }
    }

    private static func sizeOf(_ url: URL) -> UInt64 {
        if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]) {
            if values.isDirectory == true { return measure(url, cap: 12_000) }
            if let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                return UInt64(max(0, allocated))
            }
        }
        return measure(url, cap: 12_000)
    }

    private static func measure(_ url: URL, cap: Int) -> UInt64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: []) else { return 0 }
        var total: UInt64 = 0
        var seen = 0
        while let file = enumerator.nextObject() as? URL {
            seen += 1
            if seen > cap { break }
            let values = try? file.resourceValues(forKeys: keys)
            if values?.isDirectory != true {
                total += UInt64(max(0, values?.totalFileAllocatedSize ?? 0))
            }
        }
        return total
    }

    private static func quarantined(_ path: String) -> Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let hit = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[hit])
    }

    private static func shell(_ launch: String, _ args: [String], timeout: TimeInterval) -> String {
        guard FileManager.default.isExecutableFile(atPath: launch) else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
