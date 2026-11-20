import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum TrackLibrary {
    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Track Viewer", isDirectory: true)
    }

    static var metadataURL: URL {
        directoryURL.appendingPathComponent("TrackMetadata.json")
    }

    static var geoJSONURL: URL {
        directoryURL.appendingPathComponent("OnzyTracks.geojson")
    }

    private static var photosURL: URL {
        directoryURL.appendingPathComponent("photos", isDirectory: true)
    }

    static func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try manager.createDirectory(at: photosURL, withIntermediateDirectories: true)

        if !manager.fileExists(atPath: metadataURL.path) {
            guard let seed = Bundle.main.url(
                forResource: "TrackMetadata",
                withExtension: "json",
                subdirectory: "TrackData"
            ) ?? Bundle.main.url(forResource: "TrackMetadata", withExtension: "json") else {
                throw TrackImportError.missingSeedData
            }
            try manager.copyItem(at: seed, to: metadataURL)
        }

        if !manager.fileExists(atPath: geoJSONURL.path) {
            guard let seed = Bundle.main.url(
                forResource: "OnzyTracks",
                withExtension: "geojson",
                subdirectory: "TrackData"
            ) ?? Bundle.main.url(forResource: "OnzyTracks", withExtension: "geojson") else {
                throw TrackImportError.missingSeedData
            }
            try manager.copyItem(at: seed, to: geoJSONURL)
        }
    }

    static func add(_ draft: TrackImportDraft) throws {
        try prepare()

        let metadataData = try Data(contentsOf: metadataURL)
        let geoJSONData = try Data(contentsOf: geoJSONURL)
        guard var metadata = try JSONSerialization.jsonObject(with: metadataData) as? [[String: Any]],
              var geoJSON = try JSONSerialization.jsonObject(with: geoJSONData) as? [String: Any],
              var features = geoJSON["features"] as? [[String: Any]]
        else {
            throw TrackImportError.invalidLibrary
        }

        let trackID = draft.number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trackID.isEmpty, !metadata.contains(where: { $0["id"] as? String == trackID }) else {
            throw TrackImportError.duplicateTrackNumber
        }
        guard draft.coordinates.count >= 2 else {
            throw TrackImportError.noTrackPoints
        }

        let storedPhotos = try draft.photos.map { photo -> [String: Any] in
            let fileExtension = URL(fileURLWithPath: photo.filename).pathExtension
            let filename = UUID().uuidString + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
            let destination = photosURL.appendingPathComponent(filename)
            try photo.data.write(to: destination, options: .atomic)
            return [
                "url": destination.absoluteString,
                "caption": photo.caption,
                "alt": photo.caption.isEmpty ? "Photo for track \(trackID)" : photo.caption,
                "source": "imported",
                "status": "saved",
                "file": "photos/\(filename)"
            ]
        }

        let comments: [[String: Any]]
        if draft.commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            comments = []
        } else {
            comments = [[
                "author": draft.commentAuthor.trimmingCharacters(in: .whitespacesAndNewlines),
                "date_displayed": draft.date.formatted(.dateTime.month(.abbreviated).year()),
                "body_text": draft.commentBody
            ]]
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateFormat = "EEE dd-MM-yy"
        let dateText = formatter.string(from: draft.date)
        let distanceText = String(format: "%.1fkm", draft.distanceKilometres)
        let ascentText = "\(Int(draft.ascentMetres.rounded()))m"
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)

        metadata.append([
            "id": trackID,
            "title": title,
            "source_url": draft.sourceURL,
            "description_text": draft.descriptionText,
            "comments_state": comments.isEmpty ? "none displayed" : "present",
            "gallery_photos": [],
            "errors": [],
            "listing": "Imported\t\(trackID)\twalk\t\(distanceText)\t\(ascentText) \t\(location)\t\(dateText)\t\(dateText)",
            "comments": comments,
            "gallery_checked": true,
            "photos": storedPhotos
        ])

        features.append([
            "type": "Feature",
            "id": trackID,
            "properties": [
                "id": trackID,
                "name": "Track/\(trackID) \(title)"
            ],
            "geometry": [
                "type": "LineString",
                "coordinates": draft.coordinates.map { [$0.longitude, $0.latitude] }
            ]
        ])
        geoJSON["features"] = features

        let updatedMetadata = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let updatedGeoJSON = try JSONSerialization.data(withJSONObject: geoJSON)
        try updatedMetadata.write(to: metadataURL, options: .atomic)
        do {
            try updatedGeoJSON.write(to: geoJSONURL, options: .atomic)
        } catch {
            try? metadataData.write(to: metadataURL, options: .atomic)
            throw error
        }
    }

    static func delete(trackID: String) throws {
        try prepare()

        let metadataData = try Data(contentsOf: metadataURL)
        let geoJSONData = try Data(contentsOf: geoJSONURL)
        guard var metadata = try JSONSerialization.jsonObject(with: metadataData) as? [[String: Any]],
              var geoJSON = try JSONSerialization.jsonObject(with: geoJSONData) as? [String: Any],
              var features = geoJSON["features"] as? [[String: Any]]
        else {
            throw TrackImportError.invalidLibrary
        }

        let record = metadata.first { $0["id"] as? String == trackID }
        metadata.removeAll { $0["id"] as? String == trackID }
        features.removeAll { feature in
            if feature["id"] as? String == trackID { return true }
            let properties = feature["properties"] as? [String: Any]
            return properties?["id"] as? String == trackID
        }
        geoJSON["features"] = features

        let updatedMetadata = try JSONSerialization.data(
            withJSONObject: metadata,
            options: [.prettyPrinted, .sortedKeys]
        )
        let updatedGeoJSON = try JSONSerialization.data(withJSONObject: geoJSON)
        try updatedMetadata.write(to: metadataURL, options: .atomic)
        do {
            try updatedGeoJSON.write(to: geoJSONURL, options: .atomic)
        } catch {
            try? metadataData.write(to: metadataURL, options: .atomic)
            throw error
        }

        let photos = record?["photos"] as? [[String: Any]] ?? []
        for photo in photos {
            guard let relativePath = photo["file"] as? String,
                  relativePath.hasPrefix("photos/")
            else { continue }
            try? FileManager.default.removeItem(
                at: directoryURL.appendingPathComponent(relativePath)
            )
        }
    }
}

