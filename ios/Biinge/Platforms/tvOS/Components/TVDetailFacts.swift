import SwiftUI

/// The Apple TV details' facts under the overview: up to three fit one row, and more fill two rows in aligned columns
struct TVDetailFacts: View {
    let facts: [DetailFact]

    var body: some View {
        let columns = facts.count > 3 ? (facts.count + 1) / 2 : max(facts.count, 1)
        Grid(alignment: .topLeading, horizontalSpacing: 48, verticalSpacing: 14) {
            ForEach(Array(stride(from: 0, to: facts.count, by: columns)), id: \.self) { start in
                let row = Array(facts[start..<min(start + columns, facts.count)])
                GridRow {
                    ForEach(row) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(fact.label)
                                .foregroundStyle(Color.biingeText.opacity(0.55))
                                .fixedSize()
                            // the name gives way first, so the label and the count always show; Subtitles name one language
                            Text(fact.value)
                                .foregroundStyle(Color.biingeText.opacity(0.8))
                                .lineLimit(fact.label == "Subtitles" ? 1 : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            if let count = fact.count {
                                Text(count)
                                    .foregroundStyle(Color.biingeText.opacity(0.8))
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
        }
        .font(.system(size: 25))
    }
}
