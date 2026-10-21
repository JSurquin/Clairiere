import SwiftUI

struct RootView: View {
    @Environment(MemoryStore.self) private var store
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            SidebarView()
            Rectangle().fill(Theme.line).frame(width: 1)
            main
            if store.lens == .memory, let group = store.selected {
                Rectangle().fill(Theme.line).frame(width: 1)
                InspectorView(group: group)
            } else if store.lens == .apps, let app = store.shelf.selected {
                Rectangle().fill(Theme.line).frame(width: 1)
                AppDetailView(app: app)
            }
        }
        .id(store.lightTheme)
        .background(Theme.bg)
        .background(WindowChrome(light: store.lightTheme))
        .background(KeyCatcher(store: store))
        .preferredColorScheme(Theme.scheme)
        .onAppear {
            store.start()
            store.disk.prepareVolume()
        }
        .onChange(of: store.focusToken) { _, _ in
            searchFocused = true
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { store.browsingResults = false }
        }
        .onChange(of: store.releaseSearch) { _, _ in
            searchFocused = false
        }
        .onChange(of: store.query) { _, _ in
            store.alignCursor()
        }
        .sheet(isPresented: $store.showLighten) {
            LightenSheet()
                .environment(store)
                .id(store.lightTheme)
        }
        .sheet(isPresented: $store.showHelp) {
            HelpSheet { store.showHelp = false }
                .id(store.lightTheme)
        }
        .confirmationDialog(
            "Forcer la fermeture ?",
            isPresented: forcePresented,
            titleVisibility: .visible
        ) {
            Button("Forcer la fermeture", role: .destructive) { store.confirmForce() }
            Button("Annuler", role: .cancel) { store.forceRequest = nil }
        } message: {
            Text(store.forceMessage)
        }
        .confirmationDialog(
            store.pending?.title ?? "Continuer ?",
            isPresented: pendingPresented,
            titleVisibility: .visible
        ) {
            Button(pendingButton, role: pendingRole) { store.applyPending() }
            Button("Annuler", role: .cancel) { store.pending = nil }
        } message: {
            Text(store.pending?.message ?? "")
        }
    }

    private var pendingButton: String {
        guard let pending = store.pending else { return "Continuer" }
        if pending.snapshot != nil { return "Supprimer l’instantané" }
        if pending.destroy.isEmpty { return "Mettre à la Corbeille" }
        if pending.trash.isEmpty { return "Supprimer définitivement" }
        return "Continuer"
    }

    private var pendingRole: ButtonRole? {
        guard let pending = store.pending else { return nil }
        if pending.snapshot != nil || !pending.destroy.isEmpty { return .destructive }
        return nil
    }

    private var forcePresented: Binding<Bool> {
        Binding(
            get: { store.forceRequest != nil },
            set: { if !$0 { store.forceRequest = nil } }
        )
    }

    private var pendingPresented: Binding<Bool> {
        Binding(
            get: { store.pending != nil },
            set: { if !$0 { store.pending = nil } }
        )
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if store.lens == .memory {
                            HeroView()
                        }
                        switch store.lens {
                        case .home: HomeView()
                        case .memory:
                            switch store.memoryFocus {
                            case .grouped: StrataView()
                            case .mass: MassView()
                            case .drift: DriftView()
                            }
                        case .cleanup: CleanupView()
                        case .storage: StorageView()
                        case .apps: AppsView()
                        case .startup: StartupView()
                        case .advisor: AdvisorView()
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                }
                .onChange(of: store.cursorID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        @Bindable var store = store
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.lens.title)
                    .font(.system(size: 22, weight: .medium, design: .default))
                    .foregroundStyle(Theme.text)
                Text(store.lens.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if store.lens == .memory {
                Picker("Affichage", selection: $store.memoryFocus) {
                    ForEach(MemoryFocus.allCases) { focus in
                        Text(focus.title).tag(focus)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if store.lens != .home {
                search
            }
        }
        .padding(.horizontal, 22)
    }

    private var search: some View {
        @Bindable var store = store
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.muted)
                TextField(searchPrompt, text: $store.query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.text)
                    .focused($searchFocused)
                if !store.query.isEmpty {
                    Button { store.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 200)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))

            if store.lens == .memory {
                Button {
                    store.showTraces.toggle()
                } label: {
                    Text(store.showTraces ? "Petites apps" : "Grosses apps")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.showTraces ? Theme.gold : Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Affiche aussi les petites apps")
            }
        }
    }

    private var searchPrompt: String {
        switch store.lens {
        case .memory: "Chercher une app…"
        case .cleanup: "Chercher…"
        case .storage: "Chercher un fichier…"
        case .apps: "Chercher une app…"
        case .startup: "Chercher…"
        case .advisor: "Chercher un fichier…"
        case .home: ""
        }
    }
}
