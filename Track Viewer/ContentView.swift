import Foundation
import SwiftUI

struct ContentView: View {
    @State private var selectedTrackID: WalkingTrack.ID?
    @State private var searchText = ""
    @AppStorage("selectedMapStyle") private var mapStyle: MapStyle = .terrain
    @AppStorage("showsTracks") private var showsTracks = true
    @AppStorage("visibleOpenBareMapLayers") private var storedVisibleLayerNames = ""
    @State private var visibleOpenBareMapLayers = OpenBareMapLayer.defaultVisible
    @State private var trackRecords: [TrackRecord] = []
    @State private var matchingTrackRecords: [TrackRecord] = []
    @State private var selectedTrackNumber: String?
    @State private var showsOnlySearchResultsOnMap = false
    @State private var pendingDescriptionTrack: TrackRecord?
    @State private var presentedDescriptionTrack: TrackRecord?
    @State private var trackDataRevision = 0
    @State private var pendingDeleteTrack: TrackRecord?
    @State private var deletionErrorMessage: String?

    private let tracks = WalkingTrack.samples

    var body: some View {
        HSplitView {
            TrackSidebar(
                tracks: tracks,
                selectedTrackID: $selectedTrackID,
                searchText: $searchText,
                mapStyle: $mapStyle,
                showsTracks: $showsTracks,
                visibleOpenBareMapLayers: $visibleOpenBareMapLayers,
                matchingTrackRecords: matchingTrackRecords,
                selectedTrackNumber: $selectedTrackNumber,
                showsOnlySearchResultsOnMap: $showsOnlySearchResultsOnMap,
                nextTrackNumber: nextTrackNumber,
                didImportTrack: didImportTrack,
                requestDeleteTrack: { pendingDeleteTrack = $0 }
            )
            .frame(minWidth: 340, idealWidth: 470, maxWidth: 560)

            MapWorkspace(
                tracks: tracks,
                selectedTrackID: $selectedTrackID,
                mapStyle: mapStyle,
                showsTracks: showsTracks,
                visibleOpenBareMapLayers: visibleOpenBareMapLayers,
                selectedTrackNumber: selectedTrackNumber,
                visibleTrackIDs: showsOnlySearchResultsOnMap ? matchingTrackRecords.map(\.id) : nil,
                onTrackClick: handleMapTrackClick,
                trackDataRevision: trackDataRevision
            )
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if storedVisibleLayerNames.isEmpty {
                storeVisibleLayers(visibleOpenBareMapLayers)
            } else {
                let savedLayers = Set(
                    storedVisibleLayerNames.split(separator: ",").compactMap {
                        OpenBareMapLayer(rawValue: String($0))
                    }
                )
                visibleOpenBareMapLayers = savedLayers
            }
            guard trackRecords.isEmpty else { return }
            let records = TrackRecord.load()
            trackRecords = records
            matchingTrackRecords = TrackRecord.matches(records, query: searchText)
        }
        .onChange(of: searchText) { _, newValue in
            let matches = TrackRecord.matches(trackRecords, query: newValue)
            matchingTrackRecords = matches
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || matches.isEmpty {
                showsOnlySearchResultsOnMap = false
            }
        }
        .onChange(of: visibleOpenBareMapLayers) { _, newValue in
            storeVisibleLayers(newValue)
        }
        .alert(
            "Open Description?",
            isPresented: Binding(
                get: { pendingDescriptionTrack != nil },
                set: { if !$0 { pendingDescriptionTrack = nil } }
            ),
            presenting: pendingDescriptionTrack
        ) { record in
            Button("Open") {
                pendingDescriptionTrack = nil
                presentedDescriptionTrack = record
            }
            Button("Cancel", role: .cancel) {
                pendingDescriptionTrack = nil
            }
        } message: { record in
            Text("Open the description, photos, and comments for track \(record.id)?")
        }
        .sheet(item: $presentedDescriptionTrack) { record in
            TrackDescriptionView(record: record)
        }
        .alert(
            "Delete Track?",
            isPresented: Binding(
                get: { pendingDeleteTrack != nil },
                set: { if !$0 { pendingDeleteTrack = nil } }
            ),
            presenting: pendingDeleteTrack
        ) { record in
            Button("Yes", role: .destructive) { deleteTrack(record) }
            Button("No", role: .cancel) { pendingDeleteTrack = nil }
        } message: { record in
            Text("Delete track \(record.id)? This cannot be undone.")
        }
        .alert("Delete Failed", isPresented: Binding(
            get: { deletionErrorMessage != nil },
            set: { if !$0 { deletionErrorMessage = nil } }
        )) {
            Button("OK") { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "")
        }
    }

