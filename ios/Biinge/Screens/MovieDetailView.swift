import SwiftUI

struct MovieDetailView: View {
    let movieId: Int
    @Environment(\.apiClient) private var apiClient
    @Environment(MovieStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.presentMovie) private var presentMovie
    @Environment(\.presentPerson) private var presentPerson

    @State private var details: MovieDetails?
    @State private var isLoading = true
    @State private var showMenu = false
    /// Bumped when a state change lands, so the haptic fires with the UI rather than on the tap
    @State private var stateChanges = 0
    /// Bumped on the lighter commit: pinning and unpinning
    @State private var marks = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                if let details {
                    content(details)
                } else if isLoading {
                    ProgressView().tint(Color.biingeLoader)
                        .frame(maxWidth: .infinity).padding(.top, 160)
                } else {
                    DetailLoadError()
                }
            }
            .scrollIndicators(.hidden)

            CloseButton()
        }
        .background(Color.biingeBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sensoryFeedback(.success, trigger: stateChanges)
        .sensoryFeedback(.impact(weight: .light), trigger: marks)
        .overlay {
            if showMenu, let details {
                MovieActionMenu(
                    posterPath: details.posterPath,
                    state: store.currentState(id: movieId),
                    pinned: store.isPinned(id: movieId),
                    onAction: { action in Task { await handleMenu(action, details) } },
                    onCancel: { withAnimation(.spring(duration: 0.3, bounce: 0)) { showMenu = false } }
                )
            }
        }
    }

    private func content(_ movie: MovieDetails) -> some View {
        VStack(spacing: 0) {
            PosterImage(path: movie.posterPath, title: movie.title, size: "w500", cornerRadius: 12)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.7 }
                .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
                .overlay(alignment: .bottomTrailing) {
                    if let key = movie.videos.first?.key {
                        playButton(key).padding(12)
                    }
                }
                .padding(.top, 64)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text(movie.title).font(.biingeTitle1).foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    if let rating = movie.rating, rating > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill").font(.biingeTitle3).foregroundStyle(Color.biingePrimary)
                            Text(String(format: "%.1f", rating)).font(.biingeTitle2).fontWeight(.heavy).foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 15)

                HStack {
                    Text(formatDate(movie.releaseDate)).foregroundStyle(Color.biingeGraniteGray)
                    Spacer()
                    Text(formatRuntime(movie.runtime)).foregroundStyle(Color.biingeSpanishGray)
                    Spacer()
                    statusPill(movie.status)
                }
                .font(.biingeCallout)
                .padding(.horizontal, 15)

                MovieActionsView(movieId: movieId, details: movie, showMenu: $showMenu)
                    .padding(.horizontal, 15)

                if !movie.overview.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Synopsis").font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray)
                        Text(movie.overview).font(.biingeBody).foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 15)
                }

                if !movie.credits.isEmpty {
                    creditsSection(movie.credits)
                }
                if !movie.recommendations.isEmpty {
                    recommendationsSection(movie.recommendations)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailCardBackground()
        }
    }

    private func creditsSection(_ credits: [CreditPerson]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cast and crew").font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray).padding(.horizontal, 15)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(credits) { person in
                        Button {
                            presentPerson(person.id)
                        } label: {
                            VStack(spacing: 6) {
                                ProfileCircle(path: person.profilePath, size: 72, grayscale: true)
                                Text(person.name).font(.biingeCaption2).foregroundStyle(.primary)
                                    .lineLimit(2).multilineTextAlignment(.center)
                                Text(person.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 88)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 15)
            }
        }
    }

    private func recommendationsSection(_ items: [Recommendation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommendations").font(.biingeSubhead).foregroundStyle(Color.biingeGraniteGray).padding(.horizontal, 15)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            presentMovie(item.id)
                        } label: {
                            PosterImage(path: item.posterPath, title: item.title, size: "w342").frame(width: 120)
                                .overlay(alignment: .topLeading) {
                                    if isTracked(item) { WatchedBadge() }
                                }
                        }
                        .buttonStyle(.pressable)
                        .detailTransitionSource("movie-\(item.id)")
                    }
                }
                .padding(.horizontal, 15)
            }
        }
    }

    /// Live store membership, with the response's snapshot as fallback until the library loads
    private func isTracked(_ item: Recommendation) -> Bool {
        store.currentState(id: item.id) != nil
            || (!store.hasLoaded && (item.state ?? WatchState.none) != WatchState.none)
    }

    private func playButton(_ key: String) -> some View {
        Button {
            if let url = URL(string: "https://www.youtube.com/watch?v=\(key)") { openURL(url) }
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5), in: Circle())
        }
    }

    @ViewBuilder
    private func statusPill(_ status: String?) -> some View {
        if let status, !status.isEmpty {
            Text(status)
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(Color.biingeTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .overlay { Capsule().strokeBorder(Color.biingeTextSecondary, lineWidth: 2) }
        }
    }

    private func formatDate(_ raw: String?) -> String {
        guard let raw, raw.count >= 10 else { return "" }
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return "" }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    private func formatRuntime(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "" }
        return "\(minutes / 60)h\(minutes % 60)m"
    }

    private func load() async {
        guard let apiClient else { return }
        isLoading = true
        // load the library too — opened from Search, the state pill would read an empty store
        async let libraryLoad: Void = store.loadIfNeeded()
        details = try? await apiClient.movieDetails(id: movieId)
        isLoading = false
        if let details {
            store.refreshMetadata(id: movieId, title: details.title, posterPath: details.posterPath)
        }
        await libraryLoad
    }

    private func handleMenu(_ action: MovieActionMenu.MenuAction, _ movie: MovieDetails) async {
        // the menu stays open on actions; only Cancel dismisses it
        switch action {
        case .toggleWant:
            await store.toggle(id: movieId, title: movie.title, posterPath: movie.posterPath, runtime: movie.runtime ?? 0, target: .want)
            stateChanges += 1
        case .toggleWatched:
            await store.toggle(id: movieId, title: movie.title, posterPath: movie.posterPath, runtime: movie.runtime ?? 0, target: .watched)
            stateChanges += 1
        case .pin:
            await store.setPinned(id: movieId, pinned: true)
            marks += 1
        case .unpin:
            await store.setPinned(id: movieId, pinned: false)
            marks += 1
        }
    }
}

