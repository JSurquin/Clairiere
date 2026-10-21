import AppKit
import Darwin
import Foundation
import Observation

@MainActor
@Observable
final class MemoryStore {
    var snapshot: SystemSnapshot = .empty
    var groups: [AppGroup] = []
    var lens: Lens = .home {
        didSet { if lens != oldValue { alignCursor() } }
    }
    var memoryFocus: MemoryFocus = .grouped {
        didSet { if memoryFocus != oldValue { alignCursor() } }
    }
    var query = ""
    var showTraces = false
    var selectedID: String?
    var cursorID: String?
    var focusToken = 0
    var releaseSearch = 0
    var browsingResults = false
    var showHelp = false
    var showLighten = false
    var lightenPicked: Set<String> = []
    var pending: HousePending?
    var status = "Lecture de la mémoire…"
    let disk = DiskStore()
    let cleanup = CleanupStore()
    let files = FileStore()
    let shelf = AppShelf()
    let boot = BootStore()
    let advisor = AdvisorStore()
    var forceRequest: ForceRequest?
    var isNudging = false
    var nudgeReport: String?
    var frontmostPID: Int32 = 0
    var sampleCount = 0
    static let appearanceKey = "clairiere.light"
    var lightTheme = UserDefaults.standard.bool(forKey: MemoryStore.appearanceKey)

    init() {
        Theme.store = self
    }

    func setAppearance(light: Bool) {
        lightTheme = light
        UserDefaults.standard.set(light, forKey: Self.appearanceKey)
    }

    @ObservationIgnored private var history: [String: [SamplePoint]] = [:]
    @ObservationIgnored private var pidHistory: [Int32: [SamplePoint]] = [:]
    @ObservationIgnored private var ticks: [Int32: TickMark] = [:]
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var publishedFront: Int32 = -1

    var selected: AppGroup? {
        guard let selectedID else { return nil }
        return groups.first { $0.id == selectedID }
    }

    var band: PressureBand {
        guard snapshot.physical > 0 else { return .calm }
        let ratio = Double(snapshot.used) / Double(snapshot.physical)
        if snapshot.pressureLevel >= 4 || snapshot.swapUsed > 4_000_000_000 || ratio > 0.92 {
            return .critical
        }
        if snapshot.pressureLevel >= 2 || snapshot.swapUsed > 1_000_000_000 || ratio > 0.72 {
            return .tense
        }
        return .calm
    }

    var reading: String {
        guard snapshot.physical > 0 else { return "Lecture en cours." }
        if snapshot.swapUsed > 3_000_000_000 {
            return "macOS a mis \(Format.mem(snapshot.swapUsed)) sur le disque pour continuer. Fermer une grosse app rend de la mémoire."
        }
        if snapshot.compressed > 500_000_000 {
            return "macOS compresse déjà des données pour que tout tienne. Fermer une grosse app libère vraiment de la place."
        }
        return "Il reste de la mémoire libre. Les fichiers en cache se libèrent tout seuls quand une app en a besoin."
    }

    var lever: AppGroup? {
        groups.filter(\.canQuit).max { $0.footprint < $1.footprint }
    }

    var leverLine: String {
        if let lever {
            return "Le plus efficace : fermer \(lever.name) (\(Format.mem(lever.footprint)))."
        }
        return "Les plus gros morceaux font tourner macOS. Mieux vaut les laisser."
    }

    var listedFootprint: UInt64 {
        groups.reduce(0) { $0 + $1.footprint }
    }

    var nudgeAllowed: Bool {
        snapshot.physical > 0
            && snapshot.pressureLevel <= 1
            && snapshot.available > 4_000_000_000
            && snapshot.swapUsed < 1_500_000_000
            && snapshot.used * 10 < snapshot.physical * 7
    }

    var nudgeReason: String {
        if nudgeAllowed {
            return "Cette option demande à macOS de compresser des caches. L’écran peut se figer une ou deux secondes. Aucun fichier n’est supprimé."
        }
        if snapshot.swapUsed > 1_500_000_000 {
            return "Le disque sert déjà de mémoire de secours (\(Format.mem(snapshot.swapUsed))). Le plus utile est de fermer une app."
        }
        if snapshot.pressureLevel > 1 {
            return "La mémoire est déjà tendue. Cette option attend un moment plus calme."
        }
        return "Il reste peu de marge. Fermer une app peu utilisée libère de la mémoire, sans que le Mac ralentisse."
    }

