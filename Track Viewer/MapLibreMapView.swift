import SQLite3
import SwiftUI
import WebKit

struct MapLibreMapView: NSViewRepresentable {
    let usesOpenBareMap: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator.resourceHandler, forURLScheme: "mapdata")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.loadHTMLString(Self.html, baseURL: Bundle.main.bundleURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.requestedStyle = usesOpenBareMap ? .openBareMap : .openTopo
        context.coordinator.applyRequestedStyleIfReady()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        enum Style: String {
            case openBareMap = "openBareMap"
            case openTopo = "openTopo"
        }

        let resourceHandler = MapResourceSchemeHandler()
        weak var webView: WKWebView?
        var requestedStyle = Style.openBareMap
        private var isReady = false
        private var appliedStyle: Style?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            applyRequestedStyleIfReady()
        }

        func applyRequestedStyleIfReady() {
            guard isReady, appliedStyle != requestedStyle else { return }
            appliedStyle = requestedStyle
            webView?.evaluateJavaScript("setMapStyle('\\(requestedStyle.rawValue)')")
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
                }
              },
              layers: [{ id: 'opentopo', type: 'raster', source: 'opentopo' }]
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

            function showStatus(message) {
              status.textContent = message;
              status.style.display = 'block';
            }

            map.on('load', () => map.resize());
            map.on('error', event => {
              const message = event && event.error ? event.error.message : 'Unknown map error';
              console.error('MapLibre:', message);
              if (requestedStyle === 'openBareMap') {
                requestedStyle = 'openTopo';
                map.setStyle(openTopoStyle);
                showStatus('OpenBareMap could not be loaded. Showing OpenTopoMap.');
              } else {
                showStatus('Map loading error: ' + message);
              }
            });

            async function setMapStyle(name) {
              if (name === 'openBareMap') {
                requestedStyle = name;
                try {
                  const response = await fetch('mapdata://package/style.json');
                  if (!response.ok) throw new Error('OpenBareMap style returned ' + response.status);
                  const style = await response.json();
                  map.setStyle(style);
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
                status.style.display = 'none';
              }
            }
          </script>
        </body>
        </html>
        """
    }
}

final class MapResourceSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private var packageURL: URL {
        MapPackageLocation.packageURL
            ?? URL(fileURLWithPath: "/OpenBareMap-package-not-selected", isDirectory: true)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, message: "Missing resource URL")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let response = try response(for: url)
                urlSchemeTask.didReceive(response.urlResponse)
                urlSchemeTask.didReceive(response.data)
                urlSchemeTask.didFinish()
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

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

        style["sources"] = sources
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
        let data = try database.tile(zoom: zoom, column: column, xyzRow: row) ?? Data()
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        return ResourceResponse(
            data: data,
            mimeType: isPNG ? "image/png" : "application/x-protobuf",
            url: url,
            contentEncoding: data.starts(with: [0x1F, 0x8B]) ? "gzip" : nil
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
        if FileManager.default.fileExists(atPath: selectedURL.appendingPathComponent(styleName).path) {
            return selectedURL
        }

        let children = try? FileManager.default.contentsOfDirectory(
            at: selectedURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return children?.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(styleName).path)
        }
    }
}

private struct ResourceResponse {
    let data: Data
    let urlResponse: URLResponse

    init(data: Data, mimeType: String, url: URL, contentEncoding: String? = nil) {
        self.data = data
        var headers = ["Content-Type": mimeType, "Access-Control-Allow-Origin": "*"]
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
    case invalidStyle
    case invalidTilePath
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .database(let name): "Unable to read MBTiles database: \(name)"
        case .invalidStyle: "The OpenBareMap style is invalid."
        case .invalidTilePath: "The requested tile path is invalid."
        case .notFound(let path): "Map resource not found: \(path)"
        }
    }
}
