import SwiftUI

struct HeroView: View {
    @Environment(MemoryStore.self) private var store

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    PressureOrb(ratio: ratio, tint: store.band.tint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.band.title.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(store.band.tint)
                        Text(store.snapshot.physical == 0 ? "Lecture de la mémoire…" : store.band.headline)
                            .font(.system(size: 26, weight: .medium, design: .default))
                            .foregroundStyle(Theme.text)
                        Text(store.reading)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(store.leverLine)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text.opacity(0.92))
                    }
                    Spacer(minLength: 8)
                }
                composition
                metrics
                if store.snapshot.swapUsed > 100_000_000 {
                    Text("\(Format.mem(store.snapshot.swapUsed)) sont sur le disque, parce que la mémoire ne suffit plus.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.coral)
                }
            }
        }
    }

    private var ratio: Double {
        guard store.snapshot.physical > 0 else { return 0 }
        return Double(store.snapshot.used) / Double(store.snapshot.physical)
    }

    private var composition: some View {
        let parts = pieces.filter { $0.bytes > 0 }
        let total = max(parts.reduce(UInt64(0)) { $0 + $1.bytes }, 1)
        return GeometryReader { geo in
            let spacing = CGFloat(max(parts.count - 1, 0)) * 3
            let usable = max(geo.size.width - spacing, 1)
            HStack(spacing: 3) {
                ForEach(parts) { piece in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(piece.color)
                        .frame(width: max(4, usable * CGFloat(piece.bytes) / CGFloat(total)))
                        .help("\(piece.label) · \(Format.mem(piece.bytes))")
                }
            }
        }
        .frame(height: 14)
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            ForEach(pieces) { piece in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(piece.color).frame(width: 6, height: 6)
                        Text(piece.label)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    Text(Format.mem(piece.bytes))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var pieces: [Piece] {
        let snap = store.snapshot
        return [
            Piece(id: "app", label: "Applications", bytes: snap.app, color: Theme.leaf),
            Piece(id: "wired", label: "macOS", bytes: snap.wired, color: Theme.gold),
            Piece(id: "compressed", label: "Compressée", bytes: snap.compressed, color: Theme.coral),
            Piece(id: "free", label: "Disponible", bytes: snap.available, color: Theme.sky)
        ]
    }
}

private struct Piece: Identifiable {
    var id: String
    var label: String
    var bytes: UInt64
    var color: Color
}