    private func handleMapTrackClick(_ trackID: String) {
        guard let record = trackRecords.first(where: { $0.id == trackID }) else { return }

        if !matchingTrackRecords.contains(where: { $0.id == trackID }) {
            searchText = trackID
            matchingTrackRecords = TrackRecord.matches(trackRecords, query: trackID)
        }
        selectedTrackNumber = trackID

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard selectedTrackNumber == trackID else { return }
            pendingDescriptionTrack = record
        }
    }

    private func storeVisibleLayers(_ layers: Set<OpenBareMapLayer>) {
        storedVisibleLayerNames = layers.map(\.rawValue).sorted().joined(separator: ",")
    }

    private var nextTrackNumber: String {
        let highestImportedNumber = trackRecords.compactMap { Int($0.id) }.filter { $0 >= 10_000 }.max()
        return String((highestImportedNumber ?? 9_999) + 1)
    }

    private func didImportTrack(_ trackID: String) {
        let records = TrackRecord.load()
        trackRecords = records
        searchText = trackID
        matchingTrackRecords = TrackRecord.matches(records, query: trackID)
        selectedTrackNumber = trackID
        trackDataRevision += 1
    }

    private func deleteTrack(_ record: TrackRecord) {
        do {
            try TrackLibrary.delete(trackID: record.id)
            pendingDeleteTrack = nil
            let records = TrackRecord.load()
            trackRecords = records
            matchingTrackRecords = TrackRecord.matches(records, query: searchText)
            if selectedTrackNumber == record.id {
                selectedTrackNumber = nil
            }
            if matchingTrackRecords.isEmpty {
                showsOnlySearchResultsOnMap = false
            }
            trackDataRevision += 1
        } catch {
            pendingDeleteTrack = nil
            deletionErrorMessage = error.localizedDescription
        }
    }
}

private struct TrackSidebar: View {
    let tracks: [WalkingTrack]
    @Binding var selectedTrackID: WalkingTrack.ID?
    @Binding var searchText: String
    @Binding var mapStyle: MapStyle
    @Binding var showsTracks: Bool
    @Binding var visibleOpenBareMapLayers: Set<OpenBareMapLayer>
    let matchingTrackRecords: [TrackRecord]
    @Binding var selectedTrackNumber: String?
    @Binding var showsOnlySearchResultsOnMap: Bool
    let nextTrackNumber: String
    let didImportTrack: (String) -> Void
    let requestDeleteTrack: (TrackRecord) -> Void

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

            VStack(alignment: .leading, spacing: 12) {
                SidebarControls(
                    mapStyle: $mapStyle,
                    showsTracks: $showsTracks,
                    visibleOpenBareMapLayers: $visibleOpenBareMapLayers,
                    nextTrackNumber: nextTrackNumber,
                    didImportTrack: didImportTrack
                )

                SearchField(text: $searchText)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            Divider()

            TrackSearchResultsGrid(
                records: matchingTrackRecords,
                hasQuery: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedTrackNumber: $selectedTrackNumber,
                showsOnlySearchResultsOnMap: $showsOnlySearchResultsOnMap,
                requestDeleteTrack: requestDeleteTrack
            )
        }
        .background(.regularMaterial)
    }
}

