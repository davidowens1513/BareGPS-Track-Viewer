import SQLite3
import Compression
import SwiftUI
import WebKit

enum OpenBareMapLayer: String, CaseIterable, Identifiable {
    case hillshade, landCover, boundaries, minorRoads, roadNames
    case railwaysAndStations, ferryRoutes, cyclingRoutes, hikingRoutes
    case islandNames, waterFeatureNames, irishGrid, townlands

    static let defaultVisible = Set(allCases).subtracting([
        .boundaries, .roadNames, .railwaysAndStations, .ferryRoutes
    ])

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .hillshade: "Hillshade"
        case .landCover: "Land Cover"
        case .boundaries: "Boundaries"
        case .minorRoads: "Minor Roads"
        case .roadNames: "Road Names"
        case .railwaysAndStations: "Railways and Stations"
        case .ferryRoutes: "Ferry Routes"
        case .cyclingRoutes: "Cycling Routes"
        case .hikingRoutes: "Hiking Routes"
        case .islandNames: "Island Names"
        case .waterFeatureNames: "Water-Feature Names"
        case .irishGrid: "Irish Grid"
        case .townlands: "Townlands"
        }
    }

    var layerIdentifiers: [String] {
        switch self {
        case .hillshade: ["terrain-hillshade"]
        case .landCover: ["landcover"]
        case .boundaries: ["administrative-boundaries", "county-boundaries", "local-boundaries"]
        case .minorRoads: ["roads-casing-minor", "roads-minor-path", "roads-minor-track", "roads-minor"]
        case .roadNames: ["road-labels"]
        case .railwaysAndStations: ["railways", "station-labels"]
        case .ferryRoutes: ["ferry-routes"]
        case .cyclingRoutes: ["cycling-routes"]
        case .hikingRoutes: ["hiking-routes"]
        case .islandNames: ["island-labels"]
        case .waterFeatureNames: ["water-labels"]
        case .irishGrid: ["irish-grid-1km", "irish-grid-10km", "irish-grid-labels"]
        case .townlands: ["townland-labels"]
        }
    }
}

