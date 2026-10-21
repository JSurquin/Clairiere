import AppKit
import Foundation
import Observation
import SwiftUI

enum StaleBucket: String, Sendable {
    case remove
    case review
    case keep
}

struct StaleFile: Identifiable, Sendable {
    var id: String
    var token: String
    var name: String
    var path: String
    var folder: String
    var bytes: UInt64
    var months: Int
    var score: Int
    var precious: Bool
    var native: String
    var explanation: String
    var bucket: StaleBucket
}

private struct PlainError: Error {
    var message: String
}

@MainActor
@Observable
final class AdvisorStore {
    var items: [StaleFile] = []
    var picked: Set<String> = []
    var running = false
    var fraction: Double = -1
    var status = "Rien n’est lancé tant que vous n’appuyez pas sur Analyser."
    static let model = "qwen2.5:1.5b"

    func toggle(_ id: String) {
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    func pending(for ids: Set<String>) -> HousePending? {
        let chosen = items.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return nil }
        let bytes = chosen.reduce(UInt64(0)) { $0 + $1.bytes }
        return HousePending(
            title: "Mettre à la Corbeille ?",
            message: "\(Format.mem(bytes)) iront dans la Corbeille. Vous pouvez les reprendre.\n\n\(HouseScan.preview(chosen.map(\.path)))",
            trash: chosen.map(\.path),
            destroy: [],
            snapshot: nil
        )
    }

    func analyze() async {
        guard !running else { return }
        running = true
        fraction = -1
        let engineWasRunning = await Self.serverUp()
        defer {
            running = false
            if !engineWasRunning { Self.stopEngine() }
        }
        do {
            try await ensureEngine()
            try await ensureModel()
            status = "Lecture des fichiers pas ouverts depuis au moins 3 mois…"
            fraction = -1
            let found = await Task.detached(priority: .utility) { AdvisorScan.collect() }.value
            items = found
            if found.isEmpty {
                status = "Aucun vieux fichier à proposer. Les photos, la musique et la bibliothèque sont exclues."
                picked = []
                return
            }
            status = "Le modèle relit les noms…"
            await askModel(found)
            picked = Set(items.filter { $0.bucket == .remove }.map(\.id))
            let suggested = items.filter { $0.bucket == .remove }.count
            status = "\(items.count) fichiers anciens. \(suggested) sont proposés. Les documents et les photos ne sont pas cochés tout seuls."
            if !engineWasRunning {
                status += " Le modèle est refermé, pour ne pas garder de mémoire."
            }
        } catch let error as PlainError {
            status = error.message
        } catch {
            status = "Ça n’a pas abouti. Relancez l’analyse. Rien n’a été effacé."
        }
    }

    private func ensureEngine() async throws {
        if await Self.serverUp() { return }
        if let app = Self.installedApp() {
            status = "Ouverture d’Ollama…"
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            do {
                try await NSWorkspace.shared.openApplication(at: app, configuration: config)
            } catch {}
            if await Self.waitForServer() { return }
        }
        if Self.launchServe() {
            status = "Démarrage d’Ollama…"
            if await Self.waitForServer() { return }
        }
        status = "Installation d’Ollama, une seule fois…"
        let app = try await Self.installApp { value in
            let percent = Int((value * 100).rounded())
            Task { @MainActor in
                self.fraction = value
                self.status = "Téléchargement d’Ollama… \(percent) %"
            }
        }
        fraction = -1
        status = "Ouverture d’Ollama…"
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        try await NSWorkspace.shared.openApplication(at: app, configuration: config)
        guard await Self.waitForServer() else {
            throw PlainError(message: "Ollama est installé, mais il ne répond pas encore. S’il demande une autorisation, acceptez-la, puis relancez l’analyse.")
        }
    }