private struct SidebarControls: View {
    @Binding var mapStyle: MapStyle
    @Binding var showsTracks: Bool
    @Binding var visibleOpenBareMapLayers: Set<OpenBareMapLayer>
    let nextTrackNumber: String
    let didImportTrack: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                mapControls
                    .frame(width: 260, alignment: .leading)

                importControl
                    .frame(width: 240, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 12) {
                mapControls
                importControl
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var mapControls: some View {
        MapControls(
            mapStyle: $mapStyle,
            showsTracks: $showsTracks,
            visibleOpenBareMapLayers: $visibleOpenBareMapLayers
        )
    }

    private var importControl: some View {
        ImportTrackControl(
            nextTrackNumber: nextTrackNumber,
            didImport: didImportTrack
        )
    }
}

private struct MapControls: View {
    @Binding var mapStyle: MapStyle
    @Binding var showsTracks: Bool
    @Binding var visibleOpenBareMapLayers: Set<OpenBareMapLayer>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabeledContent {
                Picker("Map style", selection: $mapStyle) {
                    ForEach(MapStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            } label: {
                Label("Map style", systemImage: "map")
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)

            Divider()
                .padding(.leading, 34)

            HStack {
                Label("Walking tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath")

                Spacer()

                Toggle("Walking tracks", isOn: $showsTracks)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)

            Divider()
                .padding(.leading, 34)

            OpenBareMapLayerControls(visibleLayers: $visibleOpenBareMapLayers)
        }
        .font(.caption)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct OpenBareMapLayerControls: View {
    @Binding var visibleLayers: Set<OpenBareMapLayer>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("OpenBareMap layers", systemImage: "square.3.layers.3d")

            VStack(alignment: .leading, spacing: 7) {
                ForEach(OpenBareMapLayer.allCases) { layer in
                    Toggle(layer.title, isOn: binding(for: layer))
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(for layer: OpenBareMapLayer) -> Binding<Bool> {
        Binding(
            get: { visibleLayers.contains(layer) },
            set: { isVisible in
                if isVisible {
                    visibleLayers.insert(layer)
                } else {
                    visibleLayers.remove(layer)
                }
            }
        )
    }
}

private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.hiking")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 1) {
                Text("Track Viewer")
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

private struct TrackSearchResultsGrid: View {
    let records: [TrackRecord]
    let hasQuery: Bool
    @Binding var selectedTrackNumber: String?
    @Binding var showsOnlySearchResultsOnMap: Bool
    let requestDeleteTrack: (TrackRecord) -> Void
    @State private var sortColumn: TrackSortColumn = .date
    @State private var sortAscending = false

    private var sortedRecords: [TrackRecord] {
        records.sorted { left, right in
            let comparison = sortColumn.compare(left, right)
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(hasQuery ? "\(records.count) results" : "\(records.count) tracks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if hasQuery && !records.isEmpty {
                    HStack(spacing: 6) {
                        Text("Show on Map")
                        Toggle("Show on Map", isOn: $showsOnlySearchResultsOnMap)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 14)

            if records.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No tracks found")
                        .font(.callout.weight(.semibold))
                    Text("Try a location, activity, distance, date, or track number.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            TrackSearchResultsHeader(
                                sortColumn: sortColumn,
                                sortAscending: sortAscending,
                                selectColumn: selectSortColumn
                            )

                            ForEach(sortedRecords) { record in
                                TrackSearchResultRow(
                                    id: record.id,
                                    distance: record.distance,
                                    ascent: record.ascent,
                                    location: record.location,
                                    visitedDate: record.visitedDate,
                                    isSelected: selectedTrackNumber == record.id
                                ) {
                                    selectedTrackNumber = record.id
                                }
                                .id(record.id)
                                .contextMenu {
                                    Button("Delete Track…", role: .destructive) {
                                        requestDeleteTrack(record)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                    }
                    .onChange(of: selectedTrackNumber) { _, trackID in
                        guard let trackID else { return }
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation { proxy.scrollTo(trackID, anchor: .center) }
                        }
                    }
                }
            }
        }
        .padding(.top, 10)
    }

    private func selectSortColumn(_ column: TrackSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }
}

private struct TrackSearchResultsHeader: View {
    let sortColumn: TrackSortColumn
    let sortAscending: Bool
    let selectColumn: (TrackSortColumn) -> Void

    var body: some View {
        HStack(spacing: 8) {
            headerButton("Date", column: .date, width: 68, alignment: .leading)
            headerButton("Number", column: .number, width: 48, alignment: .leading)
            headerButton("Location", column: .location, width: 174, alignment: .leading)
            headerButton("Length", column: .length, width: 58, alignment: .trailing)
            headerButton("Ascent", column: .ascent, width: 52, alignment: .trailing)
        }
        .frame(width: 432, alignment: .leading)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    private func headerButton(
        _ title: String,
        column: TrackSortColumn,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Button {
            selectColumn(column)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
    }
}

private enum TrackSortColumn: Equatable {
    case date
    case number
    case location
    case length
    case ascent

    func compare(_ left: TrackRecord, _ right: TrackRecord) -> ComparisonResult {
        switch self {
        case .date:
            return left.visitedDateSortKey.compared(to: right.visitedDateSortKey)
        case .number:
            return left.numberSortKey.compared(to: right.numberSortKey)
        case .location:
            return left.location.localizedStandardCompare(right.location)
        case .length:
            return left.lengthSortKey.compared(to: right.lengthSortKey)
        case .ascent:
            return left.ascentSortKey.compared(to: right.ascentSortKey)
        }
    }
}

private extension Comparable {
    func compared(to other: Self) -> ComparisonResult {
        if self < other { return .orderedAscending }
        if self > other { return .orderedDescending }
        return .orderedSame
    }
}

private struct TrackSearchResultRow: View {
    let id: String
    let distance: String
    let ascent: String
    let location: String
    let visitedDate: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(visitedDate)
                        .frame(width: 68, alignment: .leading)
                    Text(id)
                        .frame(width: 48, alignment: .leading)
                    Text(location)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 174, alignment: .leading)
                    Text(distance)
                        .frame(width: 58, alignment: .trailing)
                    Text(ascent)
                        .frame(width: 52, alignment: .trailing)
                }
                .frame(width: 432, alignment: .leading)
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)

                Divider()
            }
            .frame(width: 432, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 432, alignment: .leading)
        .accessibilityElement(children: .combine)
        .help("Show track \(id) on map")
    }
}

private struct MapWorkspace: View {
    let tracks: [WalkingTrack]
    @Binding var selectedTrackID: WalkingTrack.ID?
    let mapStyle: MapStyle
    let showsTracks: Bool
    let visibleOpenBareMapLayers: Set<OpenBareMapLayer>
    let selectedTrackNumber: String?
    let visibleTrackIDs: [String]?
    let onTrackClick: (String) -> Void
    let trackDataRevision: Int

