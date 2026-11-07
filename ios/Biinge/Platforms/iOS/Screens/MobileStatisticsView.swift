import SwiftUI

/// Watched time over a calendar period: the hero total and its split, the activity chart, highlight tiles and a card per category (P03)
struct MobileStatisticsView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var loaded: [StatsPeriod: AccountStats] = [:]
    /// Each period's last load error, shown only while the period has no numbers
    @State private var failures: [StatsPeriod: String] = [:]
    @State private var period: StatsPeriod = Self.initialPeriod
    /// The bar picked in each period's chart (the peak until one is tapped)
    @State private var selected: [StatsPeriod: Int] = [:]
    @State private var forward = true

    private static var initialPeriod: StatsPeriod {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["DEBUG_STATS_PERIOD"],
           let period = StatsPeriod(rawValue: raw) {
            return period
        }
        #endif
        return .week
    }

    var body: some View {
        ModalScaffold(title: "Statistics", inset: 16) {
            VStack(alignment: .leading, spacing: 18) {
                PillFilter(selection: $period, forward: $forward) { $0.title }

                // A period is only ever drawn from its own numbers, so switching pills
                // spins rather than showing another window's figures under the new label
                if let stats = loaded[period] {
                    content(stats, now: .now)
                } else if let failure = failures[period] {
                    ContentUnavailableView {
                        Label("Can’t reach Biinge", systemImage: "icloud.slash")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            failures[period] = nil
                            Task { await load() }
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.top, 40)
                } else {
                    ProgressView().tint(Color.biingeLoader)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
        }
        .task(id: period) { await load() }
    }

    /// Renders an already fetched period straight away and refreshes it behind the
    /// scenes, so coming back to a pill costs nothing
    private func load() async {
        guard let apiClient else { return }

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

    private func content(_ stats: AccountStats, now: Date) -> some View {
        let tiles = period.highlights(for: stats, now: now)
        // an odd count gives the first tile the full width, so the 2×2 grid never ends on a gap
        let lead = tiles.count.isMultiple(of: 2) ? [] : Array(tiles.prefix(1))

        return VStack(alignment: .leading, spacing: 18) {
            hero(stats, now: now)
            if let buckets = stats.activity, !buckets.isEmpty {
                activityChart(buckets, now: now)
            }
            VStack(spacing: 10) {
                ForEach(lead, id: \.label) { highlightTile($0) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ForEach(tiles.dropFirst(lead.count), id: \.label) { highlightTile($0) }
                }
            }
            categoryCard(
                "Movies", symbol: "film.fill",
                time: AccountStats.duration(stats.movies.minutes),
                numbers: ["Watched": stats.movies.watched, period.wantLabel: stats.movies.want]
            )
            categoryCard(
                "TV Shows", symbol: "tv.fill",
                time: AccountStats.duration(stats.episodes.minutes),
                numbers: ["Shows": stats.series.watched, "Episodes": stats.episodes.watched, period.wantLabel: stats.series.want]
            )
            if let games = stats.games {
                // "to beat" rather than "played": the minutes are IGDB's estimate for the games finished, not time this user spent
                categoryCard(
                    "Games", symbol: "gamecontroller.fill",
                    time: games.minutes > 0 ? "\(AccountStats.duration(games.minutes)) to beat" : "None finished",
                    numbers: ["Finished": games.played, period.wantLabel: games.want]
                )
            }
        }
    }

    private func hero(_ stats: AccountStats, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(period.range(now: now))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.biingeTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ForEach(Array(AccountStats.durationParts(stats.totalMinutes).enumerated()), id: \.offset) { _, part in
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(part.value))
                                .font(.custom("Archivo-SemiBold", size: 56, relativeTo: .largeTitle))
                                .tracking(-2.2)
                            Text(part.unit)
                                .font(.custom("Archivo-SemiBold", size: 28, relativeTo: .title))
                                .tracking(-0.6)
                                .foregroundStyle(Color.biingeTextSecondary)
                        }
                    }
                }
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AccountStats.duration(stats.totalMinutes))
            }

            GeometryReader { geo in
                HStack(spacing: 3) {
                    if stats.totalMinutes == 0 {
                        Capsule().fill(Color.biingeFill(0.06))
                    } else {
                        if stats.moviePercent > 0 {
                            Capsule().fill(Color.dataMovies)
                                .frame(width: geo.size.width * Double(stats.moviePercent) / 100)
                        }
                        if stats.moviePercent < 100 {
                            Capsule().fill(Color.dataSeries)
                        }
                    }
                }
            }
            .frame(height: 10)

            HStack(alignment: .top, spacing: 12) {
                legendItem("Movies", percent: stats.moviePercent, minutes: stats.movies.minutes, color: .dataMovies)
                legendItem("TV", percent: stats.seriesPercent, minutes: stats.episodes.minutes, color: .dataSeries)
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }

    private func legendItem(_ name: String, percent: Int, minutes: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text("\(name) · \(percent)%")
                    .font(.subheadline)
                    .foregroundStyle(Color.biingeTextSecondary)
            }
            Text(AccountStats.duration(minutes))
                .font(.headline)
                .monospacedDigit()
                .padding(.leading, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityChart(_ buckets: [AccountStats.Bucket], now: Date) -> some View {
        let maxHours = AccountStats.chartMaxHours(buckets)
        let scale = 150 / Double(maxHours * 60)
        let index = selected[period].flatMap { buckets.indices.contains($0) ? $0 : nil } ?? AccountStats.peakIndex(buckets) ?? 0
        let bucket = buckets[index]
        let gap: CGFloat = switch period {
        case .week: 12
        case .month: 3
        case .year: 6
        case .all: 10
        }

        return VStack(alignment: .leading, spacing: 14) {
            // the callout sits above the chart and follows the selected bar, never as a tooltip over it
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(period.calloutLabel(for: bucket.start, now: now))
                        .font(.footnote)
                        .foregroundStyle(Color.biingeTextSecondary)
                    Text(bucket.totalMinutes > 0 ? AccountStats.duration(bucket.totalMinutes) : "Nothing watched")
                        .font(.custom("Archivo-SemiBold", size: 22, relativeTo: .title2))
                        .tracking(-0.44)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Movies \(AccountStats.duration(bucket.movieMinutes))")
                        Circle().fill(Color.dataMovies).frame(width: 8, height: 8)
                    }
                    HStack(spacing: 6) {
                        Text("TV \(AccountStats.duration(bucket.seriesMinutes))")
                        Circle().fill(Color.dataSeries).frame(width: 8, height: 8)
                    }
                }
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color.biingeTextSecondary)
            }

            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Rectangle().fill(Color.biingeFill(0.07)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Rectangle().fill(Color.biingeFill(0.07)).frame(height: 1)
                        .offset(y: 75)
                    Rectangle().fill(Color.biingeFill(0.14)).frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    Text("\(maxHours)h")
                        .offset(y: 4)
                        .accessibilityHidden(true)
                    Text("\(maxHours / 2)h")
                        .offset(y: 79)
                        .accessibilityHidden(true)

                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(buckets.indices, id: \.self) { item in
                            let bar = buckets[item]
                            Button {
                                selected[period] = item
                            } label: {
                                // TV stacks over movies with a 2 pt gap, and only the top segment rounds
                                VStack(spacing: bar.movieMinutes > 0 && bar.seriesMinutes > 0 ? 2 : 0) {
                                    Spacer(minLength: 0)
                                    if bar.seriesMinutes > 0 {
                                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                                            .fill(Color.dataSeries)
                                            .frame(height: Double(bar.seriesMinutes) * scale)
                                    }
                                    if bar.movieMinutes > 0 {
                                        UnevenRoundedRectangle(
                                            topLeadingRadius: bar.seriesMinutes > 0 ? 0 : 3,
                                            topTrailingRadius: bar.seriesMinutes > 0 ? 0 : 3
                                        )
                                        .fill(Color.dataMovies)
                                        .frame(height: Double(bar.movieMinutes) * scale)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .opacity(item == index ? 1 : 0.4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(period.calloutLabel(for: bar.start, now: now))
                            .accessibilityValue(AccountStats.duration(bar.totalMinutes))
                            .accessibilityAddTraits(item == index ? .isSelected : [])
                        }
                    }
                    .padding(.trailing, 32)
                }
                .font(.caption2)
                .foregroundStyle(Color.biingeTextTertiary)
                .frame(height: 150)

                HStack(spacing: gap) {
                    ForEach(buckets.indices, id: \.self) { item in
                        // an overlay lets a label wider than its bar spill over its neighbours, centred
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 13)
                            .overlay {
                                Text(period.axisLabel(at: item, of: buckets))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(item == index ? Color.biingeText : Color.biingeTextTertiary)
                                    .fixedSize()
                            }
                    }
                }
                .padding(.trailing, 32)
                .accessibilityHidden(true)
            }
        }
        .animation(MotionCurve.standard.animation(MotionDuration.quick), value: index)
        .padding(16)
        .background(Color.biingeFill(0.04), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.biingeFill(0.06), lineWidth: 1))
    }

    private func highlightTile(_ tile: StatsHighlight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: tile.symbol)
                .font(.title3)
                .foregroundStyle(Color.biingeTextSecondary)
                // symbols differ in height, so a fixed box keeps the tiles in a row level
                .frame(height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.value)
                    .font(.custom("Archivo-SemiBold", size: 24, relativeTo: .title2))
                    .tracking(-0.48)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tile.label)
                    .font(.footnote)
                    .foregroundStyle(Color.biingeTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.biingeFill(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.biingeFill(0.06), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func categoryCard(_ name: String, symbol: String, time: String, numbers: KeyValuePairs<String, Int>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.subheadline)
                        .foregroundStyle(Color.biingeTextSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.biingeFill(0.1), in: Circle())
                    Text(name)
                        .font(.custom("Archivo-SemiBold", size: 22, relativeTo: .title2))
                        .tracking(-0.44)
                }
                Spacer(minLength: 0)
                Text(time)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.biingeTextSecondary)
            }
            HStack(spacing: 28) {
                ForEach(numbers, id: \.key) { number in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(number.value.formatted())
                            .font(.custom("Archivo-SemiBold", size: 30, relativeTo: .title))
                            .tracking(-0.9)
                            .monospacedDigit()
                        Text(number.key)
                            .font(.footnote)
                            .foregroundStyle(Color.biingeTextSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.biingeFill(0.04), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.biingeFill(0.06), lineWidth: 1))
    }
}