    private func ensureModel() async throws {
        if await Self.modelReady() { return }
        status = "Téléchargement du petit modèle, environ 1 Go, une seule fois…"
        fraction = 0
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/pull")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 1200
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": Self.model, "stream": true])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw PlainError(message: "Le modèle n’a pas pu être téléchargé. Vérifiez la connexion, puis relancez.")
        }
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let completed = Self.amount(object["completed"]), let total = Self.amount(object["total"]), total > 0 {
                fraction = min(1, completed / total)
                status = "Téléchargement du petit modèle… \(Int(fraction * 100)) %"
            } else if let text = object["status"] as? String, text.localizedCaseInsensitiveContains("success") {
                fraction = 1
            }
        }
        fraction = -1
        guard await Self.modelReady() else {
            throw PlainError(message: "Le modèle n’est pas prêt. Relancez l’analyse.")
        }
    }

    private func askModel(_ found: [StaleFile]) async {
        let batch = Array(found.prefix(40))
        let lines = batch.map { item in
            "\(item.token) | \(item.name) | \(item.folder) | \(Format.mem(item.bytes)) | \(item.months) mois | \(item.native)"
        }.joined(separator: "\n")
        let system = """
        Tu classes des fichiers macOS qui n’ont pas été ouverts depuis longtemps. \
        Réponds seulement en JSON : {"items":[{"id":"f1","verdict":"enlever","why":"phrase courte en français"}]}. \
        verdict vaut enlever, garder ou verifier. \
        enlever : installateur, temporaire, copie, capture d’écran, téléchargement inutile. \
        garder : travail, photo, vidéo ou document personnel. \
        verifier : doute. N’invente aucun id.
        """
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        let body: [String: Any] = [
            "model": Self.model,
            "stream": false,
            "format": "json",
            "keep_alive": 0,
            "options": ["temperature": 0.1, "num_predict": 900],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": lines]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? String else {
            status = "Le classement vient des noms et des dates. Le modèle n’a pas répondu, rien n’est coché au hasard."
            return
        }
        apply(content)
    }

    private func apply(_ content: String) {
        let trimmed = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["items"] as? [[String: Any]] else { return }
        for row in rows {
            guard let token = row["id"] as? String,
                  let verdict = (row["verdict"] as? String)?.lowercased(),
                  let index = items.firstIndex(where: { $0.token == token }) else { continue }
            if let why = row["why"] as? String, !why.isEmpty {
                items[index].explanation = why
            }
            switch verdict {
            case "enlever":
                if !items[index].precious && items[index].score >= 3 {
                    items[index].bucket = .remove
                }
            case "garder":
                items[index].bucket = .keep
            default:
                if items[index].bucket == .remove && items[index].score < 6 {
                    items[index].bucket = .review
                }
            }
        }
    }

    private static func amount(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func serverUp() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    private static func waitForServer() async -> Bool {
        for _ in 0..<40 {
            if await serverUp() { return true }
            try? await Task.sleep(for: .milliseconds(750))
        }
        return false
    }

    private static func modelReady() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(model)
    }

    private static func installedApp() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let urls = [
            URL(fileURLWithPath: "/Applications/Ollama.app"),
            home.appending(path: "Applications/Ollama.app")
        ]
        return urls.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    @ObservationIgnored private static var servePID: Int32 = 0

    @discardableResult
    private static func launchServe() -> Bool {
        let binaries = ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"]
        guard let binary = binaries.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        servePID = process.processIdentifier
        return true
    }

    private static func stopEngine() {
        if servePID > 1 {
            kill(servePID, SIGTERM)
            servePID = 0
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.ollama.ollama") {
            app.terminate()
        }
    }

    private static func installApp(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let url = URL(string: "https://ollama.com/download/Ollama-darwin.zip") else {
            throw PlainError(message: "L’adresse d’installation est invalide.")
        }
        let zip = try await ZipFetcher.fetch(url, progress: progress)
        let unpacked = FileManager.default.temporaryDirectory.appending(path: "ClairiereOllama")
        try? FileManager.default.removeItem(at: unpacked)
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let zipPath = zip.path
        let destPath = unpacked.path
        let unpackedOK = try await Task.detached {
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zipPath, destPath]
            try ditto.run()
            ditto.waitUntilExit()
            return ditto.terminationStatus == 0
        }.value
        guard unpackedOK, let app = findApp(in: unpacked) else {
            throw PlainError(message: "L’installation d’Ollama n’a pas abouti. Rien n’a été effacé.")
        }
        let apps = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let target = apps.appending(path: "Ollama.app")
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: app, to: target)
        return target
    }

    private static func findApp(in root: URL) -> URL? {
        if root.lastPathComponent == "Ollama.app" { return root }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == "Ollama.app" {
            return url
        }
        return nil
    }
}