    var body: some View {
        ZStack {
            MapCanvas(
                tracks: tracks,
                selectedTrackID: selectedTrackID,
                mapStyle: mapStyle,
                showsTracks: showsTracks,
                visibleOpenBareMapLayers: visibleOpenBareMapLayers,
                selectedTrackNumber: selectedTrackNumber,
                visibleTrackIDs: visibleTrackIDs,
                onTrackClick: onTrackClick,
                trackDataRevision: trackDataRevision
            )

            VStack {
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
    let visibleOpenBareMapLayers: Set<OpenBareMapLayer>
    let selectedTrackNumber: String?
    let visibleTrackIDs: [String]?
    let onTrackClick: (String) -> Void
    let trackDataRevision: Int

    var body: some View {
        MapLibreMapView(
            usesOpenBareMap: mapStyle == .terrain,
            visibleOpenBareMapLayers: visibleOpenBareMapLayers,
            showsTracks: showsTracks,
            selectedTrackID: selectedTrackNumber,
            visibleTrackIDs: visibleTrackIDs,
            onTrackClick: onTrackClick
        )
            .id(trackDataRevision)
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

private struct TrackDescriptionView: View {
    let record: TrackRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TrackDescriptionHeader(
                        title: record.title,
                        number: record.id,
                        location: record.location,
                        distance: record.distance,
                        ascent: record.ascent,
                        date: record.visitedDate
                    )
                    TrackDescriptionText(text: record.descriptionText)

                    if !record.photos.isEmpty {
                        TrackPhotoGallery(photos: record.photos)
                    }

                    if !record.comments.isEmpty {
                        TrackCommentsSection(comments: record.comments)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Track Description")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 720)
    }
}

private struct TrackDescriptionHeader: View {
    let title: String
    let number: String
    let location: String
    let distance: String
    let ascent: String
    let date: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title.bold())
            Text("Track \(number) • \(date)")
                .foregroundStyle(.secondary)
            Text(location)
                .font(.headline)
            Text("\(distance) • \(ascent) ascent")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrackDescriptionText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.headline)
            Text(text.isEmpty ? "No description is available for this track." : text)
                .textSelection(.enabled)
        }
    }
}

private struct TrackPhotoGallery: View {
    let photos: [TrackPhoto]
    @State private var selectedPhoto: TrackPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 280), alignment: .top)],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(photos) { photo in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            selectedPhoto = photo
                        } label: {
                            AsyncImage(url: photo.url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 280, height: 210)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 280, height: 210)
                                        .clipped()
                                case .failure:
                                    ContentUnavailableView(
                                        "Photo unavailable",
                                        systemImage: "photo"
                                    )
                                    .frame(width: 280, height: 210)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel(photo.alt)
                        }
                        .buttonStyle(.plain)
                        .help("View photo")

                            if !photo.caption.isEmpty {
                                Text(photo.caption)
                                    .font(.caption)
                                    .lineLimit(3)
                                    .frame(width: 280, alignment: .leading)
                            }
                    }
                }
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            TrackPhotoViewer(photo: photo)
        }
    }
}

