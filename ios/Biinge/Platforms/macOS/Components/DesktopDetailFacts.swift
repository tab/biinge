import SwiftUI

/// The Mac details' facts under their hairline, in as many columns as fit and the facts fill (nothing without facts)
struct DesktopDetailFacts: View {
    let facts: [DetailFact]
    /// The narrowest a column gets (the default keeps "English · Dolby Atmos" on one line)
    var minimumColumn: CGFloat = 170

    /// The grid's measured width, 0 until its first layout
    @State private var width: CGFloat = 0

    var body: some View {
        if !facts.isEmpty {
            let fitting = width > 0 ? max(Int((width + 24) / (minimumColumn + 24)), 1) : facts.count
            let columns = Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .topLeading), count: min(fitting, facts.count))
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(facts) { fact in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(fact.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.biingeTextTertiary)
                        Group {
                            if let count = fact.count {
                                // the name gives way first, so the count always shows
                                HStack(spacing: 5) {
                                    Text(fact.value)
                                        .lineLimit(1)
                                    Text(count)
                                        .fixedSize()
                                }
                            } else {
                                // a film can list twenty directors, which the tooltip still names; Subtitles name one language
                                Text(fact.value)
                                    .lineLimit(fact.label == "Subtitles" ? 1 : 3)
                            }
                        }
                        .font(.system(size: 16))
                        .foregroundStyle(Color.biingeText.opacity(0.8))
                        .help(fact.value)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .padding(.top, 24)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.biingeFill(0.09)).frame(height: 1)
            }
        }
    }
}
