import SwiftUI

/// Mac Statistics from biinge (M30): the period's watch time and its split, the activity chart with its hovered bar's breakdown, the highlight tiles and a card per category
struct DesktopStatisticsView: View {
    let apiClient: APIClient

    @State private var loaded: [StatsPeriod: AccountStats] = [:]
    @State private var period: StatsPeriod = .week
    /// The bar under the pointer in each period's chart (the peak until one is hovered)
    @State private var selected: [StatsPeriod: Int] = [:]
    /// Each period's last load error message, cleared once its load succeeds
    @State private var failures: [StatsPeriod: String] = [:]
    /// The grid's width, which sizes its twelve columns
    @State private var width: CGFloat = 0
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let now = Date.now
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Statistics")
                            .font(.system(size: 40, weight: .bold))
                            .tracking(-1.2)
                        Text("\(period.range(now: now)) · from your Biinge history on every device")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.biingeTextSecondary)
                    }
                    Spacer(minLength: 0)
                    periodPills
                }
                // a period is only ever drawn from its own numbers, so a switch shows the spinner rather than another period's figures
                if let stats = loaded[period] {
                    content(stats, now: now)
                } else if let failure = failures[period] {
                    ContentUnavailableView {
                        Label("Can’t reach Biinge", systemImage: "icloud.slash")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                    .padding(.vertical, 60)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .navigationTitle("Statistics")
        .task(id: period) { await load() }
    }

    /// The Week, Month, Year and All pills, whose shared fill slides to the picked one
    private var periodPills: some View {
        HStack(spacing: 2) {
            ForEach(StatsPeriod.allCases, id: \.self) { item in
                Button {
                    withAnimation(MotionCurve.standard.animation(MotionDuration.standard)) { period = item }
                } label: {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 18)
                        .frame(height: 30)
                        .foregroundStyle(period == item ? Color.biingeText : Color.biingeText.opacity(0.72))
                        .background {
                            if period == item {
                                Capsule()
                                    .fill(Color.biingeText.opacity(0.16))
                                    // one shared fill slides between the pills, while Reduce Motion crossfades a fill of each pill's own
                                    .matchedGeometryEffect(id: reduceMotion ? AnyHashable(item) : "selection", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .accessibilityAddTraits(period == item ? .isSelected : [])
            }
        }
        .buttonStyle(.plain)
        .padding(3)
        .background(Color.biingeText.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.biingeFill(0.06), lineWidth: 1))
    }

    /// Fetches the period, keeping an earlier fetch on screen while it refreshes
    private func load() async {
        // the period the load is for, so a result that lands after a switch files under its own period
        let period = period
        do {
            loaded[period] = try await apiClient.stats(period: period)
            failures[period] = nil
        } catch {
            // leaving the screen or switching period cancels the load, which is no failure
            guard !Task.isCancelled else { return }
            failures[period] = error.localizedDescription
        }
    }

    /// The twelve-column grid: watch time over four columns beside activity over eight, the highlights in a row, then the Movies and TV cards side by side
    private func content(_ stats: AccountStats, now: Date) -> some View {
        // four columns of twelve with their three gaps
        let watchTimeWidth = max((width - 11 * 16) / 12 * 4 + 3 * 16, 0)
        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                watchTime(stats)
                    .frame(width: watchTimeWidth)
                    .frame(maxHeight: .infinity)
                activity(stats.activity ?? [], now: now)
                    .frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            // three tiles share the row as four do, so it never ends on a gap
            HStack(spacing: 16) {
                ForEach(period.highlights(for: stats, now: now), id: \.label) { tile in
                    highlight(tile)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                category("Movies", symbol: "film.fill", numbers: [("Watched", stats.movies.watched), (period.wantLabel, stats.movies.want)])
                category("TV Shows", symbol: "tv.fill",
                         numbers: [("Shows", stats.series.watched), ("Episodes", stats.episodes.watched), (period.wantLabel, stats.series.want)])
            }
        }
    }

    /// The Watch time card: the total over the split bar and the Movies and TV Shows rows with their time and share
    private func watchTime(_ stats: AccountStats) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Watch time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.biingeTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ForEach(Array(AccountStats.durationParts(stats.totalMinutes).enumerated()), id: \.offset) { _, part in
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(part.value))
                                .font(.system(size: 60, weight: .bold))
                                .tracking(-2.4)
                            Text(part.unit)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Color.biingeTextSecondary)
                        }
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AccountStats.duration(stats.totalMinutes))
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { proxy in
                    HStack(spacing: 3) {
                        if stats.totalMinutes == 0 {
                            Capsule().fill(Color.biingeFill(0.06))
                        } else {
                            if stats.moviePercent > 0 {
                                Capsule().fill(Color.dataMovies)
                                    .frame(width: proxy.size.width * Double(stats.moviePercent) / 100)
                            }
                            if stats.moviePercent < 100 {
                                Capsule().fill(Color.dataSeries)
                            }
                        }
                    }
                }
                .frame(height: 12)
                VStack(spacing: 0) {
                    ForEach([("Movies", Color.dataMovies, stats.movies.minutes, stats.moviePercent),
                             ("TV Shows", Color.dataSeries, stats.episodes.minutes, stats.seriesPercent)], id: \.0) { name, color, minutes, percent in
                        HStack(spacing: 10) {
                            Circle().fill(color).frame(width: 9, height: 9)
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(AccountStats.duration(minutes))
                                .fontWeight(.semibold)
                            Text("\(percent)%")
                                .foregroundStyle(Color.biingeTextSecondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .font(.system(size: 14.5))
                        .monospacedDigit()
                        .frame(height: 40)
                        .overlay(alignment: .top) {
                            if name != "Movies" { Rectangle().fill(Color.biingeFill(0.06)).frame(height: 1) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 24)
        .background(Color.biingeFill(0.04), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.biingeFill(0.07), lineWidth: 1))
    }

    /// The Activity card: the hovered bar's label, total and split above the stacked bars, peak first
    private func activity(_ buckets: [AccountStats.Bucket], now: Date) -> some View {
        let maxHours = AccountStats.chartMaxHours(buckets)
        let scale = 200 / Double(maxHours * 60)
        let index = selected[period].flatMap { buckets.indices.contains($0) ? $0 : nil } ?? AccountStats.peakIndex(buckets)
        let bucket = index.map { buckets[$0] }
        let gap: CGFloat = switch period {
        case .week: 28
        case .month: 6
        case .year: 14
        case .all: 24
        }
        return VStack(alignment: .leading, spacing: 16) {
            // the callout sits in the header and follows the hovered bar, never as a tooltip over it
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bucket.map { "Activity · \(period.calloutLabel(for: $0.start, now: now))" } ?? "Activity")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.biingeTextSecondary)
                    Text(bucket.map { $0.totalMinutes > 0 ? AccountStats.duration($0.totalMinutes) : "Nothing watched" } ?? "Nothing watched")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.5)
                }
                Spacer(minLength: 0)
                if let bucket {
                    HStack(spacing: 18) {
                        HStack(spacing: 7) {
                            Circle().fill(Color.dataMovies).frame(width: 8, height: 8)
                            Text("Movies \(AccountStats.duration(bucket.movieMinutes))")
                        }
                        HStack(spacing: 7) {
                            Circle().fill(Color.dataSeries).frame(width: 8, height: 8)
                            Text("TV \(AccountStats.duration(bucket.seriesMinutes))")
                        }
                    }
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.biingeTextSecondary)
                }
            }
            .monospacedDigit()
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Rectangle().fill(Color.biingeFill(0.07)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Rectangle().fill(Color.biingeFill(0.07)).frame(height: 1)
                        .offset(y: 100)
                    Rectangle().fill(Color.biingeFill(0.14)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    Text("\(maxHours)h")
                        .offset(y: 5)
                    Text("\(maxHours / 2)h")
                        .offset(y: 105)
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(buckets.indices, id: \.self) { item in
                            let bar = buckets[item]
                            // TV stacks over movies with a 2 pt gap, and only the top segment rounds
                            VStack(spacing: bar.movieMinutes > 0 && bar.seriesMinutes > 0 ? 2 : 0) {
                                Spacer(minLength: 0)
                                if bar.seriesMinutes > 0 {
                                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                                        .fill(Color.dataSeries)
                                        .frame(height: Double(bar.seriesMinutes) * scale)
                                }
                                if bar.movieMinutes > 0 {
                                    UnevenRoundedRectangle(topLeadingRadius: bar.seriesMinutes > 0 ? 0 : 3, topTrailingRadius: bar.seriesMinutes > 0 ? 0 : 3)
                                        .fill(Color.dataMovies)
                                        .frame(height: Double(bar.movieMinutes) * scale)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .opacity(item == index ? 1 : 0.4)
                            .onHover { if $0 { selected[period] = item } }
                            .accessibilityElement()
                            .accessibilityLabel(period.calloutLabel(for: bar.start, now: now))
                            .accessibilityValue(AccountStats.duration(bar.totalMinutes))
                            .accessibilityAddTraits(item == index ? .isSelected : [])
                            .accessibilityAction { selected[period] = item }
                        }
                    }
                    .padding(.trailing, 44)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.biingeTextTertiary)
                .frame(height: 200)
                HStack(spacing: gap) {
                    ForEach(buckets.indices, id: \.self) { item in
                        // an overlay lets a label wider than its bar spill over its neighbours, centred
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)
                            .overlay {
                                Text(period.axisLabel(at: item, of: buckets))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(item == index ? Color.biingeText : Color.biingeTextTertiary)
                                    .fixedSize()
                            }
                    }
                }
                .padding(.trailing, 44)
                .accessibilityHidden(true)
            }
        }
        .animation(MotionCurve.standard.animation(MotionDuration.quick), value: index)
        .padding(.top, 22)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.biingeFill(0.04), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.biingeFill(0.07), lineWidth: 1))
    }

    /// One highlight tile: the symbol in its box beside the value over its label
    private func highlight(_ tile: StatsHighlight) -> some View {
        HStack(spacing: 14) {
            Image(systemName: tile.symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.biingeText.opacity(0.8))
                .frame(width: 42, height: 42)
                .background(Color.biingeFill(0.06), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.value)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tile.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.biingeTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(Color.biingeFill(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.biingeFill(0.07), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// A category card: the symbol and name beside the period's counts
    private func category(_ name: String, symbol: String, numbers: [(String, Int)]) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.biingeTextSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.biingeFill(0.1), in: Circle())
                Text(name)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 28) {
                ForEach(numbers, id: \.0) { label, value in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(value.formatted())
                            .font(.system(size: 24, weight: .bold))
                            .tracking(-0.5)
                            .monospacedDigit()
                        Text(label)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.biingeTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 22)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Color.biingeFill(0.04), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.biingeFill(0.07), lineWidth: 1))
    }
}