struct MapLibreMapView: NSViewRepresentable {
    let usesOpenBareMap: Bool
    let visibleOpenBareMapLayers: Set<OpenBareMapLayer>
    let showsTracks: Bool
    let selectedTrackID: String?
    let visibleTrackIDs: [String]?
    let onTrackClick: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTrackClick: onTrackClick)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator.resourceHandler, forURLScheme: "mapdata")
        configuration.userContentController.add(context.coordinator, name: "trackClick")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.loadHTMLString(Self.html, baseURL: Bundle.main.bundleURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTrackClick = onTrackClick
        context.coordinator.requestedStyle = usesOpenBareMap ? .openBareMap : .openTopo
        context.coordinator.requestedVisibleLayers = visibleOpenBareMapLayers
        context.coordinator.requestedTracksVisible = showsTracks
        context.coordinator.requestedSelectedTrackID = selectedTrackID
        context.coordinator.requestedVisibleTrackIDs = visibleTrackIDs?.sorted()
        context.coordinator.applyRequestedStyleIfReady()
        context.coordinator.applyRequestedLayerVisibilityIfReady()
        context.coordinator.applyRequestedTrackVisibilityIfReady()
        context.coordinator.applyRequestedSelectionIfReady()
        context.coordinator.applyRequestedTrackFilterIfReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "trackClick")
        webView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        enum Style: String {
            case openBareMap = "openBareMap"
            case openTopo = "openTopo"
        }

        let resourceHandler = MapResourceSchemeHandler()
        var onTrackClick: (String) -> Void
        weak var webView: WKWebView?
        var requestedStyle = Style.openBareMap
        var requestedVisibleLayers = OpenBareMapLayer.defaultVisible
        var requestedTracksVisible = true
        var requestedSelectedTrackID: String?
        var requestedVisibleTrackIDs: [String]?
        private var isReady = false
        private var appliedStyle: Style?
        private var appliedSelectedTrackID: String?
        private var appliedVisibleTrackIDs: [String]?

        init(onTrackClick: @escaping (String) -> Void) {
            self.onTrackClick = onTrackClick
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "trackClick", let trackID = message.body as? String else { return }
            appliedSelectedTrackID = trackID
            onTrackClick(trackID)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            applyRequestedStyleIfReady()
            applyRequestedLayerVisibilityIfReady()
            applyRequestedTrackVisibilityIfReady()
            applyRequestedSelectionIfReady()
            applyRequestedTrackFilterIfReady()
        }

        func applyRequestedStyleIfReady() {
            guard isReady, appliedStyle != requestedStyle else { return }
            appliedStyle = requestedStyle
            webView?.evaluateJavaScript("setMapStyle('\(requestedStyle.rawValue)')")
        }

        func applyRequestedLayerVisibilityIfReady() {
            guard isReady else { return }
            let identifiers = requestedVisibleLayers.flatMap(\.layerIdentifiers).sorted()
            guard let data = try? JSONSerialization.data(withJSONObject: identifiers),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            webView?.evaluateJavaScript("setVisibleOpenBareMapLayers(\(json))")
        }

        func applyRequestedTrackVisibilityIfReady() {
            guard isReady else { return }
            webView?.evaluateJavaScript("setTracksVisible(\(requestedTracksVisible))")
        }

        func applyRequestedSelectionIfReady() {
            guard
                isReady,
                requestedSelectedTrackID != appliedSelectedTrackID,
                let data = try? JSONEncoder().encode(requestedSelectedTrackID),
                let json = String(data: data, encoding: .utf8)
            else { return }

            appliedSelectedTrackID = requestedSelectedTrackID
            webView?.evaluateJavaScript("setSelectedTrack(\(json))")
        }

        func applyRequestedTrackFilterIfReady() {
            guard
                isReady,
                requestedVisibleTrackIDs != appliedVisibleTrackIDs,
                let data = try? JSONEncoder().encode(requestedVisibleTrackIDs),
                let json = String(data: data, encoding: .utf8)
            else { return }

            appliedVisibleTrackIDs = requestedVisibleTrackIDs
            webView?.evaluateJavaScript("setVisibleTrackIDs(\(json))")
        }

    }

    private static var html: String {
        guard
            let scriptURL = Bundle.main.url(forResource: "maplibre-gl", withExtension: "js"),
            let styleSheetURL = Bundle.main.url(forResource: "maplibre-gl", withExtension: "css"),
            let script = try? String(contentsOf: scriptURL, encoding: .utf8),
            let styleSheet = try? String(contentsOf: styleSheetURL, encoding: .utf8)
        else {
            return "<html><body>MapLibre resources are unavailable.</body></html>"
        }

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>\(styleSheet)</style>
          <style>
            html, body, #map { width: 100%; height: 100%; margin: 0; overflow: hidden; }
            body { background: #dbe5e5; }
            .maplibregl-ctrl-attrib { font: 11px -apple-system, sans-serif; }
            #map-status {
              display: none; position: absolute; left: 16px; bottom: 36px; z-index: 10;
              max-width: 420px; padding: 8px 12px; border-radius: 8px;
              background: rgba(28, 28, 30, .88); color: white;
              font: 12px -apple-system, sans-serif;
            }
          </style>
        </head>
        <body>
          <div id="map"></div>
          <div id="map-status"></div>
          <script>\(script)</script>
          <script>
            const openTopoStyle = {
              version: 8,
              name: 'OpenTopoMap',
              sources: {
                opentopo: {
                  type: 'raster',
                  tiles: ['https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
                          'https://b.tile.opentopomap.org/{z}/{x}/{y}.png',
                          'https://c.tile.opentopomap.org/{z}/{x}/{y}.png'],
                  tileSize: 256,
                  maxzoom: 17,
                  attribution: 'Map data © OpenStreetMap contributors, SRTM | Map style © OpenTopoMap (CC-BY-SA)'
                },
                walkingTracks: {
                  type: 'geojson',
                  data: 'mapdata://tracks/OnzyTracks.geojson'
                }
              },
              layers: [
                { id: 'opentopo', type: 'raster', source: 'opentopo' },
                {
                  id: 'walking-tracks-casing',
                  type: 'line',
                  source: 'walkingTracks',
                  paint: {
                    'line-color': '#ffffff',
                    'line-width': ['interpolate', ['linear'], ['zoom'], 5, 1.5, 10, 3.5, 14, 6],
                    'line-opacity': 0.8
                  }
                },
                {
                  id: 'walking-tracks',
                  type: 'line',
                  source: 'walkingTracks',
                  paint: {
                    'line-color': '#d9272e',
                    'line-width': ['interpolate', ['linear'], ['zoom'], 5, 0.8, 10, 2, 14, 4],
                    'line-opacity': 0.9
                  }
                },
                {
                  id: 'selected-track',
                  type: 'line',
                  source: 'walkingTracks',
                  filter: ['==', ['get', 'id'], ''],
                  paint: {
                    'line-color': '#007aff',
                    'line-width': ['interpolate', ['linear'], ['zoom'], 5, 2, 10, 5, 14, 8],
                    'line-opacity': 1
                  }
                }
              ]
            };

            const map = new maplibregl.Map({
              container: 'map',
              style: openTopoStyle,
              center: [-8.15412, 53.4],
              zoom: 7,
              attributionControl: true
            });

            map.addControl(new maplibregl.NavigationControl({ showCompass: true }), 'top-right');
            map.addControl(new maplibregl.ScaleControl({ maxWidth: 120, unit: 'metric' }), 'bottom-left');

            let requestedStyle = 'openTopo';
            const status = document.getElementById('map-status');
            const openBareMapLayerIDs = [
              'terrain-hillshade', 'landcover',
              'administrative-boundaries', 'county-boundaries', 'local-boundaries',
              'roads-casing-minor', 'roads-minor-path', 'roads-minor-track', 'roads-minor',
              'road-labels', 'railways', 'station-labels', 'ferry-routes',
              'cycling-routes', 'hiking-routes', 'island-labels', 'water-labels',
              'irish-grid-1km', 'irish-grid-10km', 'irish-grid-labels', 'townland-labels'
            ];
            const visibleOpenBareMapLayerIDs = new Set();
            let tracksVisible = true;
            let selectedTrackID = null;
            let visibleTrackIDs = null;
            const trackDataPromise = fetch('mapdata://tracks/OnzyTracks.geojson', { cache: 'force-cache' })
              .then(response => {
                if (!response.ok) throw new Error('Track data returned ' + response.status);
                return response.json();
              });

            function showStatus(message) {
              status.textContent = message;
              status.style.display = 'block';
            }

            function trackFeaturesNear(point, tolerance) {
              const clickableLayers = ['selected-track', 'walking-tracks', 'walking-tracks-casing']
                .filter(layerID => map.getLayer(layerID));
              if (clickableLayers.length === 0) return [];

              const bounds = [
                [point.x - tolerance, point.y - tolerance],
                [point.x + tolerance, point.y + tolerance]
              ];
              return map.queryRenderedFeatures(bounds, { layers: clickableLayers });
            }

            map.on('click', event => {
              const features = trackFeaturesNear(event.point, 12);
              const trackID = features[0] && features[0].properties && features[0].properties.id;
              if (trackID === undefined || trackID === null) return;

              selectedTrackID = String(trackID);
              applySelectedTrack(false);
              window.webkit.messageHandlers.trackClick.postMessage(selectedTrackID);
            });

            map.on('mousemove', event => {
              map.getCanvas().style.cursor = trackFeaturesNear(event.point, 6).length > 0 ? 'pointer' : '';
            });

            map.on('load', () => map.resize());
            map.on('style.load', () => {
              applyOpenBareMapLayerVisibility();
              applyTrackVisibility();
              applyTrackFilter();
              applySelectedTrack(true);
            });
            map.on('error', event => {
              const message = event && event.error ? event.error.message : 'Unknown map error';
              console.error('MapLibre:', message);
              if (requestedStyle === 'openTopo') {
                showStatus('Map loading error: ' + message);
              }
            });

            async function setMapStyle(name) {
              if (name === 'openBareMap') {
                requestedStyle = name;
                try {
                  const response = await fetch('mapdata://package/style.json?v=1.1.0', { cache: 'no-store' });
                  if (!response.ok) throw new Error('OpenBareMap style returned ' + response.status);
                  const style = await response.json();
                  map.setStyle(style);
                  applyOpenBareMapLayerVisibility();
                  applyTrackVisibility();
                  map.jumpTo({ center: [-8.15412, 53.4], zoom: Math.max(map.getZoom(), 7) });
                  status.style.display = 'none';
                } catch (error) {
                  requestedStyle = 'openTopo';
                  map.setStyle(openTopoStyle);
                  showStatus('OpenBareMap could not be loaded. Showing OpenTopoMap.');
                  console.error(error);
                }
              } else {
                requestedStyle = name;
                map.setStyle(openTopoStyle);
                applyTrackVisibility();
                status.style.display = 'none';
              }
            }

            function setVisibleOpenBareMapLayers(layerIDs) {
              visibleOpenBareMapLayerIDs.clear();
              for (const layerID of layerIDs) visibleOpenBareMapLayerIDs.add(layerID);
              applyOpenBareMapLayerVisibility();
            }

            function applyOpenBareMapLayerVisibility() {
              for (const layerID of openBareMapLayerIDs) {
                if (map.getLayer(layerID)) {
                  const visibility = visibleOpenBareMapLayerIDs.has(layerID) ? 'visible' : 'none';
                  map.setLayoutProperty(layerID, 'visibility', visibility);
                }
              }
            }

            function setTracksVisible(isVisible) {
              tracksVisible = isVisible;
              applyTrackVisibility();
            }

            function applyTrackVisibility() {
              const visibility = tracksVisible ? 'visible' : 'none';
              for (const layerID of ['walking-tracks-casing', 'walking-tracks']) {
                if (map.getLayer(layerID)) map.setLayoutProperty(layerID, 'visibility', visibility);
              }
            }

            function setVisibleTrackIDs(trackIDs) {
              visibleTrackIDs = trackIDs;
              applyTrackFilter();
            }

            function applyTrackFilter() {
              const filter = visibleTrackIDs === null
                ? null
                : ['in', ['get', 'id'], ['literal', visibleTrackIDs]];

              for (const layerID of ['walking-tracks-casing', 'walking-tracks']) {
                if (map.getLayer(layerID)) map.setFilter(layerID, filter);
              }
            }

            function setSelectedTrack(trackID) {
              selectedTrackID = trackID;
              applySelectedTrack(true);
            }

            function applySelectedTrack(shouldZoom) {
              if (!selectedTrackID || !map.getLayer('selected-track')) return;
              map.setFilter('selected-track', ['==', ['get', 'id'], selectedTrackID]);
              if (shouldZoom) focusSelectedTrack();
            }

            async function focusSelectedTrack() {
              const trackID = selectedTrackID;

              try {
                const trackData = await trackDataPromise;
                const feature = trackData.features.find(candidate =>
                  String(candidate.properties && candidate.properties.id) === String(trackID)
                );

                if (!feature || !feature.geometry || trackID !== selectedTrackID) return;

                const bounds = new maplibregl.LngLatBounds();
                const extendCoordinates = coordinates => {
                  if (!Array.isArray(coordinates) || coordinates.length === 0) return;

                  if (typeof coordinates[0] === 'number') {
                    bounds.extend(coordinates);
                  } else {
                    coordinates.forEach(extendCoordinates);
                  }
                };

                extendCoordinates(feature.geometry.coordinates);
                if (!bounds.isEmpty() && trackID === selectedTrackID) {
                  map.fitBounds(bounds, { padding: 60, maxZoom: 15, duration: 700 });
                }
              } catch (error) {
                console.error('Could not focus selected track:', error);
              }
            }
          </script>
        </body>
        </html>
        """
    }
}

final class MapResourceSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private let taskLock = NSLock()
    private var stoppedTaskIdentifiers: Set<ObjectIdentifier> = []

    private var packageURL: URL {
        MapPackageLocation.packageURL
            ?? URL(fileURLWithPath: "/OpenBareMap-package-not-selected", isDirectory: true)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskIdentifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        clearStoppedState(for: taskIdentifier)

        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, message: "Missing resource URL")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { try response(for: url) }

            DispatchQueue.main.async { [weak self] in
                guard let self, !consumeStoppedState(for: taskIdentifier) else { return }

                switch result {
                case .success(let response):
                    urlSchemeTask.didReceive(response.urlResponse)
                    urlSchemeTask.didReceive(response.data)
                    urlSchemeTask.didFinish()
                case .failure(let error):
                    urlSchemeTask.didFailWithError(error)
                }

                clearStoppedState(for: taskIdentifier)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskIdentifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        taskLock.lock()
        stoppedTaskIdentifiers.insert(taskIdentifier)
        taskLock.unlock()
    }

    private func consumeStoppedState(for taskIdentifier: ObjectIdentifier) -> Bool {
        taskLock.lock()
        defer { taskLock.unlock() }
        return stoppedTaskIdentifiers.remove(taskIdentifier) != nil
    }

    private func clearStoppedState(for taskIdentifier: ObjectIdentifier) {
        taskLock.lock()
        stoppedTaskIdentifiers.remove(taskIdentifier)
        taskLock.unlock()
    }

    private func response(for url: URL) throws -> ResourceResponse {
        let components = url.pathComponents.filter { $0 != "/" }

        if url.host == "package", components == ["style.json"] {
            return try styleResponse(for: url)
        }

        if url.host == "tilejson", let source = components.first {
            return try tileJSONResponse(source: source, url: url)
        }

        if url.host == "tiles", components.count == 4 {
            return try tileResponse(components: components, url: url)
        }

        if url.host == "assets" {
            return try assetResponse(pathComponents: components, url: url)
        }

        if url.host == "tracks", let resource = components.first {
            return try trackResponse(resource: resource, url: url)
        }

        throw MapResourceError.notFound(url.absoluteString)
    }

    private func styleResponse(for url: URL) throws -> ResourceResponse {
        let styleURL = packageURL.appendingPathComponent("baregps-style.json")
        let data = try Data(contentsOf: styleURL)
        guard var style = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var sources = style["sources"] as? [String: Any]
        else {
            throw MapResourceError.invalidStyle
        }

        let sourceNames = ["ireland", "contours", "environment", "hillshade", "hiking", "irish-grid", "islands"]
        for sourceName in sourceNames {
            guard var source = sources[sourceName] as? [String: Any] else { continue }
            source["url"] = "mapdata://tilejson/\(sourceName)"
            sources[sourceName] = source
        }

        if var townlands = sources["townlands"] as? [String: Any] {
            townlands["data"] = "mapdata://assets/style/townlands.geojson"
            sources["townlands"] = townlands
        }

        sources["opentopo-world"] = [
            "type": "raster",
            "tiles": [
                "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
                "https://b.tile.opentopomap.org/{z}/{x}/{y}.png",
                "https://c.tile.opentopomap.org/{z}/{x}/{y}.png"
            ],
            "tileSize": 256,
            "maxzoom": 17,
            "attribution": "Map data © OpenStreetMap contributors, SRTM | Map style © OpenTopoMap (CC-BY-SA)"
        ]
        sources["walkingTracks"] = [
            "type": "geojson",
            "data": "mapdata://tracks/OnzyTracks.geojson"
        ]
        style["sources"] = sources

        guard var layers = style["layers"] as? [[String: Any]] else {
            throw MapResourceError.invalidStyle
        }
        layers = layers.flatMap { layer -> [[String: Any]] in
            guard layer["id"] as? String == "roads-minor",
                  let originalFilter = layer["filter"],
                  let originalPaint = layer["paint"] as? [String: Any]
            else {
                return [layer]
            }

            func roadLayer(
                identifier: String,
                classFilter: [Any],
                dashArray: [Double]
            ) -> [String: Any] {
                var output = layer
                output["id"] = identifier
                output["filter"] = ["all", originalFilter, classFilter]
                var paint = originalPaint
                paint["line-dasharray"] = dashArray
                output["paint"] = paint
                return output
            }

            return [
                roadLayer(
                    identifier: "roads-minor-path",
                    classFilter: ["==", "class", "path"],
                    dashArray: [1.2, 1.2]
                ),
                roadLayer(
                    identifier: "roads-minor-track",
                    classFilter: ["==", "class", "track"],
                    dashArray: [2, 1.2]
                ),
                roadLayer(
                    identifier: "roads-minor",
                    classFilter: ["!in", "class", "path", "track"],
                    dashArray: [1, 0]
                )
            ]
        }
        layers.removeAll { $0["type"] as? String == "background" }
        layers.insert([
            "id": "opentopo-world",
            "type": "raster",
            "source": "opentopo-world"
        ], at: 0)
        layers.append(contentsOf: [
            [
                "id": "walking-tracks-casing",
                "type": "line",
                "source": "walkingTracks",
                "paint": [
                    "line-color": "#ffffff",
                    "line-width": ["interpolate", ["linear"], ["zoom"], 5, 1.5, 10, 3.5, 14, 6],
                    "line-opacity": 0.8
                ]
            ],
            [
                "id": "walking-tracks",
                "type": "line",
                "source": "walkingTracks",
                "paint": [
                    "line-color": "#d9272e",
                    "line-width": ["interpolate", ["linear"], ["zoom"], 5, 0.8, 10, 2, 14, 4],
                    "line-opacity": 0.9
                ]
            ],
            [
                "id": "selected-track",
                "type": "line",
                "source": "walkingTracks",
                "filter": ["==", ["get", "id"], ""],
                "paint": [
                    "line-color": "#007aff",
                    "line-width": ["interpolate", ["linear"], ["zoom"], 5, 2, 10, 5, 14, 8],
                    "line-opacity": 1
                ]
            ]
        ])
        let hiddenOpenBareMapLayers = Set([
            "administrative-boundaries",
            "county-boundaries",
            "local-boundaries",
            "road-labels",
            "railways",
            "station-labels",
            "ferry-routes"
        ])
        for index in layers.indices {
            guard let identifier = layers[index]["id"] as? String,
                  hiddenOpenBareMapLayers.contains(identifier)
            else { continue }

            var layout = layers[index]["layout"] as? [String: Any] ?? [:]
            layout["visibility"] = "none"
            layers[index]["layout"] = layout
        }
        style["layers"] = layers
        style["sprite"] = "mapdata://assets/sprites/baregps-bog27"
        style["glyphs"] = "mapdata://assets/fonts/{fontstack}/{range}.pbf"
        let output = try JSONSerialization.data(withJSONObject: style)
        return ResourceResponse(data: output, mimeType: "application/json", url: url)
    }

    private func tileJSONResponse(source: String, url: URL) throws -> ResourceResponse {
        let fileName = source == "irish-grid" ? "grid" : source
        let fileURL = packageURL.appendingPathComponent("\(fileName).mbtiles")
        let database = try MBTilesDatabase(url: fileURL)
        let metadata = try database.metadata()
        let format = metadata["format"] ?? (source == "hillshade" ? "png" : "pbf")
        let tileJSON: [String: Any] = [
            "tilejson": "3.0.0",
            "name": metadata["name"] ?? source,
            "scheme": "xyz",
            "tiles": ["mapdata://tiles/\(source)/{z}/{x}/{y}.\(format)"],
            "minzoom": Int(metadata["minzoom"] ?? "0") ?? 0,
            "maxzoom": Int(metadata["maxzoom"] ?? "14") ?? 14,
            "attribution": "© OpenStreetMap contributors"
        ]
        let data = try JSONSerialization.data(withJSONObject: tileJSON)
        return ResourceResponse(data: data, mimeType: "application/json", url: url)
    }

    private func tileResponse(components: [String], url: URL) throws -> ResourceResponse {
        let source = components[0]
        guard let zoom = Int(components[1]),
              let column = Int(components[2]),
              let row = Int(components[3].split(separator: ".").first ?? "")
        else {
            throw MapResourceError.invalidTilePath
        }

        let fileName = source == "irish-grid" ? "grid" : source
        let database = try MBTilesDatabase(url: packageURL.appendingPathComponent("\(fileName).mbtiles"))
        let storedData = try database.tile(zoom: zoom, column: column, xyzRow: row) ?? Data()
        let data = storedData.starts(with: [0x1F, 0x8B])
            ? try storedData.gunzipped()
            : storedData
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        return ResourceResponse(
            data: data,
            mimeType: isPNG ? "image/png" : "application/x-protobuf",
            url: url
        )
    }

    private func assetResponse(pathComponents: [String], url: URL) throws -> ResourceResponse {
        let relativePath = pathComponents.joined(separator: "/")
        let fileURL = packageURL.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: fileURL)
        let mimeType: String
        switch fileURL.pathExtension {
        case "json", "geojson": mimeType = "application/json"
        case "png": mimeType = "image/png"
        case "pbf": mimeType = "application/x-protobuf"
        default: mimeType = "application/octet-stream"
        }
        return ResourceResponse(data: data, mimeType: mimeType, url: url)
    }

    private func trackResponse(resource: String, url: URL) throws -> ResourceResponse {
        try? TrackLibrary.prepare()
        let bundledURL = Bundle.main.url(
            forResource: resource.replacingOccurrences(of: ".geojson", with: ""),
            withExtension: "geojson",
            subdirectory: "TrackData"
        ) ?? Bundle.main.url(
            forResource: resource.replacingOccurrences(of: ".geojson", with: ""),
            withExtension: "geojson"
        )
        let workingURL = TrackLibrary.geoJSONURL
        let resourceURL = FileManager.default.fileExists(atPath: workingURL.path)
            ? workingURL
            : bundledURL
        guard let resourceURL else {
            throw MapResourceError.notFound(resource)
        }
        return ResourceResponse(
            data: try Data(contentsOf: resourceURL, options: .mappedIfSafe),
            mimeType: "application/geo+json",
            url: url
        )
    }

    private func fail(_ task: WKURLSchemeTask, message: String) {
        task.didFailWithError(MapResourceError.notFound(message))
    }
}

enum MapPackageLocation {
    static let bookmarkKey = "openBareMapPackageBookmark"

    private static let configuredRoot = URL(
        fileURLWithPath: "/Users/davidowens/desktop/BareGPSIreland2.0/MapHills/RegionDefinition/Ireland/Resources/OpenBareMap.bundle",
        isDirectory: true
    )

    private static let lock = NSLock()
    private static let requiredPackageFormat = "baregps-ireland-map-package-v1"
    private static let requiredApplicationVersion = "2.0"
    private static let requiredMapVersion = "1.1.0"
    nonisolated(unsafe) private static var retainedAccessURL: URL?
    nonisolated(unsafe) private static var resolvedPackageURL: URL?

    static var packageURL: URL? {
        lock.lock()
        defer { lock.unlock() }

        if let resolvedPackageURL {
            return resolvedPackageURL
        }

        if let configuredPackage = findPackage(in: configuredRoot) {
            resolvedPackageURL = configuredPackage
            return configuredPackage
        }

        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey), !bookmark.isEmpty else {
            return nil
        }

        var isStale = false
        guard let selectedURL = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), selectedURL.startAccessingSecurityScopedResource() else {
            return nil
        }

        guard let packageURL = findPackage(in: selectedURL) else {
            selectedURL.stopAccessingSecurityScopedResource()
            return nil
        }

        retainedAccessURL = selectedURL
        resolvedPackageURL = packageURL
        return packageURL
    }

    static func makeBookmark(for selectedURL: URL) throws -> Data {
        let isAccessing = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }

        let bookmark = try selectedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        lock.lock()
        if let retainedAccessURL {
            retainedAccessURL.stopAccessingSecurityScopedResource()
        }
        retainedAccessURL = nil
        resolvedPackageURL = nil
        lock.unlock()
        return bookmark
    }

    private static func findPackage(in selectedURL: URL) -> URL? {
        let styleName = "baregps-style.json"
        if isRequiredPackage(selectedURL, styleName: styleName) {
            return selectedURL
        }

        let children = try? FileManager.default.contentsOfDirectory(
            at: selectedURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return children?.first { isRequiredPackage($0, styleName: styleName) }
    }

    private static func isRequiredPackage(_ packageURL: URL, styleName: String) -> Bool {
        guard FileManager.default.fileExists(
            atPath: packageURL.appendingPathComponent(styleName).path
        ),
        let manifestData = try? Data(
            contentsOf: packageURL.appendingPathComponent("manifest.json")
        ),
        let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
        manifest["packageFormat"] as? String == requiredPackageFormat,
        let targetApplication = manifest["targetApplication"] as? [String: Any],
        targetApplication["version"] as? String == requiredApplicationVersion,
        let map = manifest["map"] as? [String: Any],
        map["version"] as? String == requiredMapVersion,
        map["style"] as? String == styleName
        else {
            return false
        }
        return true
    }
}

private struct ResourceResponse {
    let data: Data
    let urlResponse: URLResponse

    init(data: Data, mimeType: String, url: URL, contentEncoding: String? = nil) {
        self.data = data
        var headers = [
            "Content-Type": mimeType,
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store, no-cache, must-revalidate",
            "Pragma": "no-cache"
        ]
        if let contentEncoding {
            headers["Content-Encoding"] = contentEncoding
        }
        urlResponse = HTTPURLResponse(
            url: url,
            statusCode: data.isEmpty ? 204 : 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }
}

private final class MBTilesDatabase {
    private var database: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw MapResourceError.database(url.lastPathComponent)
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func metadata() throws -> [String: String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT name, value FROM metadata", -1, &statement, nil) == SQLITE_OK else {
            throw MapResourceError.database("metadata")
        }
        defer { sqlite3_finalize(statement) }

        var values: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 0),
                  let value = sqlite3_column_text(statement, 1)
            else { continue }
            values[String(cString: name)] = String(cString: value)
        }
        return values
    }

    func tile(zoom: Int, column: Int, xyzRow: Int) throws -> Data? {
        let tmsRow = (1 << zoom) - 1 - xyzRow
        var statement: OpaquePointer?
        let sql = "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MapResourceError.database("tiles")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(zoom))
        sqlite3_bind_int(statement, 2, Int32(column))
        sqlite3_bind_int(statement, 3, Int32(tmsRow))
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0)
        else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }
}

private enum MapResourceError: LocalizedError {
    case database(String)
    case decompression
    case invalidStyle
    case invalidTilePath
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .database(let name): "Unable to read MBTiles database: \(name)"
        case .decompression: "Unable to decompress a vector map tile."
        case .invalidStyle: "The OpenBareMap style is invalid."
        case .invalidTilePath: "The requested tile path is invalid."
        case .notFound(let path): "Map resource not found: \(path)"
        }
    }
}

private extension Data {
    func gunzipped() throws -> Data {
        guard count >= 18,
              starts(with: [0x1F, 0x8B]),
              self[index(startIndex, offsetBy: 3)] == 0
        else {
            throw MapResourceError.decompression
        }

        let decodedSize = suffix(4).enumerated().reduce(0) { result, element in
            result | (Int(element.element) << (element.offset * 8))
        }
        guard decodedSize > 0 else { return Data() }

        let compressedPayload = dropFirst(10).dropLast(8)
        var output = [UInt8](repeating: 0, count: decodedSize)
        let bytesWritten = output.withUnsafeMutableBytes { destination in
            compressedPayload.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    decodedSize,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    compressedPayload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard bytesWritten == decodedSize else {
            throw MapResourceError.decompression
        }
        return Data(output)
    }
}
