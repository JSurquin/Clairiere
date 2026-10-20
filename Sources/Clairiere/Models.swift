import AppKit
import Foundation
import SwiftUI

enum Lens: String, CaseIterable, Identifiable {
    case home
    case memory
    case cleanup
    case storage
    case apps
    case startup
    case advisor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Accueil"
        case .memory: "Mémoire"
        case .cleanup: "Nettoyage"
        case .storage: "Stockage"
        case .apps: "Apps"
        case .startup: "Démarrage"
        case .advisor: "IA"
        }
    }

    var subtitle: String {
        switch self {
        case .home: "L’essentiel, sans rien lancer"
        case .memory: "Chaque app, et ce qu’elle contient"
        case .cleanup: "Caches, journaux, corbeille"
        case .storage: "Disque, iCloud, gros fichiers"
        case .apps: "Taille, restes, mises à jour"
        case .startup: "Ce qui s’ouvre avec le Mac"
        case .advisor: "Fichiers anciens, lus sur ce Mac"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .memory: "memorychip"
        case .cleanup: "sparkles"
        case .storage: "internaldrive"
        case .apps: "square.grid.2x2"
        case .startup: "bolt"
        case .advisor: "wand.and.stars"
        }
    }
}

enum MemoryFocus: String, CaseIterable, Identifiable {
    case grouped
    case mass
    case drift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grouped: "Par app"
        case .mass: "Les plus gros"
        case .drift: "Ça augmente"
        }
    }
}

enum Strata: String, CaseIterable, Identifiable {
    case browsers
    case windows
    case shadow
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browsers: "Navigateurs"
        case .windows: "Apps ouvertes"
        case .shadow: "En arrière-plan"
        case .system: "macOS"
        }
    }

    var detail: String {
        switch self {
        case .browsers: "La fenêtre, et les onglets qui pèsent souvent plus lourd"
        case .windows: "Les fenêtres que vous voyez"
        case .shadow: "Ouvertes sans fenêtre"
        case .system: "Mieux vaut les laisser ouvertes"
        }
    }

    var tint: Color {
        switch self {
        case .browsers: Theme.sky
        case .windows: Theme.leaf
        case .shadow: Theme.gold
        case .system: Theme.muted
        }
    }
}

enum PartRole: String, CaseIterable {
    case interface
    case pages
    case graphics
    case plugin
    case helper
    case service
    case kernel
    case other

    var label: String {
        switch self {
        case .interface: "Fenêtre"
        case .pages: "Onglet"
        case .graphics: "Image"
        case .plugin: "Extension"
        case .helper: "Aide"
        case .service: "Tâche"
        case .kernel: "macOS"
        case .other: "Autre"
        }
    }

    var tint: Color {
        switch self {
        case .interface: Theme.leaf
        case .pages: Theme.sky
        case .graphics: Theme.gold
        case .plugin: Theme.lilac
        case .helper: Theme.muted
        case .service: Theme.gold
        case .kernel: Theme.coral
        case .other: Theme.muted
        }
    }
}

enum PressureBand {
    case calm
    case tense
    case critical

    var title: String {
        switch self {
        case .calm: "Ça va"
        case .tense: "Un peu juste"
        case .critical: "Pleine"
        }
    }

    var headline: String {
        switch self {
        case .calm: "Il reste de la place."
        case .tense: "La mémoire commence à manquer."
        case .critical: "La mémoire est pleine."
        }
    }

    var tint: Color {
        switch self {
        case .calm: Theme.leaf
        case .tense: Theme.gold
        case .critical: Theme.coral
        }
    }
}

struct SamplePoint: Sendable {
    var time: Date
    var footprint: UInt64
}

struct TickMark: Sendable {
    var ticks: UInt64
    var time: Date
}

struct SystemSnapshot: Sendable {
    var physical: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var cached: UInt64
    var free: UInt64
    var purgeable: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var uncompressedInCompressor: UInt64
    var swapEncrypted: Bool
    var pressureLevel: Int32
    var capturedAt: Date

    var used: UInt64 { app &+ wired &+ compressed }
    var available: UInt64 { free &+ cached }

    static let empty = SystemSnapshot(
        physical: 0,
        app: 0,
        wired: 0,
        compressed: 0,
        cached: 0,
        free: 0,
        purgeable: 0,
        swapUsed: 0,
        swapTotal: 0,
        uncompressedInCompressor: 0,
        swapEncrypted: false,
        pressureLevel: 0,
        capturedAt: .distantPast
    )
}

struct AppHint: Sendable {
    var pid: Int32
    var localizedName: String
    var bundlePath: String?
    var bundleID: String?
    var policy: Int32
    var isActive: Bool
}

struct RawProcess: Sendable, Identifiable {
    var id: Int32 { pid }
    var pid: Int32
    var ppid: Int32
    var uid: uid_t
    var name: String
    var command: String
    var path: String
    var footprint: UInt64
    var resident: UInt64
    var virtualSize: UInt64
    var wired: UInt64
    var peak: UInt64
    var threads: Int
    var cpuTicks: UInt64
    var cpuPercent: Double
    var start: Date
    var cwd: String
    var detail: String
}

struct MemoryPart: Identifiable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var role: PartRole
    var footprint: UInt64
    var resident: UInt64
    var virtualSize: UInt64
    var wired: UInt64
    var peak: UInt64
    var cpu: Double
    var threads: Int
    var path: String
    var isMain: Bool
    var canSignal: Bool
    var driftPerMinute: Double
}

struct Segment: Identifiable {
    var id: String
    var role: PartRole
    var bytes: UInt64
    var share: Double
}

struct AppGroup: Identifiable {
    var id: String
    var name: String
    var strata: Strata
    var bundlePath: String?
    var bundleID: String?
    var mainPID: Int32?
    var icon: NSImage?
    var parts: [MemoryPart]
    var footprint: UInt64
    var resident: UInt64
    var cpu: Double
    var history: [SamplePoint]
    var driftPerMinute: Double
    var canQuit: Bool
    /// App sans fenêtre, visible seulement dans la barre de menus.
    var menuBar: Bool
    var isSelf: Bool
    var narrative: String
    var advice: String

    var segments: [Segment] {
        let grouped = Dictionary(grouping: parts, by: \.role)
        let rows = grouped.map { role, items in
            (role, items.reduce(UInt64(0)) { $0 + $1.footprint })
        }
        .sorted { $0.1 > $1.1 }
        let total = max(footprint, 1)
        let head = rows.prefix(4)
        let tail = rows.dropFirst(4).reduce(UInt64(0)) { $0 + $1.1 }
        var result = head.map { role, bytes in
            Segment(id: role.rawValue, role: role, bytes: bytes, share: Double(bytes) / Double(total))
        }
        if tail > 0 {
            result.append(Segment(id: "rest", role: .other, bytes: tail, share: Double(tail) / Double(total)))
        }
        return result
    }
}

enum ForceRequest: Identifiable {
    case application(String)
    case process(pid: Int32, title: String)

    var id: String {
        switch self {
        case .application(let appID): "app-\(appID)"
        case .process(let pid, _): "pid-\(pid)"
        }
    }
}

struct Capture: Sendable {
    var system: SystemSnapshot
    var processes: [RawProcess]
    var ticks: [Int32: TickMark]
}
