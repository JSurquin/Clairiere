import AppKit
import SwiftUI

@main
struct ClairiereApp: App {
    @State private var store = MemoryStore()

    var body: some Scene {
        WindowGroup("Clairière") {
            RootView()
                .environment(store)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandMenu("Affichage") {
                Button("Accueil") { store.lens = .home }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Mémoire") { store.lens = .memory }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Nettoyage") { store.lens = .cleanup }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Stockage") { store.lens = .storage }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Apps") { store.lens = .apps }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Démarrage") { store.lens = .startup }
                    .keyboardShortcut("6", modifiers: .command)
                Button("IA") { store.lens = .advisor }
                    .keyboardShortcut("7", modifiers: .command)
                Divider()
                Button("Par app") { store.lens = .memory; store.memoryFocus = .grouped }
                Button("Les plus gros") { store.lens = .memory; store.memoryFocus = .mass }
                Button("Ça augmente") { store.lens = .memory; store.memoryFocus = .drift }
                Divider()
                Button("Action de la ligne") { store.primaryAction() }
                    .keyboardShortcut(KeyEquivalent.return, modifiers: .command)
                    .disabled(store.forceRequest != nil || store.pending != nil || store.disk.confirmEvict)
                Button("Forcer la fermeture") { store.forceCurrent() }
                    .keyboardShortcut(KeyEquivalent.return, modifiers: [.command, .shift])
                    .disabled(store.forceRequest != nil || store.pending != nil || store.disk.confirmEvict)
                Divider()
                Button("Recherche") { store.focusToken += 1 }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Libérer") { store.showLighten = true }
                    .keyboardShortcut("l", modifiers: .command)
                Button(store.showTraces ? "Masquer les petites apps" : "Afficher les petites apps") {
                    store.showTraces.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button(store.lightTheme ? "Thème sombre" : "Thème clair") {
                    store.setAppearance(light: !store.lightTheme)
                }
            }
            CommandGroup(replacing: .help) {
                Button("Raccourcis Clairière") { store.showHelp = true }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuStatus(store: store)
        } label: {
            Image(systemName: "leaf.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuStatus: View {
    var store: MemoryStore

    var body: some View {
        Button("Ouvrir Clairière") { store.openMainWindow() }
        Text(store.snapshot.physical == 0 ? "Mémoire : lecture…" : "Mémoire : \(Format.mem(store.snapshot.used)) utilisés")
        Text(store.disk.volume.total == 0 ? "Disque : lecture…" : "Disque : \(Format.mem(store.disk.volume.available)) libres")
        if let heavy = store.heaviestQuitable {
            Button("Fermer \(heavy.name)") { store.quit(heavy) }
        }
        Divider()
        Button("Quitter Clairière") { NSApp.terminate(nil) }
    }
}
