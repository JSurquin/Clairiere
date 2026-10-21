import AppKit
import SwiftUI

struct KeyRow: Identifiable {
    var id: String
    var reveal: String?
}

enum KeyBridge {
    nonisolated(unsafe) static weak var store: MemoryStore?

    static func deliver(keyCode: UInt16, rawFlags: UInt, chars: String) -> Bool {
        MainActor.assumeIsolated {
            let typing = NSApp.keyWindow?.firstResponder is NSTextView
            return store?.handleKey(keyCode: keyCode, rawFlags: rawFlags, chars: chars, typing: typing) ?? false
        }
    }
}

struct KeyCatcher: NSViewRepresentable {
    var store: MemoryStore

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start(store)
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.store = store
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var store: MemoryStore?
        var monitor: Any?

        func start(_ store: MemoryStore) {
            self.store = store
            KeyBridge.store = store
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let key = event.keyCode
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
                let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
                let handled = KeyBridge.deliver(keyCode: key, rawFlags: flags, chars: chars)
                return handled ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            KeyBridge.store = nil
        }
    }
}

extension MemoryStore {
    func show(_ lens: Lens) {
        self.lens = lens
    }

    func rowOn(_ id: String) -> Bool {
        cursorID == id
    }

    var heaviestQuitable: AppGroup? {
        groups.filter(\.canQuit).max { $0.footprint < $1.footprint }
    }