private struct TrackPhotoViewer: View {
    let photo: TrackPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            AsyncImage(url: photo.url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    ContentUnavailableView("Photo unavailable", systemImage: "photo")
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: 1_000, maxHeight: 750)

            if !photo.caption.isEmpty {
                Text(photo.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 520)
    }
}

private struct TrackCommentsSection: View {
    let comments: [TrackComment]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)

            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(comment.author)
                            .font(.subheadline.bold())
                        Spacer()
                        Text(comment.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(comment.body)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct TrackRecord: Identifiable {
    let id: String
    let title: String
    let searchableDetails: String
    let activity: TrackActivity
    let distance: String
    let ascent: String
    let location: String
    let visitedDate: String
    let uploadedDate: String
    let descriptionText: String
    let comments: [TrackComment]
    let photos: [TrackPhoto]

    var numberSortKey: Int { Int(id) ?? 0 }
    var lengthSortKey: Double { numericValue(from: distance) }
    var ascentSortKey: Double { numericValue(from: ascent) }

    var visitedDateSortKey: Int {
        let components = visitedDate.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return 0 }
        return (components[2] * 10_000) + (components[1] * 100) + components[0]
    }

    private func numericValue(from value: String) -> Double {
        let numericText = value.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        return Double(numericText) ?? 0
    }

    private struct RawRecord: Decodable {
        let id: String
        let title: String
        let descriptionText: String
        let listing: String
        let comments: [RawComment]
        let photos: [RawPhoto]

        enum CodingKeys: String, CodingKey {
            case id, title, listing, comments, photos
            case descriptionText = "description_text"
        }
    }

    private struct RawComment: Decodable {
        let author: String
        let dateDisplayed: String
        let bodyText: String

        enum CodingKeys: String, CodingKey {
            case author
            case dateDisplayed = "date_displayed"
            case bodyText = "body_text"
        }
    }

    private struct RawPhoto: Decodable {
        let url: String
        let caption: String
        let alt: String
    }

    static func load() -> [TrackRecord] {
        try? TrackLibrary.prepare()
        let bundledURL = Bundle.main.url(
            forResource: "TrackMetadata",
            withExtension: "json",
            subdirectory: "TrackData"
        ) ?? Bundle.main.url(
            forResource: "TrackMetadata",
            withExtension: "json"
        )
        let resourceURL = FileManager.default.fileExists(atPath: TrackLibrary.metadataURL.path)
            ? TrackLibrary.metadataURL
            : bundledURL

        guard
            let resourceURL,
            let data = try? Data(contentsOf: resourceURL),
            let rawRecords = try? JSONDecoder().decode([RawRecord].self, from: data)
        else {
            return []
        }

        return rawRecords.compactMap { rawRecord in
            let fields = rawRecord.listing.components(separatedBy: "\t")
            guard fields.count == 8 else { return nil }

            let searchableDetails = (
                [rawRecord.descriptionText]
                    + rawRecord.comments.map(\.bodyText)
                    + rawRecord.photos.flatMap { [$0.caption, $0.alt] }
            ).joined(separator: " ")

            return TrackRecord(
                id: rawRecord.id,
                title: rawRecord.title,
                searchableDetails: searchableDetails,
                activity: TrackActivity(rawValue: fields[2]) ?? .walk,
                distance: fields[3],
                ascent: fields[4].trimmingCharacters(in: .whitespaces),
                location: fields[5],
                visitedDate: fields[6].split(separator: " ", maxSplits: 1).last.map(String.init) ?? fields[6],
                uploadedDate: fields[7],
                descriptionText: rawRecord.descriptionText.closingBlankParagraphLines(),
                comments: rawRecord.comments.map {
                    TrackComment(
                        author: $0.author,
                        date: $0.dateDisplayed,
                        body: $0.bodyText.closingBlankParagraphLines()
                    )
                },
                photos: rawRecord.photos.compactMap {
                    guard let url = URL(string: $0.url) else { return nil }
                    return TrackPhoto(
                        url: url,
                        caption: $0.caption.closingBlankParagraphLines(),
                        alt: $0.alt
                    )
                }
            )
        }
    }

    static func matches(_ records: [TrackRecord], query: String) -> [TrackRecord] {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !terms.isEmpty else { return records }

        return records.filter { record in
            let searchableValues = [
                record.id,
                record.title,
                record.searchableDetails,
                record.activity.rawValue,
                record.distance,
                record.ascent,
                record.location,
                record.visitedDate,
                record.uploadedDate
            ]

            return terms.allSatisfy { term in
                searchableValues.contains { value in
                    value.localizedStandardContains(term)
                }
            }
        }
    }
}

private extension String {
    func closingBlankParagraphLines() -> String {
        replacingOccurrences(
            of: #"\n[ \t]*\n+"#,
            with: "\n",
            options: .regularExpression
        )
    }
}

private struct TrackComment: Identifiable {
    let author: String
    let date: String
    let body: String

    var id: String { "\(author)|\(date)|\(body)" }
}

private struct TrackPhoto: Identifiable {
    let url: URL
    let caption: String
    let alt: String

    var id: URL { url }
}

private enum TrackActivity: String, Decodable {
    case walk
    case run
    case cycle
}

private struct WalkingTrack: Identifiable, Equatable {
    let id: UUID
    let name: String
    let location: String
    let distance: String
    let duration: String
    let difficulty: Difficulty

    static let samples: [WalkingTrack] = []
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
        case .terrain: "OpenBareMap (Ireland only)"
        case .outdoors: "OpenTopo"
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
