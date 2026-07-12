import SwiftUI

/// A small filled pie showing watch progress (0...100), used on watching shows.
struct PieChartView: View {
    let percent: Double
    var color: Color = .white

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.stroke(
                Circle().path(in: rect.insetBy(dx: 1, dy: 1)),
                with: .color(color.opacity(0.5)),
                lineWidth: 1.5
            )

            guard percent > 0 else { return }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(
                center: center,
                radius: rect.width / 2 - 2,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 360 * min(percent, 100) / 100),
                clockwise: false
            )
            wedge.closeSubpath()
            context.fill(wedge, with: .color(color))
        }
    }
}
