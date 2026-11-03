import SwiftUI

/// The live picture of the voice on the island: bars, soft waves or a pixel grid.
/// All three read the same meter and redraw with its 60 Hz timer.
struct Visualizer: View {
    @ObservedObject var meter: LevelMeter
    let style: AppState.VisualStyle
    let source: AppState.VisualSource

    var body: some View {
        Group {
            switch style {
            case .bars: bars
            case .waves: waves
            case .pixels: pixels
            }
        }
        .accessibilityHidden(true) // decoration; the state is announced elsewhere
    }

    // MARK: Bars

    private var bars: some View {
        let values = meter.values(count: LevelMeter.barCount, source: source)
        return HStack(spacing: 5) {
            ForEach(values.indices, id: \.self) { i in
                Capsule().fill(.white).frame(width: 5, height: 6 + 22 * CGFloat(values[i]))
            }
        }
        .frame(width: 110, height: 28)
    }

    // MARK: Waves: four soft lines, strongest in the middle, fading out at the edges

    private var waves: some View {
        let signals = meter.signals(count: 4, source: source)
        let phase = meter.phase
        return Canvas { context, size in
            let opacities: [Double] = [1, 0.65, 0.4, 0.22]
            let frequencies: [Double] = [1.2, 1.7, 2.3, 3.1]
            let speeds: [Double] = [2.2, -1.6, 2.9, -2.4]
            let mid = size.height / 2

            func line(_ k: Int) -> Path {
                var path = Path()
                for x in stride(from: 0.0, through: Double(size.width), by: 2) {
                    let t = x / Double(size.width)
                    let envelope = pow(sin(.pi * t), 1.4)
                    let amplitude = (1.5 + 11 * Double(signals[k])) * envelope
                    let y = Double(mid) + amplitude * sin(2 * .pi * frequencies[k] * t + phase * speeds[k])
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                return path
            }

            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 3))
                for k in 0..<4 {
                    glow.stroke(line(k), with: .color(.white.opacity(opacities[k] * 0.6)), lineWidth: 4)
                }
            }
            for k in 0..<4 {
                context.stroke(line(k), with: .color(.white.opacity(opacities[k])),
                               style: StrokeStyle(lineWidth: k == 0 ? 2 : 1.6, lineCap: .round))
            }
        }
        .frame(width: 150, height: 28)
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0), .init(color: .black, location: 0.25),
            .init(color: .black, location: 0.75), .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing))
    }

    // MARK: Pixels: a dim grid that lights up from the middle row outward

    private var pixels: some View {
        let columns = 14, rows = 4
        let values = meter.values(count: columns, source: source)
        return Canvas { context, size in
            let gap: CGFloat = 2
            let cellW = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cellH = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            for c in 0..<columns {
                for r in 0..<rows {
                    let distance = abs(Double(r) - Double(rows - 1) / 2) // 0.5 inner, 1.5 outer
                    let lit = min(max(Double(values[c]) * 2 - (distance - 0.5), 0), 1)
                    let rect = CGRect(x: CGFloat(c) * (cellW + gap), y: CGFloat(r) * (cellH + gap), width: cellW, height: cellH)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.white.opacity(0.10 + 0.90 * lit)))
                }
            }
        }
        .frame(width: 120, height: 28)
    }
}

/// Loading wheel while the model works. Static under "Reduce motion" (the island says "Распознаю…").
struct Spinner: View {
    @ObservedObject var meter: LevelMeter
    let animated: Bool

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 22, height: 22)
            .rotationEffect(.degrees(animated ? meter.phase * 400 : 0))
            .accessibilityLabel("Распознаю речь")
    }
}