    func leaveSearch() {
        releaseSearch += 1
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    func alignCursor() {
        let rows = visibleRows()
        if let cursorID, rows.contains(where: { $0.id == cursorID }) { return }
        cursorID = rows.first?.id
    }

    func reveal(_ path: String?) {
        guard let path, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    func openSoftwareUpdate() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func openSparkle(_ app: AppRecord) async {
        guard let feed = app.sparkle else { return }
        if let page = await HouseScan.pageLink(feed: feed) {
            NSWorkspace.shared.open(page)
        }
    }

    func applyPending() {
        guard let job = pending else { return }
        pending = nil
        if let snapshot = job.snapshot {
            Task {
                let text = await Task.detached { HouseScan.deleteSnapshot(snapshot) }.value
                boot.maintenance = text
                await boot.scan()
            }
            return
        }
        Task {
            let text = await Task.detached {
                HouseScan.apply(trash: job.trash, destroy: job.destroy)
            }.value
            status = text
            disk.prepareVolume()
            await cleanup.scan()
            if files.all.isEmpty == false || lens == .storage {
                await files.scan()
            }
            if lens == .apps {
                await shelf.scan()
            }
            let gone = advisor.items.map(\.path).filter { !FileManager.default.fileExists(atPath: $0) }
            if !gone.isEmpty {
                advisor.items.removeAll { gone.contains($0.path) }
                advisor.picked = advisor.picked.filter { id in advisor.items.contains { $0.id == id } }
            }
        }
    }

    func handleKey(keyCode: UInt16, rawFlags: UInt, chars: String, typing: Bool) -> Bool {
        if dialogOpen { return false }
        let flags = NSEvent.ModifierFlags(rawValue: rawFlags)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        if flags.contains(.option) || flags.contains(.control) { return false }
        let key = keyCode
        let editing = typing && !browsingResults

        if key == 53 {
            if editing {
                browsingResults = true
                leaveSearch()
                alignCursor()
                return true
            }
            return closeSurface()
        }
        if command && !shift && chars == "f" {
            browsingResults = false
            focusToken += 1
            return true
        }
        if command && !shift && chars == "o" {
            revealCurrent()
            return true
        }
        if command && shift && (key == 36 || key == 76) {
            forceCurrent()
            return true
        }
        if command && (key == 36 || key == 76) {
            primaryAction()
            return true
        }
        if editing && !command && (key == 125 || key == 126 || key == 36 || key == 76) {
            browsingResults = true
            leaveSearch()
            let visible = visibleRows().contains { $0.id == cursorID }
            if !visible {
                alignCursor()
            } else if key == 125 {
                moveCursor(1)
            } else if key == 126 {
                moveCursor(-1)
            } else {
                openCurrent()
            }
            return true
        }
        if editing { return false }
        if command && chars == "a" {
            setChecks(on: !shift)
            return true
        }
        if !command && (key == 126 || key == 125) {
            moveCursor(key == 126 ? -1 : 1)
            return true
        }
        if !command && key == 49 {
            toggleCurrent()
            return true
        }
        if !command && (key == 36 || key == 76) {
            openCurrent()
            return true
        }
        return false
    }

    func visibleRows() -> [KeyRow] {
        if showLighten {
            return idleHeavy.map { KeyRow(id: "idle:\($0.id)", reveal: $0.bundlePath) }
        }
        switch lens {
        case .home:
            return ["home:memory", "home:cleanup", "home:storage", "home:apps", "home:startup", "home:advisor", "home:idle"]
                .map { KeyRow(id: $0, reveal: nil) }
        case .memory:
            return memoryRows().map { KeyRow(id: $0.id, reveal: $0.bundlePath) }
        case .cleanup:
            return cleanup.items.filter { listed($0.title + " " + $0.detail) }.map {
                KeyRow(id: "junk:\($0.id)", reveal: $0.paths.first)
            }
        case .storage:
            let clouds = disk.batches.filter { listed($0.title + " " + $0.place) }.map {
                KeyRow(id: "cloud:\($0.id)", reveal: $0.paths.first)
            }
            let files = self.files.all.filter { listed($0.title + " " + $0.note) }.map {
                KeyRow(id: "file:\($0.id)", reveal: $0.path)
            }
            return clouds + files
        case .apps:
            return shelf.apps.filter { listed($0.name + " " + $0.bundleID) }.map {
                KeyRow(id: "app:\($0.id)", reveal: $0.path)
            }
        case .startup:
            let agents = boot.items.filter { listed($0.name + " " + $0.detail) }.map {
                KeyRow(id: "boot:\($0.id)", reveal: $0.path)
            }
            let snaps = boot.snapshots.map { KeyRow(id: "snap:\($0.id)", reveal: nil) }
            return agents + snaps
        case .advisor:
            return advisor.items.filter { listed($0.name + " " + $0.explanation) }.map {
                KeyRow(id: "stale:\($0.id)", reveal: $0.path)
            }
        }
    }

    private var dialogOpen: Bool {
        forceRequest != nil || disk.confirmEvict || pending != nil
    }

    private func listed(_ text: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return text.localizedStandardContains(needle)
    }

    private func memoryRows() -> [AppGroup] {
        switch memoryFocus {
        case .grouped:
            return Strata.allCases.flatMap { groups(in: $0) }
        case .mass:
            return visibleGroups
        case .drift:
            return driftingUp + driftingDown
        }
    }

    private func moveCursor(_ delta: Int) {
        let rows = visibleRows()
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.id == cursorID } ?? (delta > 0 ? -1 : 0)
        let next = min(max(0, index + delta), rows.count - 1)
        cursorID = rows[next].id
    }

    private func closeSurface() -> Bool {
        if showHelp {
            showHelp = false
            return true
        }
        if showLighten {
            showLighten = false
            return true
        }
        if lens == .cleanup, cleanup.openID != nil {
            cleanup.openID = nil
            return true
        }
        if selectedID != nil {
            selectedID = nil
            return true
        }
        if shelf.selectedID != nil {
            shelf.selectedID = nil
            return true
        }
        if !query.isEmpty {
            query = ""
            return true
        }
        return false
    }

    private func toggleCurrent() {
        guard let id = cursorID else { return }
        if id.hasPrefix("idle:") {
            let groupID = String(id.dropFirst(5))
            if lightenPicked.contains(groupID) { lightenPicked.remove(groupID) } else { lightenPicked.insert(groupID) }
        } else if id.hasPrefix("junk:") {
            cleanup.toggle(String(id.dropFirst(5)))
        } else if id.hasPrefix("cloud:") {
            disk.toggleCloud(String(id.dropFirst(6)))
        } else if id.hasPrefix("file:") {
            files.toggle(String(id.dropFirst(5)))
        } else if id.hasPrefix("app:") {
            shelf.toggle(String(id.dropFirst(4)))
        } else if id.hasPrefix("stale:") {
            advisor.toggle(String(id.dropFirst(6)))
        }
    }

    private func setChecks(on: Bool) {
        if showLighten {
            lightenPicked = on ? Set(idleHeavy.map(\.id)) : []
            return
        }
        switch lens {
        case .cleanup:
            let ids = visibleRows().compactMap { row -> String? in
                row.id.hasPrefix("junk:") ? String(row.id.dropFirst(5)) : nil
            }
            cleanup.picked = on ? Set(ids) : []
        case .storage:
            if !on {
                disk.picked = []
                files.picked = []
                return
            }
            for row in visibleRows() {
                if row.id.hasPrefix("cloud:") { disk.picked.insert(String(row.id.dropFirst(6))) }
                if row.id.hasPrefix("file:") { files.picked.insert(String(row.id.dropFirst(5))) }
            }
        case .apps:
            let ids = visibleRows().compactMap { row -> String? in
                row.id.hasPrefix("app:") ? String(row.id.dropFirst(4)) : nil
            }
            shelf.picked = on ? Set(ids) : []
        case .advisor:
            let ids = visibleRows().compactMap { row -> String? in
                row.id.hasPrefix("stale:") ? String(row.id.dropFirst(6)) : nil
            }
            advisor.picked = on ? Set(ids) : []
        default:
            break
        }
    }

    private func openCurrent() {
        guard let id = cursorID else { return }
        if showLighten {
            toggleCurrent()
            return
        }
        switch id {
        case "home:memory", "home:idle":
            show(.memory)
        case "home:cleanup":
            show(.cleanup)
        case "home:storage":
            show(.storage)
        case "home:apps":
            show(.apps)
        case "home:startup":
            show(.startup)
        case "home:advisor":
            show(.advisor)
        default:
            break
        }
        if id.hasPrefix("junk:") {
            let itemID = String(id.dropFirst(5))
            if cleanup.items.first(where: { $0.id == itemID })?.parts.count ?? 0 > 1 {
                cleanup.toggleOpen(itemID)
            }
            return
        }
        if let group = groups.first(where: { $0.id == id }) {
            selectedID = group.id
            return
        }
        if id.hasPrefix("app:") {
            let path = String(id.dropFirst(4))
            if let app = shelf.apps.first(where: { $0.id == path }) {
                shelf.select(app)
            }
        }
    }

    func primaryAction() {
        guard let id = cursorID else {
            status = "Choisissez une ligne avec les flèches."
            return
        }
        if showLighten {
            let groupID = String(id.dropFirst(5))
            closeApp(groups.first { $0.id == groupID })
            return
        }
        if id.hasPrefix("home:") {
            openCurrent()
            return
        }
        if lens == .memory, let group = groups.first(where: { $0.id == id }) ?? selected {
            closeApp(group)
            return
        }
        if id.hasPrefix("junk:") {
            pending = cleanup.pending(for: [String(id.dropFirst(5))])
        } else if id.hasPrefix("cloud:") {
            let batchID = String(id.dropFirst(6))
            if let batch = disk.batches.first(where: { $0.id == batchID }) {
                disk.askEvict([batch])
            }
        } else if id.hasPrefix("file:") {
            pending = files.pending(for: [String(id.dropFirst(5))])
        } else if id.hasPrefix("app:") {
            let path = String(id.dropFirst(4))
            if let app = shelf.apps.first(where: { $0.id == path }) {
                guard canRemove(app) else { return }
                shelf.select(app)
                pending = shelf.removalPending(includeApp: true, extra: Array(shelf.leftoverPicked))
            }
        } else if id.hasPrefix("boot:") {
            let path = String(id.dropFirst(5))
            if let item = boot.items.first(where: { $0.id == path }) {
                if item.id.hasPrefix("login:") {
                    openLoginItems()
                } else if !item.locked {
                    Task { await boot.toggle(item) }
                }
            }
        } else if id.hasPrefix("stale:") {
            pending = advisor.pending(for: [String(id.dropFirst(6))])
        } else if id.hasPrefix("snap:") {
            let snapID = String(id.dropFirst(5))
            if let snapshot = boot.snapshots.first(where: { $0.id == snapID }) {
                pending = boot.snapshotPending(snapshot)
            }
        }
    }

    func forceCurrent() {
        let groupID: String
        if let id = cursorID, id.hasPrefix("idle:") {
            groupID = String(id.dropFirst(5))
        } else if lens == .memory {
            groupID = cursorID ?? selectedID ?? ""
        } else {
            groupID = ""
        }
        guard let group = groups.first(where: { $0.id == groupID }) else {
            status = "Choisissez une app dans Mémoire, puis forcez la fermeture."
            return
        }
        if group.canQuit {
            forceRequest = .application(group.id)
            return
        }
        if let part = group.parts.first(where: \.canSignal) {
            forceRequest = .process(pid: part.pid, title: part.name)
            return
        }
        status = "\(group.name) reste ouverte. macOS la protège."
    }

    private func closeApp(_ group: AppGroup?) {
        guard let group else {
            status = "Choisissez une app avec les flèches."
            return
        }
        if group.canQuit {
            quit(group)
            return
        }
        if let part = group.parts.first(where: \.canSignal) {
            stopPart(part)
            return
        }
        status = "\(group.name) reste ouverte. macOS la protège."
    }

    func pendingCheckedApps() -> HousePending? {
        let chosen = shelf.apps.filter { shelf.picked.contains($0.id) && canRemove($0) }
        guard !chosen.isEmpty else {
            status = "Ces apps sont ouvertes ou protégées. Mieux vaut les laisser."
            return nil
        }
        var paths: [String] = []
        for app in chosen {
            paths.append(app.path)
            paths.append(contentsOf: HouseScan.leftovers(bundleID: app.bundleID, name: app.name))
        }
        return HousePending(
            title: "Retirer \(chosen.count) app\(chosen.count > 1 ? "s" : "") ?",
            message: "L’app et ses restes iront à la Corbeille. Vous pouvez les reprendre.\n\n\(HouseScan.preview(paths))",
            trash: paths,
            destroy: [],
            snapshot: nil
        )
    }

    private func canRemove(_ app: AppRecord) -> Bool {
        if app.bundleID == Bundle.main.bundleIdentifier || app.path.hasPrefix("/System") {
            status = "\(app.name) reste en place."
            return false
        }
        let running = groups.contains { $0.bundlePath == app.path || ($0.bundleID != nil && $0.bundleID == app.bundleID) }
        if running {
            status = "Fermez \(app.name) dans Mémoire avant de la retirer."
            return false
        }
        return true
    }

    private func revealCurrent() {
        guard let id = cursorID else { return }
        if let row = visibleRows().first(where: { $0.id == id }) {
            reveal(row.reveal)
        }
    }
}