private enum AdvisorScan {
    static func collect() -> [StaleFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey,
            .contentAccessDateKey, .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return [] }
        let homePrefix = home.path.hasSuffix("/") ? home.path : home.path + "/"
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        var found: [StaleFile] = []
        var seen = 0
        while let url = enumerator.nextObject() as? URL {
            seen += 1
            if seen > 70_000 { break }
            let name = url.lastPathComponent
            let rel = url.path.hasPrefix(homePrefix) ? String(url.path.dropFirst(homePrefix.count)) : url.path
            let top = rel.split(separator: "/").first.map(String.init) ?? name
            if top == "Library" || top == "Music" || top == "Pictures" || top.hasPrefix(".")
                || name.hasSuffix(".photoslibrary") || name.hasSuffix(".musiclibrary")
                || name == "node_modules" || name == ".git" || name == ".build" || name == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            if name.hasSuffix(".app") {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            let opened = values?.contentAccessDate ?? values?.contentModificationDate
            guard let opened, opened < cutoff else { continue }
            let bytes = UInt64(max(0, values?.totalFileAllocatedSize ?? 0))
            guard let item = describe(url: url, name: name, top: top, bytes: bytes, opened: opened) else { continue }
            found.append(item)
        }
        found.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.bytes > rhs.bytes
        }
        if found.count > 80 { found = Array(found.prefix(80)) }
        for index in found.indices {
            found[index].token = "f\(index + 1)"
        }
        return found
    }

    private static func describe(url: URL, name: String, top: String, bytes: UInt64, opened: Date) -> StaleFile? {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        let ext = url.pathExtension.lowercased()
        let days = Int(Date().timeIntervalSince(opened) / 86_400)
        let months = max(3, days / 30)
        var score = days >= 365 ? 3 : (days >= 180 ? 2 : 1)
        var reason = "Pas ouvert depuis \(months) mois"
        var strong = false
        if ["dmg", "pkg", "iso"].contains(ext) {
            score += 3
            reason = "Installateur pas ouvert depuis \(months) mois"
            strong = true
        } else if ["tmp", "crdownload", "part", "download"].contains(ext) {
            score += 4
            reason = "Téléchargement incomplet, depuis \(months) mois"
            strong = true
        } else if folded.contains("screenshot") || folded.contains("capture d") {
            score += 2
            reason = "Capture d’écran ancienne, \(months) mois"
            strong = true
        } else if folded.contains("copie") || folded.contains("copy") || folded.contains("(1)") || folded.contains("(2)") {
            score += 2
            reason = "Le nom indique une copie, pas ouverte depuis \(months) mois"
            strong = true
        } else if folded.contains("sans titre") || folded.contains("untitled") {
            score += 2
            reason = "Fichier sans vrai nom, depuis \(months) mois"
            strong = true
        } else if ["zip", "rar", "7z", "tar", "gz"].contains(ext) {
            score += 1
            reason = "Archive pas ouverte depuis \(months) mois"
        }
        if top == "Downloads" { score += 1 }
        if top == "Desktop" { score += 1 }
        let work: Set<String> = [
            "pdf", "pages", "numbers", "key", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "txt", "md", "rtf", "csv", "jpg", "jpeg", "png", "heic", "gif", "webp",
            "mov", "mp4", "m4v", "mp3", "wav", "m4a", "aac"
        ]
        let precious = work.contains(ext) && !strong
        if precious { score = min(score, 3) }
        let worth = strong || bytes >= 20 * 1_048_576 || score >= 4
        guard worth, bytes >= 200_000 || strong else { return nil }
        let bucket: StaleBucket = precious ? .review : (score >= 5 ? .remove : .review)
        return StaleFile(
            id: url.path,
            token: "",
            name: name,
            path: url.path,
            folder: HouseScan.pretty(url.deletingLastPathComponent().path),
            bytes: bytes,
            months: months,
            score: score,
            precious: precious,
            native: reason,
            explanation: reason,
            bucket: bucket
        )
    }
}

