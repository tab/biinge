import Charts
import SwiftUI

struct ProfileView: View {
    let authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var sheet: ProfileSheet?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Avatar(email: authManager.user?.email ?? "", size: 60)
                        Text(authManager.user?.email ?? "")
                            .font(.biingeCallout)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        sheet = .statistics
                    } label: {
                        Label("Statistics", systemImage: "chart.pie")
                    }
                    Button {
                        sheet = .appearance
                    } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                }
                .foregroundStyle(.primary)

                Section {
                    Button {
                        sheet = .info(InfoItem(title: "About", sections: Self.about))
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    Button {
                        sheet = .info(InfoItem(title: "Privacy", sections: Self.privacy))
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    Button {
                        sheet = .info(InfoItem(title: "Terms", sections: Self.terms))
                    } label: {
                        Label("Terms", systemImage: "doc.text")
                    }
                }
                .foregroundStyle(.primary)

                Section {
                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        Text("Log Out")
                    }
                }

                Section {
                    Text("Version \(appVersion)")
                        .font(.biingeFootnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Profile")
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.environment["DEBUG_STATISTICS"] == "1" {
                    sheet = .statistics
                }
                #endif
            }
            .sheet(item: $sheet) { route in
                Group {
                    switch route {
                    case .statistics:
                        StatisticsView()
                    case .appearance:
                        AppearanceView(authManager: authManager)
                    case .info(let item):
                        InfoView(title: item.title, sections: item.sections)
                    }
                }
                .preferredColorScheme(colorScheme)
                .presentationDragIndicator(.hidden)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static let about: [InfoSection] = [
        InfoSection(heading: nil, body: "Biinge helps you track the films, TV shows and games you mean to get to, the ones "
            + "you're part-way through, and the ones you've finished — with your personal library synced across your devices."),
        InfoSection(heading: nil, body: "Film and TV metadata and imagery are provided by The Movie Database (TMDB). "
            + "Game metadata and imagery are provided by IGDB."),
    ]

    static let privacy: [InfoSection] = [
        InfoSection(heading: nil, body: "This policy explains what Biinge stores and how it is used. Biinge is a personal "
            + "watch-tracking app — it does not sell your data or show ads."),
        InfoSection(heading: "Information we store", body: "Your account details (email address and name), your appearance "
            + "preference, and the films, TV shows, episodes and games you track together with their state."),
        InfoSection(heading: "How it is used", body: "Your data is used only to run the app — to sync your library and show "
            + "your statistics. It is never sold, rented, or shared with advertisers."),
        InfoSection(heading: "Third-party services", body: "Biinge fetches film and TV metadata and imagery from The Movie "
            + "Database (TMDB), and game metadata and imagery from IGDB. Anonymized crash and performance diagnostics may "
            + "be collected to keep the app stable. Your library is never shared with these services."),
        InfoSection(heading: "Data retention", body: "Your data is kept while your account is active. You can request "
            + "deletion of your account and its associated data at any time."),
    ]

    static let terms: [InfoSection] = [
        InfoSection(heading: nil, body: "By using Biinge you agree to these terms. Biinge is provided for personal, "
            + "non-commercial use."),
        InfoSection(heading: "Your account", body: "You are responsible for activity under your account and for keeping your "
            + "credentials secure. Do not misuse the service or attempt to disrupt it."),
        InfoSection(heading: "Content and attribution", body: "Film and TV metadata and imagery are provided by The Movie "
            + "Database (TMDB), and game metadata and imagery by IGDB. Both remain the property of their respective "
            + "owners. This product uses the TMDB and IGDB APIs but is not endorsed or certified by either."),
        InfoSection(heading: "Availability", body: "Biinge is provided \"as is\" and \"as available\", without warranties of "
            + "any kind. Features may change and the service may be unavailable from time to time."),
        InfoSection(heading: "Changes", body: "These terms may be updated over time. Continued use of Biinge means you accept "
            + "the current version."),
    ]
}

/// The Profile sub-screens, each presented as a detail-style modal
private enum ProfileSheet: Identifiable {
    case statistics
    case appearance
    case info(InfoItem)

    var id: String {
        switch self {
        case .statistics: return "statistics"
        case .appearance: return "appearance"
        case .info(let item): return item.id
        }
    }
}

/// Shared chrome for Profile modals: dark backdrop, translucent close button, rounded-top card
struct ModalScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.biingeCard.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title)
                        .font(.biingeTitle1)
                        .foregroundStyle(.primary)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.top, 64)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

            CloseButton()
        }
    }
}