    var visibleGroups: [AppGroup] {
        let needle = normalize(query)
        return groups.filter { group in
            if !needle.isEmpty {
                let haystack = normalize(group.name + " " + group.parts.map(\.name).joined(separator: " "))
                if !haystack.contains(needle) { return false }
            }
            if showTraces { return group.footprint >= 8_000_000 || group.canQuit }
            return group.footprint >= 40_000_000 || (group.canQuit && group.footprint >= 20_000_000)
        }
    }

    func groups(in strata: Strata) -> [AppGroup] {
        visibleGroups.filter { $0.strata == strata }
    }

    var driftingUp: [AppGroup] {
        visibleGroups
            .filter { $0.driftPerMinute > 30_000_000 && $0.history.count >= 4 }
            .sorted { $0.driftPerMinute > $1.driftPerMinute }
    }

    var driftingDown: [AppGroup] {
        visibleGroups
            .filter { $0.driftPerMinute < -30_000_000 && $0.history.count >= 4 }
            .sorted { $0.driftPerMinute < $1.driftPerMinute }
    }

    var idleHeavy: [AppGroup] {
        guard sampleCount >= 3 else { return [] }
        return groups.filter { group in
            group.canQuit
                && group.cpu < 5
                && group.footprint > 200_000_000
                && group.mainPID != frontmostPID
                && !group.isSelf
        }
        .sorted { $0.footprint > $1.footprint }
    }

    var forceMessage: String {
        switch forceRequest {
        case .application(let id):
            let group = groups.first { $0.id == id }
            let name = group?.name ?? "cette app"
            if group?.menuBar == true {
                return "\(name) va quitter la barre de menus. Ce qui n’est pas enregistré peut être perdu."
            }
            return "\(name) va se fermer tout de suite. Ce qui n’est pas enregistré peut être perdu."
        case .process(_, let title):
            return "\(title) va se fermer tout de suite. L’onglet ou la fenêtre qui l’utilise se ferme avec."
        case nil:
            return ""
        }
    }