private final class ZipFetcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    nonisolated(unsafe) private var continuation: CheckedContinuation<URL, Error>?
    nonisolated(unsafe) private var progress: (@Sendable (Double) -> Void)?
    nonisolated(unsafe) private var session: URLSession?

    static func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let fetcher = ZipFetcher()
        return try await withCheckedThrowingContinuation { continuation in
            fetcher.continuation = continuation
            fetcher.progress = progress
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForResource = 1200
            let session = URLSession(configuration: configuration, delegate: fetcher, delegateQueue: nil)
            fetcher.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progress?(value)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let destination = FileManager.default.temporaryDirectory.appending(path: "Ollama-darwin.zip")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: PlainError(message: "Le téléchargement d’Ollama n’a pas pu être enregistré."))
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil, continuation != nil {
            continuation?.resume(throwing: PlainError(message: "Le téléchargement d’Ollama s’est interrompu. Vérifiez la connexion, puis relancez."))
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }
}

struct AdvisorView: View {
    @Environment(MemoryStore.self) private var store

    private var advisor: AdvisorStore { store.advisor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clairière regarde les fichiers qui n’ont pas été ouverts depuis trois mois. Elle lit le nom, le dossier, la taille et la date, sans ouvrir le contenu. Ensuite, un petit modèle installé sur ce Mac relit la liste, puis se décharge. Rien ne part sans votre accord, et les fichiers vont à la Corbeille.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(advisor.status)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if advisor.fraction >= 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.wash)
                                Capsule()
                                    .fill(Theme.leaf)
                                    .frame(width: max(8, geo.size.width * advisor.fraction))
                            }
                        }
                        .frame(height: 8)
                    }
                }
                Spacer(minLength: 12)
                ActionButton(
                    title: advisor.running ? "Analyse en cours…" : (advisor.items.isEmpty ? "Analyser" : "Relancer"),
                    tint: Theme.leaf,
                    prominent: true,
                    helpText: "Installe et ouvre Ollama si besoin, puis classe les fichiers anciens."
                ) {
                    Task { await store.advisor.analyze() }
                }
                .disabled(advisor.running)
                .opacity(advisor.running ? 0.55 : 1)
            }

            bucket("À mettre à la Corbeille", advisor.items.filter { $0.bucket == .remove }, empty: nil)
            bucket("À vérifier", advisor.items.filter { $0.bucket == .review }, empty: nil)
            bucket("Mieux les garder", advisor.items.filter { $0.bucket == .keep }, empty: nil)

            if !advisor.items.isEmpty {
                HStack {
                    Spacer()
                    ActionButton(
                        title: "Mettre la sélection à la Corbeille",
                        tint: Theme.leaf,
                        prominent: true,
                        helpText: "Demande confirmation. Les fichiers cochés vont à la Corbeille."
                    ) {
                        store.pending = advisor.pending(for: advisor.picked)
                    }
                    .disabled(advisor.picked.isEmpty || advisor.running)
                    .opacity(advisor.picked.isEmpty ? 0.45 : 1)
                }
            }
        }
    }

    private func bucket(_ title: String, _ items: [StaleFile], empty: String?) -> some View {
        let shown = items.filter {
            store.query.isEmpty || $0.name.localizedStandardContains(store.query) || $0.explanation.localizedStandardContains(store.query)
        }
        return Group {
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 18, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.text)
                    ForEach(shown) { item in
                        CheckLine(
                            title: item.name,
                            detail: "\(item.explanation) · \(item.folder)",
                            meta: Format.mem(item.bytes),
                            on: advisor.picked.contains(item.id),
                            focused: store.cursorID == "stale:\(item.id)",
                            actionTitle: "Corbeille"
                        ) {
                            store.advisor.toggle(item.id)
                        } action: {
                            store.pending = advisor.pending(for: [item.id])
                        }
                        .id("stale:\(item.id)")
                    }
                }
            }
        }
    }
}
