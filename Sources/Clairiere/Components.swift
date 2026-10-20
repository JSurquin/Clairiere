import AppKit
import SwiftUI

struct Mark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.gold.opacity(0.55), lineWidth: 1.2)
            Circle()
                .trim(from: 0.08, to: 0.78)
                .stroke(Theme.leaf, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(200))
            Circle()
                .fill(Theme.leaf)
                .frame(width: 5, height: 5)
                .offset(y: -8)
        }
        .frame(width: 28, height: 28)
    }
}

struct AppGlyph: View {
    var group: AppGroup
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let icon = group.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    Circle().fill(group.strata.tint.opacity(0.16))
                    Text(String(group.name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.38, weight: .medium, design: .serif))
                        .foregroundStyle(group.strata.tint)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct ActionButton: View {
    var title: String
    var tint: Color
    var prominent = false
    var helpText: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? tint : Theme.text.opacity(0.88))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(prominent ? tint.opacity(0.16) : Theme.wash, in: Capsule())
                .overlay(Capsule().stroke(prominent ? tint.opacity(0.45) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

struct Chip: View {
    var text: String
    var tint: Color = Theme.muted

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.1), in: Capsule())
    }
}

struct Sparkline: View {
    var points: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let minValue = points.min() ?? 0
            let maxValue = points.max() ?? 1
            let span = max(maxValue - minValue, 1)
            Path { path in
                for (index, value) in points.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    let y = geo.size.height * (1 - CGFloat((value - minValue) / span))
                    let point = CGPoint(x: x, y: y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

struct SegmentBar: View {
    var segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            let spacing = CGFloat(max(segments.count - 1, 0)) * 3
            let usable = max(geo.size.width - spacing, 1)
            HStack(spacing: 3) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(segment.role.tint)
                        .frame(width: max(4, usable * segment.share))
                        .help("\(segment.role.label) · \(Format.mem(segment.bytes))")
                }
            }
        }
        .frame(height: 8)
    }
}

struct PressureOrb: View {
    var ratio: Double
    var tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Theme.wash, lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, max(0, ratio)))
                .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.45), value: ratio)
            VStack(spacing: 0) {
                Text("\(Int((min(ratio, 1) * 100).rounded()))")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 86, height: 86)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}