enum TrackImportError: LocalizedError {
    case missingSeedData
    case invalidLibrary
    case invalidGPX
    case noTrackPoints
    case duplicateTrackNumber
    case invalidMountainViewsNumber
    case mountainViewsTrackUnavailable
    case invalidMountainViewsTrack

    var errorDescription: String? {
        switch self {
        case .missingSeedData: "The original track files could not be found."
        case .invalidLibrary: "The working track library is not valid."
        case .invalidGPX: "The selected file is not a valid GPX track."
        case .noTrackPoints: "The GPX file does not contain enough track points."
        case .duplicateTrackNumber: "That track number is already in the library."
        case .invalidMountainViewsNumber: "Enter a valid MountainViews track number."
        case .mountainViewsTrackUnavailable: "That MountainViews track could not be downloaded."
        case .invalidMountainViewsTrack: "MountainViews returned a track page that could not be read."
        }
    }
}

struct TrackCoordinate: Equatable {
    let latitude: Double
    let longitude: Double
    let elevation: Double?
}

struct ImportedPhoto: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
    var caption = ""
}

struct TrackImportDraft: Identifiable {
    let id = UUID()
    var number: String
    var title: String
    var location = ""
    var date = Date()
    var descriptionText = ""
    var commentAuthor = ""
    var commentBody = ""
    var photos: [ImportedPhoto] = []
    var sourceURL = ""
    let coordinates: [TrackCoordinate]
    let distanceKilometres: Double
    let ascentMetres: Double
}

