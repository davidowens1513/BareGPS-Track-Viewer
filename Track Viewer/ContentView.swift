import SwiftUI

struct ContentView: View {
    @State private var selectedTrackID: WalkingTrack.ID?
    @State private var searchText = ""
    @State private var mapStyle: MapStyle = .terrain
    @State private var showsTracks = true

    private let tracks = WalkingTrack.samples

    var body: some View {
        HSplitView {
            TrackSidebar(
                tracks: tracks,
                selectedTrackID: $selectedTrackID,
                searchText: $searchText,
                mapStyle: $mapStyle,
                showsTracks: $showsTracks
            )
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

            MapWorkspace(
                tracks: tracks,
                selectedTrackID: $selectedTrackID,
                mapStyle: mapStyle,
                showsTracks: showsTracks
            )
            .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TrackSidebar: View {
    let tracks: [WalkingTrack]
    @Binding var selectedTrackID: WalkingTrack.ID?
    @Binding var searchText: String
    @Binding var mapStyle: MapStyle
    @Binding var showsTracks: Bool

    private var filteredTracks: [WalkingTrack] {
        guard !searchText.isEmpty else { return tracks }
        return tracks.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.location.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()

            VStack(spacing: 12) {
                SearchField(text: $searchText)

                Picker("Map style", selection: $mapStyle) {
                    ForEach(MapStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Toggle("Show walking tracks", isOn: $showsTracks)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            Divider()

            TrackList(
                tracks: filteredTracks,
                selectedTrackID: $selectedTrackID
            )

            Divider()

            MapSourceFooter(mapStyle: mapStyle)
        }
        .background(.regularMaterial)
    }
}

private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.hiking")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 1) {
                Text("Walking Tracks")
                    .font(.headline)
                Text("Ireland and beyond")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search tracks", text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct TrackList: View {
    let tracks: [WalkingTrack]
    @Binding var selectedTrackID: WalkingTrack.ID?

    var body: some View {
        List(tracks, selection: $selectedTrackID) { track in
            TrackRow(track: track)
                .tag(track.id)
        }
        .listStyle(.sidebar)
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView.search
            }
        }
    }
}

private struct TrackRow: View {
    let track: WalkingTrack

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(track.name)
                .font(.body.weight(.medium))
                .lineLimit(1)

            HStack(spacing: 6) {
                Label(track.distance, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Text("•")
                Text(track.location)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct MapSourceFooter: View {
    let mapStyle: MapStyle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "map")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("MapLibre")
                    .font(.caption.weight(.semibold))
                Text(mapStyle.sourceDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
                .accessibilityLabel("Map source available")
        }
        .padding(12)
    }
}

private struct MapWorkspace: View {
    let tracks: [WalkingTrack]
    @Binding var selectedTrackID: WalkingTrack.ID?
    let mapStyle: MapStyle
    let showsTracks: Bool

    var body: some View {
        ZStack {
            MapCanvas(
                tracks: tracks,
                selectedTrackID: selectedTrackID,
                mapStyle: mapStyle,
                showsTracks: showsTracks
            )

            VStack {
                HStack(alignment: .top) {
                    MapLocationBadge(mapStyle: mapStyle)
                    Spacer()
                }

                Spacer()

                HStack(alignment: .bottom) {
                    Spacer()

                    if let selectedTrack = tracks.first(where: { $0.id == selectedTrackID }) {
                        TrackSummaryCard(track: selectedTrack)
                    }
                }
            }
            .padding(16)
        }
    }
}

private struct MapCanvas: View {
    let tracks: [WalkingTrack]
    let selectedTrackID: WalkingTrack.ID?
    let mapStyle: MapStyle
    let showsTracks: Bool

    var body: some View {
        MapLibreMapView(usesOpenBareMap: mapStyle == .terrain)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Interactive walking track map")
    }
}

private struct MapGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 80

        stride(from: rect.minX, through: rect.maxX, by: spacing).forEach { x in
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        stride(from: rect.minY, through: rect.maxY, by: spacing).forEach { y in
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        return path
    }
}

private struct TerrainContours: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        for index in 0..<7 {
            let inset = CGFloat(index) * 42
            let contourRect = CGRect(
                x: rect.midX - 330 + inset,
                y: rect.midY - 250 + inset * 0.7,
                width: 660 - inset * 1.6,
                height: 500 - inset * 1.15
            )
            path.addEllipse(in: contourRect)
        }

        return path
    }
}

private struct IrelandSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.02))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.25),
            control1: CGPoint(x: rect.width * 0.68, y: rect.height * 0.02),
            control2: CGPoint(x: rect.width * 0.82, y: rect.height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.55),
            control1: CGPoint(x: rect.width * 0.91, y: rect.height * 0.38),
            control2: CGPoint(x: rect.width * 0.76, y: rect.height * 0.48)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.94),
            control1: CGPoint(x: rect.width * 0.78, y: rect.height * 0.74),
            control2: CGPoint(x: rect.width * 0.70, y: rect.height * 0.92)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.76),
            control1: CGPoint(x: rect.width * 0.39, y: rect.height),
            control2: CGPoint(x: rect.width * 0.24, y: rect.height * 0.90)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.13, y: rect.height * 0.42),
            control1: CGPoint(x: rect.width * 0.06, y: rect.height * 0.67),
            control2: CGPoint(x: rect.width * 0.17, y: rect.height * 0.53)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.02),
            control1: CGPoint(x: rect.width * 0.04, y: rect.height * 0.19),
            control2: CGPoint(x: rect.width * 0.31, y: rect.height * 0.12)
        )
        path.closeSubpath()
        return path
    }
}

