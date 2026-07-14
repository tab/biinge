import SwiftUI

/// A small filled pie showing watch progress, used on watching shows
struct PieChartView: View {
    let percent: Double
    var color: Color = .white

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let ringWidth: CGFloat = 1.5
            let border: CGFloat = 2

            context.stroke(
                Circle().path(in: rect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2)),
                with: .color(color),
                lineWidth: ringWidth
            )

            guard percent > 0 else { return }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(
                center: center,
                radius: rect.width / 2 - ringWidth - border,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 360 * min(percent, 100) / 100),
                clockwise: false
            )
            wedge.closeSubpath()
            context.fill(wedge, with: .color(color))
        }
    }
}
