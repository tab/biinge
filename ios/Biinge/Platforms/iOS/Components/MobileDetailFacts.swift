import SwiftUI

/// The iPhone details' facts in two columns under their hairline (nothing without facts)
struct MobileDetailFacts: View {
    let facts: [DetailFact]
    /// The space between the hairline and the first row
    var topPadding: CGFloat = 20

    @ScaledMetric(relativeTo: .caption) private var labelSize = 12.5
    @ScaledMetric(relativeTo: .subheadline) private var valueSize = 15
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !facts.isEmpty {
            // accessibility sizes outgrow two columns
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .topLeading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 18) {
                ForEach(facts) { fact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fact.label)
                            .font(.system(size: labelSize, weight: .medium))
                            .foregroundStyle(Color.biingeTextTertiary)
                        Group {
                            if let count = fact.count {
                                // the name gives way first, so the count always shows
                                HStack(spacing: 4) {
                                    Text(fact.value)
                                        .lineLimit(1)
                                    Text(count)
                                        .fixedSize()
                                }
                            } else {
                                // a film can list twenty directors; Subtitles name one language
                                Text(fact.value)
                                    .lineLimit(fact.label == "Subtitles" ? 1 : 3)
                            }
                        }
                        .font(.system(size: valueSize))
                        .foregroundStyle(Color.biingeText.opacity(0.8))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, topPadding)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.biingeFill(0.09)).frame(height: 1)
            }
        }
    }
}