private struct TrackOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.72))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.43),
            control1: CGPoint(x: rect.width * 0.19, y: rect.height * 0.50),
            control2: CGPoint(x: rect.width * 0.35, y: rect.height * 0.61)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.67, y: rect.height * 0.29),
            control1: CGPoint(x: rect.width * 0.50, y: rect.height * 0.22),
            control2: CGPoint(x: rect.width * 0.59, y: rect.height * 0.42)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.18),
            control1: CGPoint(x: rect.width * 0.74, y: rect.height * 0.16),
            control2: CGPoint(x: rect.width * 0.78, y: rect.height * 0.26)
        )
        return path
    }
}

private struct TrackPins: View {
    let tracks: [WalkingTrack]
    let selectedTrackID: WalkingTrack.ID?

    var body: some View {
        ZStack {
            ForEach(Array(tracks.prefix(4).enumerated()), id: \.element.id) { index, track in
                Image(systemName: selectedTrackID == track.id ? "mappin.circle.fill" : "mappin.circle")
                    .font(.title)
                    .foregroundStyle(selectedTrackID == track.id ? .orange : .white)
                    .shadow(radius: 2)
                    .offset(
                        x: CGFloat(index - 1) * 90,
                        y: CGFloat((index % 2) * 100 - 70)
                    )
                    .accessibilityLabel(track.name)
            }
        }
    }
}

private struct MapLocationBadge: View {
    let mapStyle: MapStyle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .foregroundStyle(.green)
            Text("Island of Ireland")
                .font(.callout.weight(.semibold))
            Text("•")
                .foregroundStyle(.tertiary)
            Text(mapStyle.title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct MapControlStack: View {
    var body: some View {
        VStack(spacing: 0) {
            MapControlButton(title: "Zoom in", systemImage: "plus")
            Divider().frame(width: 30)
            MapControlButton(title: "Zoom out", systemImage: "minus")
            Divider().frame(width: 30)
            MapControlButton(title: "Find my location", systemImage: "location")
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(.white.opacity(0.18))
        }
    }
}

private struct MapControlButton: View {
    let title: LocalizedStringResource
    let systemImage: String

    var body: some View {
        Button {
            // Actions will forward to the MapLibre camera controller.
        } label: {
            Image(systemName: systemImage)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct ScaleBar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("20 km")
                .font(.caption2.weight(.medium))
            Rectangle()
                .fill(.primary)
                .frame(width: 72, height: 2)
        }
        .padding(9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct TrackSummaryCard: View {
    let track: WalkingTrack

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.hiking")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.headline)
                Text("\(track.distance) • \(track.duration) • \(track.difficulty.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                // The MapLibre camera will fit this track's bounds.
            } label: {
                Image(systemName: "scope")
            }
            .buttonStyle(.bordered)
            .help("Fit track on map")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.18))
        }
    }
}

private struct WalkingTrack: Identifiable, Equatable {
    let id: UUID
    let name: String
    let location: String
    let distance: String
    let duration: String
    let difficulty: Difficulty

    static let samples = [
        WalkingTrack(
            id: UUID(uuidString: "039015D6-0468-45A9-A5E6-80A66B7C9E72")!,
            name: "Glendalough Spinc",
            location: "Wicklow",
            distance: "9.5 km",
            duration: "3 hr",
            difficulty: .moderate
        ),
        WalkingTrack(
            id: UUID(uuidString: "93B986A8-0F4D-4B75-AB81-8FA7A12531B0")!,
            name: "Carrauntoohil Loop",
            location: "Kerry",
            distance: "12.8 km",
            duration: "5 hr",
            difficulty: .hard
        ),
        WalkingTrack(
            id: UUID(uuidString: "2A1F73C5-7B84-4E5D-B362-A91C6F4D2857")!,
            name: "Howth Cliff Path",
            location: "Dublin",
            distance: "7.8 km",
            duration: "2 hr",
            difficulty: .easy
        ),
        WalkingTrack(
            id: UUID(uuidString: "8F3D5C2B-9A17-4E60-B481-6D72A05F3C89")!,
            name: "Diamond Hill",
            location: "Galway",
            distance: "7.1 km",
            duration: "2.5 hr",
            difficulty: .moderate
        ),
        WalkingTrack(
            id: UUID(uuidString: "71C4A2E9-6D83-4B50-9F27-3A8E15D6C492")!,
            name: "Slieve Donard",
            location: "Down",
            distance: "9.2 km",
            duration: "4 hr",
            difficulty: .hard
        )
    ]
}

private enum Difficulty: String, Equatable {
    case easy
    case moderate
    case hard

    var title: LocalizedStringResource {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .hard: "Hard"
        }
    }
}

private enum MapStyle: String, CaseIterable, Identifiable {
    case terrain
    case outdoors

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .terrain: "Terrain"
        case .outdoors: "Outdoors"
        }
    }

    var sourceDescription: LocalizedStringResource {
        switch self {
        case .terrain: "OpenBareMap • Ireland"
        case .outdoors: "OpenTopo • Worldwide"
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .terrain:
            [Color(red: 0.18, green: 0.34, blue: 0.30), Color(red: 0.08, green: 0.20, blue: 0.24)]
        case .outdoors:
            [Color(red: 0.34, green: 0.39, blue: 0.28), Color(red: 0.15, green: 0.23, blue: 0.20)]
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 760)
}
