import SwiftUI

/// Apple TV Statistics from Settings: the period pills (focus picks the period), the hero total with its split and legend, and the activity chart with the peak bucket called out (T30)
struct TVStatisticsView: View {
    let apiClient: APIClient

    @State private var loaded: [StatsPeriod: AccountStats] = [:]
    /// Each period's last load error, shown only while the period has no numbers
    @State private var failures: [StatsPeriod: String] = [:]
    /// Counts Try Again presses, which rerun the shown period's load
    @State private var retries = 0
    @State private var period: StatsPeriod = .week
    @FocusState private var focus: StatsPeriod?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Statistics")
                        .font(.system(size: 76, weight: .bold))
                        .tracking(-2.66)
                    Text(period.range(now: .now))
                        .font(.system(size: 28))
                        .foregroundStyle(Color.biingeTextSecondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(StatsPeriod.allCases, id: \.self) { item in
                        Button { period = item } label: {
                            Text(item.title)
                        }
                        .buttonStyle(PeriodPillStyle(isSelected: item == period))
                        .focused($focus, equals: item)
                    }
                }
                .padding(8)
                .background(Color.biingeFill(0.08), in: Capsule())
                .focusSection()
            }
            // a period is only drawn from its own numbers, so a pill that hasn't loaded yet spins (a failed refresh keeps the numbers it had)
            if let stats = loaded[period] {
                content(stats, now: .now)
                    .padding(.top, 90)
            } else if let failure = failures[period] {
                Message(icon: "icloud.slash", title: "Can’t reach Biinge", text: failure, action: "Try Again") {
                    failures[period] = nil
                    retries += 1
                }
                .padding(.top, 60)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 200)
            }
        }
        .padding(.horizontal, 120)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color.biingeText)
        .background(Color.biingeBackground)
        .ignoresSafeArea()
        // the header sits where the tab bar would, as the board draws the screen without it
        .toolbar(.hidden, for: .tabBar)
        .defaultFocus($focus, .week)
        // left and right move focus along the pills, which picks the period at once
        .onChange(of: focus) {
            if let focus { period = focus }
        }
        .task(id: "\(period.rawValue)-\(retries)") { await load() }
    }

    /// Loads the shown period's numbers into that period's cache, or its error (a load cancelled by another pick or by leaving publishes nothing)
    private func load() async {
        let requested = period
        do {
            let result = try await apiClient.stats(period: requested)
            guard !Task.isCancelled else { return }
            loaded[requested] = result
            failures[requested] = nil
        } catch {
            guard !Task.isCancelled else { return }
            failures[requested] = error.localizedDescription
        }
    }

    /// The hero beside the chart card, five to eight
    private func content(_ stats: AccountStats, now: Date) -> some View {
        GeometryReader { geo in
            let width = (geo.size.width - 48) / 13
            HStack(alignment: .top, spacing: 48) {
                hero(stats)
                    .frame(width: width * 5)
                if let buckets = stats.activity, !buckets.isEmpty {
                    chart(buckets, now: now)
                        .frame(width: width * 8)
                }
            }
        }
        .frame(height: 370)
    }

    /// The total with its smaller units, then the split bar over the Movies and TV Shows legend
    private func hero(_ stats: AccountStats) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                ForEach(Array(AccountStats.durationParts(stats.totalMinutes).enumerated()), id: \.offset) { _, part in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(part.value))
                            .font(.system(size: 120, weight: .bold))
                            .tracking(-5.4)
                        Text(part.unit)
                            .font(.system(size: 56, weight: .semibold))
                            .tracking(-1.12)
                            .foregroundStyle(Color.biingeTextSecondary)
                    }
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AccountStats.duration(stats.totalMinutes))
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 24) {
                GeometryReader { geo in
                    HStack(spacing: 5) {
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
                .frame(height: 18)
                HStack(alignment: .top, spacing: 24) {
                    legendItem("Movies", percent: stats.moviePercent, minutes: stats.movies.minutes, color: .dataMovies)
                    legendItem("TV Shows", percent: stats.seriesPercent, minutes: stats.episodes.minutes, color: .dataSeries)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func legendItem(_ name: String, percent: Int, minutes: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 16, height: 16)
                Text("\(name) · \(percent)%")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.biingeTextSecondary)
            }
            Text(AccountStats.duration(minutes))
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .padding(.leading, 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The peak bucket's callout over the stacked bars, gridlines and axis labels (the chart takes no focus, so the peak stays called out)
    private func chart(_ buckets: [AccountStats.Bucket], now: Date) -> some View {
        let maxHours = AccountStats.chartMaxHours(buckets)
        let scale = 196 / Double(maxHours * 60)
        let index = AccountStats.peakIndex(buckets) ?? 0
        let bucket = buckets[index]
        let gap: CGFloat = switch period {
        case .week: 40
        case .month: 8
        case .year: 20
        case .all: 36
        }

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(period.calloutLabel(for: bucket.start, now: now))
                        .font(.system(size: 24))
                        .foregroundStyle(Color.biingeTextSecondary)
                    Text(bucket.totalMinutes > 0 ? AccountStats.duration(bucket.totalMinutes) : "Nothing watched")
                        .font(.system(size: 40, weight: .bold))
                        .tracking(-1)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                HStack(spacing: 28) {
                    HStack(spacing: 10) {
                        Circle().fill(Color.dataMovies).frame(width: 14, height: 14)
                        Text("Movies \(AccountStats.duration(bucket.movieMinutes))")
                    }
                    HStack(spacing: 10) {
                        Circle().fill(Color.dataSeries).frame(width: 14, height: 14)
                        Text("TV \(AccountStats.duration(bucket.seriesMinutes))")
                    }
                }
                .font(.system(size: 24))
                .monospacedDigit()
                .foregroundStyle(Color.biingeTextSecondary)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Rectangle().fill(Color.biingeFill(0.07)).frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Rectangle().fill(Color.biingeFill(0.07)).frame(height: 2)
                        .frame(maxHeight: .infinity)
                    Rectangle().fill(Color.biingeFill(0.14)).frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    Text("\(maxHours)h")
                        .offset(y: 8)
                    Text("\(maxHours / 2)h")
                        .offset(y: 98 + 8)
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(buckets.indices, id: \.self) { item in
                            let bar = buckets[item]
                            // TV stacks over movies with a 3 pt gap, and only the top segment rounds
                            VStack(spacing: bar.movieMinutes > 0 && bar.seriesMinutes > 0 ? 3 : 0) {
                                Spacer(minLength: 0)
                                if bar.seriesMinutes > 0 {
                                    UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                                        .fill(Color.dataSeries)
                                        .frame(height: Double(bar.seriesMinutes) * scale)
                                }
                                if bar.movieMinutes > 0 {
                                    UnevenRoundedRectangle(topLeadingRadius: bar.seriesMinutes > 0 ? 0 : 6, topTrailingRadius: bar.seriesMinutes > 0 ? 0 : 6)
                                        .fill(Color.dataMovies)
                                        .frame(height: Double(bar.movieMinutes) * scale)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .opacity(item == index ? 1 : 0.4)
                        }
                    }
                    .padding(.trailing, 76)
                }
                .font(.system(size: 20))
                .foregroundStyle(Color.biingeTextTertiary)
                .frame(height: 196)

                HStack(spacing: gap) {
                    ForEach(buckets.indices, id: \.self) { item in
                        // an overlay lets a label wider than its bar spill over its neighbours, centred
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .overlay {
                                Text(period.axisLabel(at: item, of: buckets))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(item == index ? Color.biingeText : Color.biingeTextTertiary)
                                    .fixedSize()
                            }
                    }
                }
                .padding(.trailing, 76)
            }
            .accessibilityHidden(true)
        }
        .padding(.top, 30)
        .padding(.horizontal, 36)
        .padding(.bottom, 26)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.biingeFill(0.05), in: RoundedRectangle(cornerRadius: 32))
    }
}

/// A period pill: tinted while selected, light and raised while focused (Reduce Motion: lit without the scale)
private struct PeriodPillStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Pill(label: configuration.label, isSelected: isSelected)
    }

    /// Reads focus from the environment, which a ButtonStyle itself can't see
    private struct Pill: View {
        let label: ButtonStyleConfiguration.Label
        let isSelected: Bool

        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isFocused ? Color.biingeFocusText : Color.biingeText.opacity(isSelected ? 1 : 0.6))
                .padding(.horizontal, 32)
                .frame(height: 64)
                .background(isFocused ? Color.biingeFocusFill : Color.biingeFill(isSelected ? 0.18 : 0), in: Capsule())
                .scaleEffect(isFocused && !reduceMotion ? 1.06 : 1)
                .shadow(color: Color.biingeShadow.opacity(isFocused ? 0.45 : 0), radius: 20, y: 18)
                .animation(MotionCurve.focus.animation(MotionDuration.standard), value: isFocused)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