    func start() {
        guard !started else { return }
        started = true
        NSApp.activate()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let pause: Duration = NSApp.isActive ? .seconds(2) : .seconds(6)
                try? await Task.sleep(for: pause)
            }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let previous = ticks
        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        let hints = Self.hints()
        let captured = await Task.detached(priority: .utility) {
            Probe.capture(previous: previous)
        }.value
        ticks = captured.ticks
        snapshot = captured.system
        sampleCount += 1
        let built = assemble(processes: captured.processes, hints: hints, at: captured.system.capturedAt)
        if shouldPublish(built) {
            groups = built
            publishedFront = frontmostPID
        }
        let liveIcons = Set(built.compactMap(\.bundlePath))
        if iconCache.count != liveIcons.count {
            iconCache = iconCache.filter { liveIcons.contains($0.key) }
        }
        if selectedID != nil && !groups.contains(where: { $0.id == selectedID }) {
            selectedID = nil
        }
        if let cursorID, !visibleRows().contains(where: { $0.id == cursorID }) {
            self.cursorID = visibleRows().first?.id
        } else if cursorID == nil {
            self.cursorID = visibleRows().first?.id
        }
        if snapshot.physical == 0 {
            status = "Impossible de lire la mémoire."
        } else if sampleCount == 1 {
            status = "Mémoire lue. L’évolution apparaît dans quelques secondes."
        }
    }

    func quit(_ group: AppGroup) {
        guard group.canQuit else { return }
        guard requestClose(group) else {
            status = "\(group.name) a refusé de se fermer. Vous pouvez forcer la fermeture."
            return
        }
        status = group.menuBar
            ? "Fermeture demandée pour \(group.name). L’icône est dans la barre de menus."
            : "Fermeture demandée pour \(group.name)."
        watchClose(of: group)
    }

    func quitMany(_ ids: Set<String>) {
        let targets = groups.filter { ids.contains($0.id) && $0.canQuit }
        for group in targets {
            _ = requestClose(group)
        }
        let count = targets.count
        status = count == 0
            ? "Aucune app sélectionnée."
            : "Fermeture demandée pour \(Format.count(count, one: "app", many: "apps"))."
        for group in targets {
            watchClose(of: group)
        }
    }

    func stopPart(_ part: MemoryPart) {
        guard part.canSignal, part.pid > 1 else { return }
        if part.isMain, let group = groups.first(where: { $0.parts.contains { $0.pid == part.pid } }), group.canQuit {
            quit(group)
            return
        }
        status = kill(part.pid, SIGTERM) == 0
            ? "Fermeture demandée pour \(part.name)."
            : "macOS a refusé de fermer \(part.name)."
        scheduleRefresh()
    }

    func confirmForce() {
        guard let request = forceRequest else { return }
        forceRequest = nil
        switch request {
        case .application(let id):
            guard let group = groups.first(where: { $0.id == id }), group.canQuit else {
                status = "Cette app n’est plus là."
                return
            }
            force(group)
        case .process(let pid, let title):
            guard let part = groups.flatMap(\.parts).first(where: { $0.pid == pid }), part.canSignal, pid > 1 else {
                status = "Cet élément est protégé, ou il a déjà disparu."
                return
            }
            force(pid: pid, name: title)
        }
        scheduleRefresh()
    }

    func nudge() async {
        guard nudgeAllowed, !isNudging else { return }
        isNudging = true
        defer { isNudging = false }
        let before = snapshot.available
        let cap = min(1_610_612_736, Int(snapshot.available / 2))
        await Task.detached(priority: .utility) {
            MemoryNudge.push(maxBytes: cap)
        }.value
        await refresh()
        let delta = Int64(snapshot.available) - Int64(before)
        if delta >= 0 {
            nudgeReport = "La mémoire libre a gagné \(Format.mem(UInt64(delta))). macOS refera du cache dès qu’une app en aura besoin."
        } else {
            nudgeReport = "La mémoire libre a baissé de \(Format.mem(UInt64(-delta))). Les apps ont repris la place."
        }
        status = nudgeReport ?? status
    }

    func reveal(_ group: AppGroup) {
        guard let path = group.bundlePath ?? group.parts.first?.path, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func apps(matching group: AppGroup) -> [NSRunningApplication] {
        let running = NSWorkspace.shared.runningApplications
        if let id = group.bundleID {
            let matched = running.filter { $0.bundleIdentifier == id }
            if !matched.isEmpty { return matched }
        }
        if let path = group.bundlePath {
            let matched = running.filter { $0.bundleURL?.path == path }
            if !matched.isEmpty { return matched }
        }
        if let pid = group.mainPID, let app = NSRunningApplication(processIdentifier: pid) {
            return [app]
        }
        return []
    }

    /// Demande à l’app de la barre (et pas seulement à un de ses programmes) de se fermer.
    private func requestClose(_ group: AppGroup) -> Bool {
        let apps = apps(matching: group)
        if apps.contains(where: { $0.terminate() }) { return true }
        guard let pid = group.mainPID, pid > 1 else { return false }
        return kill(pid, SIGTERM) == 0
    }

    private func watchClose(of group: AppGroup) {
        let id = group.id
        let name = group.name
        let menu = group.menuBar
        scheduleRefresh()
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            await refresh()
            let still = groups.contains { $0.id == id }
            if still && menu {
                status = "\(name) est encore dans la barre de menus. Forcer enlève l’icône."
            } else if still {
                status = "\(name) est encore ouvert. Vous pouvez forcer la fermeture."
            } else if menu {
                status = "\(name) est fermé. L’icône a quitté la barre de menus."
            }
        }
    }

    private func force(_ group: AppGroup) {
        var closed = apps(matching: group).contains { $0.forceTerminate() }
        for part in group.parts where part.canSignal && part.pid > 1 {
            if kill(part.pid, SIGKILL) == 0 { closed = true }
        }
        if group.menuBar {
            status = closed
                ? "\(group.name) est fermé, y compris l’icône dans la barre de menus."
                : "macOS a refusé de forcer la fermeture de \(group.name)."
        } else {
            status = closed
                ? "\(group.name) a été fermé."
                : "macOS a refusé de forcer la fermeture de \(group.name)."
        }
    }

    private func force(pid: Int32, name: String) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            status = app.forceTerminate()
                ? "Fermeture forcée demandée pour \(name)."
                : "macOS a refusé de forcer la fermeture de \(name)."
            return
        }
        status = kill(pid, SIGKILL) == 0
            ? "\(name) a été fermé."
            : "macOS a refusé de fermer \(name)."
    }

    private func scheduleRefresh() {
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            await refresh()
        }
    }

    private static func hints() -> [Int32: AppHint] {
        var map: [Int32: AppHint] = [:]
        for app in NSWorkspace.shared.runningApplications {
            map[app.processIdentifier] = AppHint(
                pid: app.processIdentifier,
                localizedName: app.localizedName ?? "",
                bundlePath: app.bundleURL?.path,
                bundleID: app.bundleIdentifier,
                policy: Int32(app.activationPolicy.rawValue),
                isActive: app.isActive
            )
        }
        return map
    }

    private func assemble(processes: [RawProcess], hints: [Int32: AppHint], at now: Date) -> [AppGroup] {
        let selfPID = Int32(ProcessInfo.processInfo.processIdentifier)
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        updatePIDHistory(processes, at: now)

        struct Bucket {
            var hint: AppHint?
            var processes: [RawProcess]
        }
        var buckets: [String: Bucket] = [:]

        var hintByBundle: [String: AppHint] = [:]
        for hint in hints.values {
            guard let path = hint.bundlePath else { continue }
            let key = canonical(path)
            if hintByBundle[key]?.policy != 0 {
                hintByBundle[key] = hint
            }
        }

        for process in processes {
            let owner = ownerHint(for: process.pid, byPID: byPID, hints: hints)
            let outer = Self.outermostApp(process.path).map(canonical)
            let key: String
            let hint: AppHint?
            if let outer, let match = hintByBundle[outer] {
                key = "bundle:" + outer
                hint = match
            } else if let path = owner?.bundlePath {
                key = "bundle:" + canonical(path)
                hint = owner
            } else {
                key = "pid:\(process.pid)"
                hint = nil
            }
            var bucket = buckets[key] ?? Bucket(hint: hint, processes: [])
            if bucket.hint == nil || hint?.policy == 0 { bucket.hint = hint }
            bucket.processes.append(process)
            buckets[key] = bucket
        }

        var built: [AppGroup] = []
        built.reserveCapacity(buckets.count)
        for (key, bucket) in buckets {
            built.append(makeGroup(id: key, hint: bucket.hint, processes: bucket.processes, selfPID: selfPID))
        }

        for group in built where group.footprint >= 8_000_000 {
            var series = history[group.id] ?? []
            series.append(SamplePoint(time: now, footprint: group.footprint))
            if series.count > 36 { series.removeFirst(series.count - 36) }
            history[group.id] = series
        }
        let live = Set(built.map(\.id))
        history = history.filter { live.contains($0.key) }

        return built.map { group in
            var copy = group
            let series = history[group.id] ?? []
            copy.history = series
            copy.driftPerMinute = drift(of: series)
            let words = narrative(for: copy)
            copy.narrative = words.story
            copy.advice = words.advice
            return copy
        }
        .sorted { $0.footprint > $1.footprint }
    }

    private func makeGroup(id: String, hint: AppHint?, processes source: [RawProcess], selfPID: Int32) -> AppGroup {
        let processes = source.sorted { $0.footprint > $1.footprint }
        let mainPID = hint?.pid ?? processes.first?.pid
        let isSelf = processes.contains { $0.pid == selfPID }
        let shell = Probe.isShell(hint?.bundleID)
        let browser = Probe.isBrowser(bundleID: hint?.bundleID, name: hint?.localizedName ?? processes.first?.name ?? "")

        let parts: [MemoryPart] = processes.map { process in
            let isMain = process.pid == mainPID
            let series = pidHistory[process.pid] ?? []
            return MemoryPart(
                pid: process.pid,
                name: process.name,
                role: Probe.role(name: process.name, command: process.command, isMain: isMain),
                footprint: process.footprint,
                resident: process.resident,
                virtualSize: process.virtualSize,
                wired: process.wired,
                peak: process.peak,
                cpu: process.cpuPercent,
                threads: process.threads,
                path: process.path,
                isMain: isMain,
                canSignal: Probe.canSignal(process: process, selfPID: selfPID) && !shell && !isSelf,
                driftPerMinute: drift(of: series)
            )
        }

        let policy = hint?.policy ?? 2
        let strata: Strata
        if shell || parts.contains(where: { $0.role == .kernel }) {
            strata = .system
        } else if browser && (policy == 0 || policy == 1) {
            strata = .browsers
        } else if policy == 0 {
            strata = .windows
        } else if policy == 1 {
            strata = .shadow
        } else if processes.contains(where: { $0.uid == 0 || !Probe.canSignal(process: $0, selfPID: selfPID) }) && hint == nil {
            strata = .system
        } else {
            strata = .shadow
        }

        let canQuit = !isSelf && !shell && hint != nil && (policy == 0 || policy == 1) && (mainPID ?? 0) > 1
        var name = hint?.localizedName ?? ""
        if name.isEmpty { name = processes.first?.name ?? "Processus" }
        if isSelf { name = "Clairière" }
        if hint == nil, strata == .shadow, processes.count == 1, let process = processes.first {
            if !process.detail.isEmpty {
                name = "\(name) · \(prettyPath(process.detail))"
            } else if !process.cwd.isEmpty {
                let pretty = prettyPath(process.cwd)
                if pretty != "~" && pretty != "/" && pretty != "~/" {
                    name = "\(name) · \(pretty)"
                }
            }
        }

        let path = hint?.bundlePath.map(canonical)
        return AppGroup(
            id: id,
            name: name,
            strata: strata,
            bundlePath: path,
            bundleID: hint?.bundleID,
            mainPID: mainPID,
            icon: icon(for: path ?? processes.first?.path),
            parts: parts,
            footprint: parts.reduce(0) { $0 + $1.footprint },
            resident: parts.reduce(0) { $0 + $1.resident },
            cpu: parts.reduce(0) { $0 + $1.cpu },
            history: [],
            driftPerMinute: 0,
            canQuit: canQuit,
            menuBar: hint?.policy == 1,
            isSelf: isSelf,
            narrative: "",
            advice: ""
        )
    }

    private func narrative(for group: AppGroup) -> (story: String, advice: String) {
        let memory = Format.mem(group.footprint)
        if group.isSelf {
            return (
                "Clairière mesure la mémoire. Elle utilise \(memory).",
                "Laissez-la ouverte pour continuer à voir ce qui se passe."
            )
        }
        if group.strata == .system {
            return (
                "\(group.name) fait partie de macOS et utilise \(memory).",
                "Le laisser ouvert évite de casser le Mac."
            )
        }
        if group.menuBar {
            return (
                "\(group.name) utilise \(memory). Cette app n’a pas de fenêtre : son icône est dans la barre en haut de l’écran.",
                "Fermer demande à cette icône de partir. Si elle reste, Forcer l’enlève."
            )
        }
        let folded = group.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if folded.contains("orbstack") || folded.contains("docker") || folded.contains("virtual machine") || folded.contains("utm") {
            let verb = group.canQuit ? "Fermer \(group.name)" : "Fermer \(group.name)"
            return (
                "\(group.name) utilise \(memory). Une partie est peut-être déjà compressée.",
                "\(verb) arrête aussi les machines et les conteneurs qui tournent dedans."
            )
        }
        let pages = group.parts.filter { $0.role == .pages }
        let pageBytes = pages.reduce(UInt64(0)) { $0 + $1.footprint }
        if !pages.isEmpty && pageBytes * 3 > group.footprint {
            let engines = Format.count(pages.count, one: "onglet", many: "onglets")
            let held = Format.mem(pageBytes)
            if group.strata == .browsers {
                return (
                    "\(group.name) utilise \(memory), dont \(held) pour \(engines).",
                    "Fermer \(group.name) libère tout. Dans le détail, vous pouvez fermer un seul onglet."
                )
            }
            return (
                "\(group.name) utilise \(memory), dont \(held) pour \(engines) internes.",
                "Fermer \(group.name) ferme tout. Dans le détail, vous pouvez fermer une seule partie."
            )
        }
        if group.parts.count == 1 && group.footprint > 700_000_000 {
            let gap = group.footprint > group.resident ? group.footprint - group.resident : 0
            let extra = gap > 200_000_000 ? " \(Format.mem(gap)) sont déjà compressés ou sur le disque." : ""
            return (
                "\(group.name) utilise \(memory) à lui seul.\(extra)",
                group.canQuit
                    ? "Le fermer libère cette place. Forcer la fermeture peut perdre ce qui n’est pas enregistré."
                    : "Il se ferme avec l’app qui l’a lancé."
            )
        }
        if group.driftPerMinute > 80_000_000 {
            return (
                "\(group.name) prend environ \(Format.mem(UInt64(group.driftPerMinute))) de plus chaque minute.",
                "Le fermer arrête cette hausse."
            )
        }
        if group.history.count >= 2 && group.cpu < 3 && group.footprint > 350_000_000 && group.canQuit {
            return (
                "\(group.name) est peu utilisé et garde pourtant \(memory).",
                "Le fermer libère de la mémoire sans toucher à macOS."
            )
        }
        if group.strata == .shadow {
            return (
                "\(group.name) tourne sans fenêtre et utilise \(memory).",
                "Le fermer laisse macOS intact."
            )
        }
        return (
            "\(group.name) utilise \(memory) pour ce que vous êtes en train de faire.",
            group.canQuit
                ? "Le fermer libère cette mémoire. Forcer sert seulement si l’app ne répond plus."
                : "Cette place se libère quand l’app se termine."
        )
    }

    private func ownerHint(for pid: Int32, byPID: [Int32: RawProcess], hints: [Int32: AppHint]) -> AppHint? {
        var current = pid
        var seen = Set<Int32>()
        var fallback: AppHint?
        for _ in 0..<12 {
            if let hint = hints[current], hint.bundlePath != nil {
                if hint.policy == 0 { return hint }
                if fallback == nil, hint.policy == 1 { fallback = hint }
            }
            guard let process = byPID[current] else { break }
            let parent = process.ppid
            if parent <= 1 || parent == current || seen.contains(parent) { break }
            seen.insert(current)
            current = parent
        }
        return fallback
    }

    private func updatePIDHistory(_ processes: [RawProcess], at now: Date) {
        var live = Set<Int32>()
        for process in processes where process.footprint >= 8_000_000 {
            live.insert(process.pid)
            var series = pidHistory[process.pid] ?? []
            series.append(SamplePoint(time: now, footprint: process.footprint))
            if series.count > 36 { series.removeFirst(series.count - 36) }
            pidHistory[process.pid] = series
        }
        pidHistory = pidHistory.filter { live.contains($0.key) }
    }

    private func drift(of series: [SamplePoint]) -> Double {
        guard series.count >= 3, let first = series.first, let last = series.last else { return 0 }
        let minutes = last.time.timeIntervalSince(first.time) / 60
        guard minutes >= 0.12 else { return 0 }
        return Double(Int64(last.footprint) - Int64(first.footprint)) / minutes
    }

    private func shouldPublish(_ built: [AppGroup]) -> Bool {
        if sampleCount < 4 || groups.count != built.count || publishedFront != frontmostPID {
            return true
        }
        for (old, new) in zip(groups, built) {
            if old.id != new.id { return true }
            if abs(Int64(old.footprint) - Int64(new.footprint)) > 12_000_000 { return true }
            if abs(old.cpu - new.cpu) > 1.5 { return true }
        }
        return false
    }

    private func icon(for path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        if let cached = iconCache[path] { return cached }
        let source = NSWorkspace.shared.icon(forFile: path)
        let side = 64
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return source }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        iconCache[path] = image
        return image
    }

    private static func outermostApp(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.upperBound].dropLast())
    }

    private func prettyPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var value = path
        if value == home { return "~" }
        if value.hasPrefix(home + "/") {
            value = "~" + value.dropFirst(home.count)
        }
        if value.count > 46 {
            let parts = value.split(separator: "/")
            if parts.count >= 2 {
                return "…/" + parts.suffix(2).joined(separator: "/")
            }
        }
        return value
    }

    private func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