/// The action row on a movie: white Want/Watched pills, or a single accent pill when tracked
struct MovieActionsView: View {
    let movieId: Int
    let details: MovieDetails
    @Binding var showMenu: Bool
    @Environment(MovieStore.self) private var store
    /// Bumped when a state change lands, so the haptic fires with the UI rather than on the tap
    @State private var stateChanges = 0

    var body: some View {
        let state = store.currentState(id: movieId)
        Group {
            if state == .want || state == .watched {
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0)) { showMenu = true }
                } label: {
                    Text(state == .want ? "Want" : "Watched")
                        .font(.biingeCallout).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Color.biingeAccent, in: Capsule())
                }
                .buttonStyle(.pressable)
            } else {
                HStack(spacing: 10) {
                    actionPill("Want") { toggle(.want) }
                    actionPill("Watched") { toggle(.watched) }
                }
            }
        }
        .sensoryFeedback(.success, trigger: stateChanges)
    }

    private func toggle(_ target: WatchState) {
        Task {
            await store.toggle(
                id: movieId, title: details.title, posterPath: details.posterPath,
                runtime: details.runtime ?? 0, target: target
            )
            stateChanges += 1
        }
    }

    private func actionPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.biingeCallout).fontWeight(.semibold)
                .foregroundStyle(Color.biingeBackground)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Color.biingeText, in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// The full-screen action menu shown when tapping a tracked movie's state pill
struct MovieActionMenu: View {
    let posterPath: String
    let state: WatchState?
    let pinned: Bool
    let onAction: (MenuAction) -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    enum MenuAction {
        case toggleWant, toggleWatched, pin, unpin
    }

    var body: some View {
        ZStack {
            // one solid scrim where the user asked for less transparency, the frosted pair otherwise
            if reduceTransparency {
                Color.black.opacity(0.82).ignoresSafeArea()
            } else {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                Color.black.opacity(0.4).ignoresSafeArea()
            }

            Button(action: onCancel) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Button(action: onCancel) {
                    PosterImage(path: posterPath, title: "", size: "w342", cornerRadius: 12)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.55 }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close")

                VStack(spacing: 2) {
                    ForEach(options, id: \.title) { option in
                        Button(action: option.action) {
                            Text(option.title)
                                .font(.biingeBody).fontWeight(.semibold)
                                .foregroundStyle(Color.biingeText.opacity(0.7))
                                .padding(10)
                        }
                        .buttonStyle(.pressable)
                    }
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.biingeBody).fontWeight(.semibold)
                            .foregroundStyle(Color.biingeText.opacity(0.7))
                            .padding(10)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 15)
            // the menu materialises out of the scrim instead of fading flat onto it
            .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
        }
        .transition(.opacity)
    }

    private var options: [(title: String, action: () -> Void)] {
        switch state {
        case .want:
            return [
                ("Remove from Want", { onAction(.toggleWant) }),
                ("Move to Watched", { onAction(.toggleWatched) }),
                (pinned ? "Unpin" : "Pin", { onAction(pinned ? .unpin : .pin) }),
            ]
        case .watched:
            return [
                ("Remove from Watched", { onAction(.toggleWatched) }),
                ("Move to Want", { onAction(.toggleWant) }),
                (pinned ? "Unpin" : "Pin", { onAction(pinned ? .unpin : .pin) }),
            ]
        default:
            return [
                ("Want", { onAction(.toggleWant) }),
                ("Watched", { onAction(.toggleWatched) }),
            ]
        }
    }
}

/// Shared error state for detail screens (e.g. missing TMDB token)
struct DetailLoadError: View {
    var body: some View {
        ContentUnavailableView(
            "Couldn't load details",
            systemImage: "exclamationmark.triangle",
            description: Text("Please try again.")
        )
        .padding(.top, 80)
    }
}