final class GPXTrackParser: NSObject, XMLParserDelegate {
    private var coordinates: [TrackCoordinate] = []
    private var currentLatitude: Double?
    private var currentLongitude: Double?
    private var currentElevation: Double?
    private var currentText = ""
    private var parsedName = ""

    static func parse(data: Data, nextNumber: String) throws -> TrackImportDraft {
        let delegate = GPXTrackParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.coordinates.count >= 2 else {
            throw parser.parserError ?? TrackImportError.invalidGPX
        }

        var distance = 0.0
        var ascent = 0.0
        for (previous, current) in zip(delegate.coordinates, delegate.coordinates.dropFirst()) {
            distance += Self.distance(from: previous, to: current)
            if let previousElevation = previous.elevation,
               let currentElevation = current.elevation,
               currentElevation > previousElevation {
                ascent += currentElevation - previousElevation
            }
        }

        return TrackImportDraft(
            number: nextNumber,
            title: "",
            coordinates: delegate.coordinates,
            distanceKilometres: distance / 1_000,
            ascentMetres: ascent
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        if elementName == "trkpt" {
            currentLatitude = attributeDict["lat"].flatMap(Double.init)
            currentLongitude = attributeDict["lon"].flatMap(Double.init)
            currentElevation = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "ele", currentLatitude != nil {
            currentElevation = Double(value)
        } else if elementName == "name", parsedName.isEmpty {
            parsedName = value
        } else if elementName == "trkpt",
                  let latitude = currentLatitude,
                  let longitude = currentLongitude {
            coordinates.append(
                TrackCoordinate(latitude: latitude, longitude: longitude, elevation: currentElevation)
            )
            currentLatitude = nil
            currentLongitude = nil
            currentElevation = nil
        }
    }

    private static func distance(from start: TrackCoordinate, to end: TrackCoordinate) -> Double {
        let radius = 6_371_000.0
        let latitudeDelta = (end.latitude - start.latitude) * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

enum MountainViewsTrackImporter {
    static func fetch(trackNumber: String) async throws -> TrackImportDraft {
        let number = trackNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty, number.allSatisfy(\.isNumber),
              let url = URL(string: "https://mountainviews.ie/track/\(number)/")
        else {
            throw TrackImportError.invalidMountainViewsNumber
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 Track Viewer", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else {
            throw TrackImportError.mountainViewsTrackUnavailable
        }

        guard let jsonText = capture(#"trackJSONStr:\s*'([^']+)'"#, in: html),
              let jsonData = jsonText.data(using: .utf8),
              let feature = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let geometry = feature["geometry"] as? [String: Any],
              let lineStrings = geometry["coordinates"] as? [[[Double]]]
        else {
            throw TrackImportError.invalidMountainViewsTrack
        }

        let coordinates = lineStrings.flatMap { line in
            line.compactMap { point -> TrackCoordinate? in
                guard point.count >= 2 else { return nil }
                return TrackCoordinate(latitude: point[1], longitude: point[0], elevation: nil)
            }
        }
        guard coordinates.count >= 2 else {
            throw TrackImportError.noTrackPoints
        }

        let title = capture(#"<span class="h4">(.*?)</span>"#, in: html).map(plainText) ?? ""
        let location = capture(#"Track/\d+ in area near (.*?) \(Ireland\)"#, in: html).map(plainText) ?? ""
        let ascent = capture(#"Ascent:\s*</span>\s*([0-9.]+)m"#, in: html).flatMap(Double.init) ?? 0
        let statedDistance = capture(#"Length:\s*</span>\s*([0-9.]+)km"#, in: html).flatMap(Double.init)
        let descriptionHTML = capture(
            #"<div id="trackDetailView"[^>]*>(.*?)<div id="trackDetailRows""#,
            in: html
        ) ?? ""
        let uploadedDate = capture(#"Uploaded on:\s*([^<,(]+(?:,[^<(]+)?)\s*\("#, in: html)
            .flatMap(parseDate) ?? Date()
        let photos = await fetchPhotos(trackNumber: number, referringPage: url)

        return TrackImportDraft(
            number: number,
            title: title,
            location: location,
            date: uploadedDate,
            descriptionText: plainText(descriptionHTML),
            photos: photos,
            sourceURL: url.absoluteString,
            coordinates: coordinates,
            distanceKilometres: statedDistance ?? distance(of: coordinates) / 1_000,
            ascentMetres: ascent
        )
    }

    private static func fetchPhotos(trackNumber: String, referringPage: URL) async -> [ImportedPhoto] {
        guard let galleryURL = URL(string: "https://mountainviews.ie/ajax/ajx_galleryFeed.php") else {
            return []
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "q", value: "action=trkGallery&trkUnitId=\(trackNumber)")
        ]
        var request = URLRequest(url: galleryURL)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 Track Viewer", forHTTPHeaderField: "User-Agent")
        request.setValue(referringPage.absoluteString, forHTTPHeaderField: "Referer")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pictureBase = payload["picBase"] as? String,
              let galleryItems = payload["galleryData"] as? [[String: Any]]
        else {
            return []
        }

        let ownItems = galleryItems.filter { item in
            guard let path = item["href"] as? String else { return false }
            return path.contains("picmvtrk-\(trackNumber)-")
        }

        var photos: [ImportedPhoto] = []
        for item in ownItems {
            guard let path = item["href"] as? String,
                  let imageURL = URL(string: pictureBase + "/" + path),
                  let (imageData, imageResponse) = try? await URLSession.shared.data(from: imageURL),
                  let imageHTTPResponse = imageResponse as? HTTPURLResponse,
                  imageHTTPResponse.statusCode == 200,
                  NSImage(data: imageData) != nil
            else { continue }

            let titleHTML = item["title"] as? String ?? ""
            let captionHTML = capture(#"<b>(.*?)</b>"#, in: titleHTML) ?? titleHTML
            var photo = ImportedPhoto(data: imageData, filename: imageURL.lastPathComponent)
            photo.caption = plainText(captionHTML)
            photos.append(photo)
        }
        return photos
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captureRange])
    }

    private static func plainText(_ html: String) -> String {
        let prepared = html
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        guard let data = prepared.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
              )
        else { return normalizeParagraphSpacing(prepared) }
        return normalizeParagraphSpacing(
            attributed.string
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        )
    }

    private static func normalizeParagraphSpacing(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy"
        return formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func distance(of coordinates: [TrackCoordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { result, pair in
            let radius = 6_371_000.0
            let latitudeDelta = (pair.1.latitude - pair.0.latitude) * .pi / 180
            let longitudeDelta = (pair.1.longitude - pair.0.longitude) * .pi / 180
            let startLatitude = pair.0.latitude * .pi / 180
            let endLatitude = pair.1.latitude * .pi / 180
            let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
                + cos(startLatitude) * cos(endLatitude)
                * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
            return result + radius * 2 * atan2(sqrt(a), sqrt(1 - a))
        }
    }
}

struct ImportTrackControl: View {
    let nextTrackNumber: String
    let didImport: (String) -> Void
    @State private var isChoosingGPX = false
    @State private var isRequestingMountainViewsTrack = false
    @State private var isDownloadingMountainViewsTrack = false
    @State private var mountainViewsTrackNumberToDownload: String?
    @State private var draft: TrackImportDraft?
    @State private var errorMessage: String?

    private static let gpxType = UTType(filenameExtension: "gpx") ?? .xml

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Add a track", systemImage: "plus.circle")
                .font(.caption.weight(.semibold))

            Button {
                isChoosingGPX = true
            } label: {
                Text("Import Track Directly")
                    .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 14)

            Color.clear
                .frame(height: 5)
                .accessibilityHidden(true)

            Button {
                isRequestingMountainViewsTrack = true
            } label: {
                Text("Add Track ex. MV")
                    .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .center)
            .disabled(isDownloadingMountainViewsTrack)
            .sheet(
                isPresented: $isRequestingMountainViewsTrack,
                onDismiss: downloadRequestedMountainViewsTrack
            ) {
                MountainViewsTrackNumberView { number in
                    mountainViewsTrackNumberToDownload = number
                    isRequestingMountainViewsTrack = false
                }
            }

            if isDownloadingMountainViewsTrack {
                ProgressView("Downloading…")
                    .controlSize(.small)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .fileImporter(
            isPresented: $isChoosingGPX,
            allowedContentTypes: [Self.gpxType]
        ) { result in
            do {
                let url = try result.get()
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                draft = try GPXTrackParser.parse(data: Data(contentsOf: url), nextNumber: nextTrackNumber)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $draft) { draft in
            TrackImportReviewView(initialDraft: draft) { savedDraft in
                do {
                    try TrackLibrary.add(savedDraft)
                    self.draft = nil
                    didImport(savedDraft.number)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func downloadRequestedMountainViewsTrack() {
        guard let number = mountainViewsTrackNumberToDownload else { return }
        mountainViewsTrackNumberToDownload = nil
        isDownloadingMountainViewsTrack = true
        Task {
            do {
                draft = try await MountainViewsTrackImporter.fetch(trackNumber: number)
            } catch {
                errorMessage = error.localizedDescription
            }
            isDownloadingMountainViewsTrack = false
        }
    }
}

private struct MountainViewsTrackNumberView: View {
    @State private var trackNumber = ""
    @Environment(\.dismiss) private var dismiss
    let download: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Track from MountainViews")
                .font(.title2.weight(.semibold))

            Text("Enter the MountainViews track number.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("MV track number")
                    .frame(width: 120, alignment: .leading)
                LeftAlignedTextField(
                    text: $trackNumber,
                    accessibilityLabel: "MountainViews track number"
                )
                .frame(height: 26)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Download") { download(trackNumber) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trackNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct TrackImportReviewView: View {
    @State private var draft: TrackImportDraft
    @State private var isChoosingPhotos = false
    @State private var selectedPhoto: ImportedPhoto?
    @Environment(\.dismiss) private var dismiss
    let save: (TrackImportDraft) -> Void

    init(initialDraft: TrackImportDraft, save: @escaping (TrackImportDraft) -> Void) {
        _draft = State(initialValue: initialDraft)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route Preview") {
                    ImportedTrackPreview(coordinates: draft.coordinates)
                        .frame(height: 180)
                    HStack(spacing: 28) {
                        LabeledContent(
                            "Length (m)",
                            value: draft.distanceKilometres,
                            format: .number.precision(.fractionLength(1))
                        )
                        LabeledContent(
                            "Ascent (m)",
                            value: draft.ascentMetres,
                            format: .number.precision(.fractionLength(0))
                        )
                    }
                }

                Section("Track Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        ImportLabeledTextField(title: "Number", text: $draft.number)
                        ImportLabeledTextField(title: "Title", text: $draft.title)
                        ImportLabeledTextField(title: "Location", text: $draft.location)
                        ImportLabeledDateField(title: "Date", date: $draft.date)
                        ImportLabeledMultilineField(
                            title: "Description",
                            text: $draft.descriptionText,
                            lineLimit: 8...20
                        )
                    }
                }

                Section("Photos") {
                    Button("Add Photos…") { isChoosingPhotos = true }
                    ForEach($draft.photos) { $photo in
                        HStack(alignment: .top) {
                            if let image = NSImage(data: photo.data) {
                                Button {
                                    selectedPhoto = photo
                                } label: {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 54)
                                        .clipped()
                                }
                                .buttonStyle(.plain)
                                .help("View photo")
                                .accessibilityLabel(photo.caption.isEmpty ? "View photo" : photo.caption)
                            }
                            ImportLabeledTextField(title: "Caption", text: $photo.caption)
                        }
                    }
                }

            }
            .formStyle(.grouped)
            .navigationTitle("Import Track")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Track") { save(draft) }
                        .disabled(
                            draft.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || draft.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 650)
        .sheet(item: $selectedPhoto) { photo in
            ImportedPhotoViewer(photo: photo)
        }
        .fileImporter(
            isPresented: $isChoosingPhotos,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard let urls = try? result.get() else { return }
            for url in urls {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    draft.photos.append(ImportedPhoto(data: data, filename: url.lastPathComponent))
                }
            }
        }
    }
}

private struct ImportedPhotoViewer: View {
    let photo: ImportedPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            if let image = NSImage(data: photo.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 1_000, maxHeight: 750)
            }
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

private struct ImportLabeledTextField: View {
    let title: LocalizedStringResource
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .frame(width: 88, alignment: .leading)
            LeftAlignedTextField(text: $text, accessibilityLabel: String(localized: title))
                .frame(height: 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ImportLabeledMultilineField: View {
    let title: LocalizedStringResource
    @Binding var text: String
    let lineLimit: ClosedRange<Int>

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption)
                .frame(width: 88, alignment: .leading)
                .padding(.top, 6)
            LeftAlignedTextEditor(text: $text, accessibilityLabel: String(localized: title))
                .frame(minHeight: CGFloat(lineLimit.lowerBound * 20))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ImportLabeledDateField: View {
    let title: LocalizedStringResource
    @Binding var date: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .frame(width: 88, alignment: .leading)
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .foregroundStyle(.black)
                .background(.white, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.gray.opacity(0.35), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LeftAlignedTextField: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.alignment = .left
        field.baseWritingDirection = .leftToRight
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = .white
        field.textColor = .black
        field.focusRingType = .none
        field.setAccessibilityLabel(accessibilityLabel)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.alignment = .left
        field.baseWritingDirection = .leftToRight
        field.setAccessibilityLabel(accessibilityLabel)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

private struct LeftAlignedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let editor = NSTextView()
        editor.delegate = context.coordinator
        editor.string = text
        editor.alignment = .left
        editor.baseWritingDirection = .leftToRight
        editor.backgroundColor = .white
        editor.textColor = .black
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.textContainerInset = NSSize(width: 5, height: 5)
        editor.isRichText = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.setAccessibilityLabel(accessibilityLabel)

        let scrollView = NSScrollView()
        scrollView.documentView = editor
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let editor = scrollView.documentView as? NSTextView else { return }
        if editor.string != text {
            editor.string = text
        }
        editor.alignment = .left
        editor.baseWritingDirection = .leftToRight
        editor.setAccessibilityLabel(accessibilityLabel)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            text = editor.string
        }
    }
}

private struct ImportedTrackPreview: View {
    let coordinates: [TrackCoordinate]

    var body: some View {
        Canvas { context, size in
            guard let minLatitude = coordinates.map(\.latitude).min(),
                  let maxLatitude = coordinates.map(\.latitude).max(),
                  let minLongitude = coordinates.map(\.longitude).min(),
                  let maxLongitude = coordinates.map(\.longitude).max()
            else { return }

            let latitudeRange = max(maxLatitude - minLatitude, 0.000_001)
            let longitudeRange = max(maxLongitude - minLongitude, 0.000_001)
            let inset: CGFloat = 12
            var path = Path()

            for (index, coordinate) in coordinates.enumerated() {
                let x = inset + CGFloat((coordinate.longitude - minLongitude) / longitudeRange)
                    * (size.width - inset * 2)
                let y = inset + CGFloat((maxLatitude - coordinate.latitude) / latitudeRange)
                    * (size.height - inset * 2)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(.blue), lineWidth: 3)
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