/// Chart palette: status hues for library bars, media hues for the watch-time donut
private enum StatPalette {
    static let want = Color(rgb: 0x999999)
    static let watching = Color(rgb: 0xEEC01E)
    static let watched = Color(rgb: 0x27AE60)
    static let moviesTime = Color(rgb: 0x8B5CF6)
    static let tvTime = Color(rgb: 0x22B8CF)
}

/// One status row in a library breakdown bar chart
private struct StatBar: Identifiable {
    let label: String
    let count: Int
    let color: Color
    var id: String { label }
}

/// One slice of the watch-time donut
private struct TimeSlice: Identifiable {
    let label: String
    let minutes: Int
    let color: Color
    var id: String { label }
}

struct StatisticsView: View {
    @Environment(\.apiClient) private var apiClient
    @State private var loaded: [StatsPeriod: AccountStats] = [:]
    @State private var period: StatsPeriod = Self.initialPeriod

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
        ModalScaffold(title: "Statistics") {
            VStack(alignment: .leading, spacing: 28) {
                periodChips

                // A period is only ever drawn from its own numbers, so switching chips
                // spins rather than showing another window's figures under the new label
                if let stats = loaded[period] {
                    content(stats)
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
    /// scenes, so coming back to a chip costs nothing
    private func load() async {
        guard let apiClient else { return }

        if let result = try? await apiClient.stats(period: period) {
            loaded[period] = result
        }
    }

    private var periodChips: some View {
        HStack(spacing: 8) {
            ForEach(StatsPeriod.allCases, id: \.self) { option in
                let isActive = option == period
                Button {
                    period = option
                } label: {
                    Text(option.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isActive ? Color.biingeBackground : Color.biingeGrayDark)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(isActive ? Color.biingeText : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: period)
    }

    @ViewBuilder
    private func content(_ stats: AccountStats) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            if let activity = stats.activity {
                watchActivity(activity)
            }
            watchTime(stats)
            breakdown(
                "Movies",
                bars: [
                    StatBar(label: period.wantLabel, count: stats.movies.want, color: StatPalette.want),
                    StatBar(label: "Watched", count: stats.movies.watched, color: StatPalette.watched),
                ],
                caption: "\(formatMinutes(stats.movies.minutes)) watched \(period.phrase)"
            )
            breakdown(
                "TV Shows",
                bars: [
                    StatBar(label: period.wantLabel, count: stats.series.want, color: StatPalette.want),
                    stats.series.watching.map { StatBar(label: "Watching", count: $0, color: StatPalette.watching) },
                    StatBar(label: "Watched", count: stats.series.watched, color: StatPalette.watched),
                ].compactMap { $0 },
                caption: "\(stats.episodes.watched) episodes · \(formatMinutes(stats.episodes.minutes)) watched \(period.phrase)"
            )
            if let games = stats.games {
                breakdown(
                    "Games",
                    bars: [
                        StatBar(label: period.wantLabel, count: games.want, color: StatPalette.want),
                        games.playing.map { StatBar(label: "Playing", count: $0, color: StatPalette.watching) },
                        StatBar(label: "Played", count: games.played, color: StatPalette.watched),
                    ].compactMap { $0 },
                    // "to beat" rather than "played": the minutes are IGDB's estimate for the games
                    // finished in the period, not time this user spent
                    caption: "\(formatMinutes(games.minutes)) to beat · finished \(period.phrase)"
                )
            }
        }
    }

    @ViewBuilder
    private func watchActivity(_ buckets: [AccountStats.Bucket]) -> some View {
        let total = buckets.reduce(0) { $0 + $1.totalMinutes }
        let step = axisStride(buckets.map(\.totalMinutes).max() ?? 0)
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Watch activity")
            if total > 0 {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Date", bucket.start, unit: period.unit),
                        y: .value("Minutes", bucket.movieMinutes)
                    )
                    .foregroundStyle(by: .value("Kind", "Movies"))
                    BarMark(
                        x: .value("Date", bucket.start, unit: period.unit),
                        y: .value("Minutes", bucket.tvMinutes)
                    )
                    .foregroundStyle(by: .value("Kind", "TV"))
                }
                .chartForegroundStyleScale(
                    domain: ["Movies", "TV"],
                    range: [StatPalette.moviesTime, StatPalette.tvTime]
                )
                .chartLegend(position: .bottom, spacing: 12)
                .chartYAxis {
                    AxisMarks(values: .stride(by: Double(step))) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text(axisLabel(minutes, step: step))
                            }
                        }
                    }
                }
                .chartXAxis {
                    switch period {
                    case .week:
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisTick()
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    case .month:
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisTick()
                            AxisValueLabel(format: .dateTime.day())
                        }
                    case .year:
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisTick()
                            AxisValueLabel(format: .dateTime.month(.narrow))
                        }
                    case .all:
                        AxisMarks(values: .stride(by: .year, count: labelStride(buckets.count))) { _ in
                            AxisTick()
                            AxisValueLabel(format: .dateTime.year())
                        }
                    }
                }
                .frame(height: 180)
                Text("\(formatMinutes(total)) \(period.phrase)")
                    .font(.biingeFootnote)
                    .foregroundStyle(Color.biingeGraniteGray)
            } else {
                Text(period == .all ? "No watch activity yet" : "No watch activity \(period.phrase)")
                    .font(.biingeFootnote)
                    .foregroundStyle(Color.biingeGraniteGray)
            }
        }
    }

    /// Y-axis step in minutes, scaled to the tallest bar so the axis carries about four marks
    ///
    /// The step has to come from the data: a fixed one draws a gridline per hour, which is
    /// three marks across a week and thousands across a whole history. Every candidate past
    /// an hour is a whole number of hours, and every candidate past a day a whole number of
    /// days, so a mark never lands mid-unit where two labels would round to the same text.
    private func axisStride(_ maxMinutes: Int) -> Int {
        let candidates = [15, 30, 60, 120, 360, 720, 1440, 4320, 10080, 20160, 43200, 86400]
        let target = max(15, maxMinutes / 4)

        return candidates.first { $0 >= target } ?? candidates[candidates.count - 1]
    }

    /// Names an axis mark in the coarsest unit its step lands on exactly
    private func axisLabel(_ minutes: Int, step: Int) -> String {
        if step >= 1440 { return "\(minutes / 1440)d" }
        if step >= 60 { return "\(minutes / 60)h" }

        return "\(minutes)m"
    }

    /// Thins labels to roughly six, so an all-time chart spanning many years stays readable
    private func labelStride(_ count: Int) -> Int {
        max(1, Int((Double(count) / 6.0).rounded(.up)))
    }

    @ViewBuilder
    private func watchTime(_ stats: AccountStats) -> some View {
        let total = stats.movies.minutes + stats.episodes.minutes
        let slices = [
            TimeSlice(label: "Movies", minutes: stats.movies.minutes, color: StatPalette.moviesTime),
            TimeSlice(label: "TV", minutes: stats.episodes.minutes, color: StatPalette.tvTime),
        ]

        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Watch time")
            if total > 0 {
                HStack(spacing: 24) {
                    donut(slices, total: total)
                        .frame(width: 116, height: 116)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(slices) { legendRow($0, total: total) }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text("No watch time yet")
                    .font(.biingeFootnote)
                    .foregroundStyle(Color.biingeGraniteGray)
            }
        }
    }

    private func donut(_ slices: [TimeSlice], total: Int) -> some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Minutes", slice.minutes),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 1) {
                Text(formatMinutes(total))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("total")
                    .font(.biingeFootnote)
                    .foregroundStyle(Color.biingeGraniteGray)
            }
            .padding(.horizontal, 8)
        }
    }

    private func legendRow(_ slice: TimeSlice, total: Int) -> some View {
        let pct = total > 0 ? Int((Double(slice.minutes) / Double(total) * 100).rounded()) : 0
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(slice.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(slice.label)
                    .font(.biingeCaption2)
                    .foregroundStyle(.primary)
                Text(formatMinutes(slice.minutes))
                    .font(.biingeFootnote)
                    .foregroundStyle(Color.biingeGraniteGray)
            }
            Spacer(minLength: 8)
            Text("\(pct)%")
                .font(.biingeCaption2)
                .monospacedDigit()
                .foregroundStyle(slice.color)
        }
    }

    @ViewBuilder
    private func breakdown(_ title: String, bars: [StatBar], caption: String) -> some View {
        let total = bars.reduce(0) { $0 + $1.count }
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(title)
            if total > 0 {
                VStack(spacing: 12) {
                    ForEach(bars.sorted { $0.count > $1.count }) { statBarRow($0, total: total) }
                }
                Text(caption)
                    .font(.biingeFootnote)
                    .foregroundStyle(Color.biingeGraniteGray)
            } else {
                Text("Nothing tracked yet")
                    .font(.biingeFootnote)
                    .foregroundStyle(Color.biingeGraniteGray)
            }
        }
    }

    /// One status row: label, a track filled to the status' share of the library, and the count
    private func statBarRow(_ bar: StatBar, total: Int) -> some View {
        let fraction = total > 0 ? Double(bar.count) / Double(total) : 0
        return HStack(spacing: 12) {
            Text(bar.label)
                .font(.biingeFootnote)
                .foregroundStyle(Color.biingeGraniteGray)
                .frame(width: 80, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.biingeSecondaryCard)
                    Capsule()
                        .fill(bar.color)
                        .frame(width: fraction > 0 ? max(4, geo.size.width * fraction) : 0)
                }
            }
            .frame(height: 10)
            Text("\(bar.count)")
                .font(.biingeCaption2)
                .monospacedDigit()
                .foregroundStyle(Color.biingeText)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray)
    }

    /// Renders a runtime down to the minute below a day, where whole hours alone would round a film away
    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        if weeks > 0 { return "\(weeks)w \(days % 7)d \(hours % 24)h" }
        if days > 0 { return "\(days)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

struct AppearanceView: View {
    let authManager: AuthManager
    @Environment(\.apiClient) private var apiClient

    var body: some View {
        ModalScaffold(title: "Appearance") {
            VStack(spacing: 0) {
                ForEach(Appearance.allCases, id: \.self) { option in
                    Button {
                        guard let apiClient else { return }
                        Task { await authManager.updateAppearance(option, using: apiClient) }
                    } label: {
                        HStack {
                            Text(option.rawValue.capitalized).foregroundStyle(.primary)
                            Spacer()
                            if authManager.user?.appearance == option {
                                Image(systemName: "checkmark").foregroundStyle(Color.biingePrimary)
                            }
                        }
                        .font(.biingeCallout)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option != Appearance.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }
}

/// One block of an info page, with an optional heading
struct InfoSection {
    let heading: String?
    let body: String
}

/// A titled info page presented as a modal sheet (About, Privacy, Terms)
struct InfoItem: Identifiable {
    var id: String { title }
    let title: String
    let sections: [InfoSection]
}

struct InfoView: View {
    let title: String
    let sections: [InfoSection]

    var body: some View {
        ModalScaffold(title: title) {
            ForEach(sections.indices, id: \.self) { index in
                let section = sections[index]
                VStack(alignment: .leading, spacing: 8) {
                    if let heading = section.heading {
                        Text(heading)
                            .font(.biingeSubhead)
                            .foregroundStyle(Color.biingeGraniteGray)
                    }
                    Text(section.body)
                        .font(.biingeBody)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
