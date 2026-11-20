import * as maplibregl from "maplibre-gl";
import { strFromU8, strToU8, unzip, zipSync } from "fflate";
import type { Feature, FeatureCollection, Geometry } from "geojson";
import { formatKnownLocation, inferOfflineLocation } from "./geography";
import "maplibre-gl/dist/maplibre-gl.css";
import "./style.css";

type Coordinate = [longitude: number, latitude: number, elevation?: number];

interface Track {
    id: string;
    name: string;
    fileName: string;
    location: string;
    coordinates: Coordinate[];
    segments: Coordinate[][];
    distanceMetres: number;
    ascentMetres: number;
    date?: Date;
    color: string;
    visible: boolean;
}

interface ImportResult {
    tracks: Track[];
    failures: string[];
}

interface ScreenTrackPath {
    track: Track;
    points: maplibregl.Point[];
}

const polylineColors = [
    { name: "Red", value: "#d9271c" },
    { name: "Orange", value: "#e56717" },
    { name: "Amber", value: "#e99b00" },
    { name: "Yellow", value: "#d5b800" },
    { name: "Lime", value: "#70a800" },
    { name: "Green", value: "#14833b" },
    { name: "Teal", value: "#00877d" },
    { name: "Cyan", value: "#008cab" },
    { name: "Blue", value: "#1769c2" },
    { name: "Indigo", value: "#4b50b9" },
    { name: "Purple", value: "#873ca8" },
    { name: "Magenta", value: "#bd287d" }
];
const savedPolylineColor = localStorage.getItem("baregps-polyline-color");
let polylineColor = polylineColors.some(option => option.value === savedPolylineColor)
    ? savedPolylineColor!
    : polylineColors[0].value;
const tracks: Track[] = [];
let map: maplibregl.Map;
let searchQuery = "";
let sortMode = "date";
let sortAscending = false;
let overlayFrame: number | undefined;
let screenTrackPaths: ScreenTrackPath[] = [];
const selectedTrackIDs = new Set<string>();
let showOnlySelected = false;
let pendingExport: string | undefined;
let knownTrackLocations: Record<string, string> = {};
const knownTrackLocationsPromise = fetch("/tools/track-viewer/known-track-locations.json")
    .then(response => response.ok ? response.json() as Promise<Record<string, string>> : {})
    .then(locations => { knownTrackLocations = locations; })
    .catch(() => undefined);

document.querySelector<HTMLDivElement>("#app")!.innerHTML = `
  <main class="app-shell">
    <aside class="sidebar">
      <header class="brand-block">
        <img src="/tools/track-viewer/track-viewer.svg" width="42" height="42" alt="" aria-hidden="true" />
        <div><p class="eyebrow">BareGPS Hiking Tools</p><h1>Track Viewer</h1></div>
      </header>

      <section class="import-panel" id="drop-zone">
        <span class="drop-label">Drop GPX or ZIP here</span>
        <div class="import-actions">
          <label class="primary-button" for="file-input">Files / ZIP</label>
          <label class="secondary-button" for="folder-input">Folder</label>
        </div>
        <input id="file-input" type="file" accept=".gpx,.zip,application/gpx+xml,application/zip" multiple />
        <input id="folder-input" type="file" accept=".gpx,application/gpx+xml" webkitdirectory multiple />
      </section>

      <div class="status-row" aria-live="polite">
        <span id="track-count">No tracks loaded</span>
        <div class="status-actions">
          <details class="colour-menu">
            <summary>Colours</summary>
            <div class="colour-popover">
              <strong>Polyline colour</strong>
              <div class="colour-options">
                ${polylineColors.map(option => `
                  <button type="button" class="colour-option" data-colour="${option.value}" title="${option.name}" aria-label="${option.name}">
                    <span style="background:${option.value}"></span>
                  </button>`).join("")}
              </div>
            </div>
          </details>
          <details class="export-menu" id="export-menu">
            <summary>Export</summary>
            <div class="export-options">
              <button type="button" data-export="zip-selected">ZIP · Selected only</button>
              <button type="button" data-export="zip-all">ZIP · All tracks</button>
              <button type="button" data-export="geojson-selected">GeoJSON · Selected only</button>
              <button type="button" data-export="geojson-all">GeoJSON · All tracks</button>
              <div class="export-confirmation">
                <span id="export-summary">Choose an export option.</span>
                <button id="export-confirm-button" type="button" disabled>Confirm</button>
              </div>
            </div>
          </details>
        </div>
      </div>
      <section class="library-controls" aria-label="Track library controls">
        <label class="selected-only-control">
          <input id="selected-only-input" type="checkbox" />
          <span>Show only selected</span>
        </label>
        <label class="search-control">
          <span aria-hidden="true">⌕</span>
          <input id="search-input" type="search" placeholder="Search all fields" />
        </label>
      </section>
      <p class="error-message" id="error-message" role="alert" hidden></p>
      <section class="results-grid" aria-label="Imported tracks">
        <div class="grid-header">
          <span class="selection-heading" aria-label="Selected">✓</span>
          <button type="button" data-sort="date">Date</button>
          <button type="button" data-sort="name">Number / Name</button>
          <button type="button" data-sort="location">Location</button>
          <button type="button" data-sort="distance">Length</button>
          <button type="button" data-sort="ascent">Ascent</button>
        </div>
        <div class="track-list" id="track-list"></div>
      </section>
    </aside>

    <div class="panel-resizer" id="panel-resizer" role="separator" tabindex="0"
         aria-label="Resize track library" aria-orientation="vertical"></div>

    <section class="map-panel" aria-label="Track map">
      <div id="map"></div>
      <canvas class="track-overlay" id="track-overlay" aria-hidden="true"></canvas>
      <div class="track-hover-card" id="track-hover-card" hidden></div>
      <div class="map-note">OpenTopoMap · Track files are processed locally</div>
    </section>
  </main>
`;

const fileInput = document.querySelector<HTMLInputElement>("#file-input")!;
const appShell = document.querySelector<HTMLElement>(".app-shell")!;
const panelResizer = document.querySelector<HTMLElement>("#panel-resizer")!;
const folderInput = document.querySelector<HTMLInputElement>("#folder-input")!;
const dropZone = document.querySelector<HTMLElement>("#drop-zone")!;
const errorMessage = document.querySelector<HTMLElement>("#error-message")!;
const exportMenu = document.querySelector<HTMLDetailsElement>("#export-menu")!;
const exportButtons = Array.from(document.querySelectorAll<HTMLButtonElement>("[data-export]"));
const exportSummary = document.querySelector<HTMLElement>("#export-summary")!;
const exportConfirmButton = document.querySelector<HTMLButtonElement>("#export-confirm-button")!;
const searchInput = document.querySelector<HTMLInputElement>("#search-input")!;
const selectedOnlyInput = document.querySelector<HTMLInputElement>("#selected-only-input")!;
const trackOverlay = document.querySelector<HTMLCanvasElement>("#track-overlay")!;
const trackHoverCard = document.querySelector<HTMLElement>("#track-hover-card")!;
const savedSidebarWidth = Number(localStorage.getItem("baregps-sidebar-width"));
if (Number.isFinite(savedSidebarWidth) && savedSidebarWidth >= 330) {
    setSidebarWidth(savedSidebarWidth);
}

panelResizer.addEventListener("pointerdown", event => {
    panelResizer.setPointerCapture(event.pointerId);
    panelResizer.classList.add("is-resizing");
});
panelResizer.addEventListener("pointermove", event => {
    if (!panelResizer.hasPointerCapture(event.pointerId)) return;
    setSidebarWidth(event.clientX);
});
panelResizer.addEventListener("pointerup", event => {
    if (panelResizer.hasPointerCapture(event.pointerId)) panelResizer.releasePointerCapture(event.pointerId);
    panelResizer.classList.remove("is-resizing");
    localStorage.setItem("baregps-sidebar-width", String(Math.round(panelResizer.getBoundingClientRect().left)));
});
panelResizer.addEventListener("dblclick", () => {
    localStorage.removeItem("baregps-sidebar-width");
    appShell.style.removeProperty("--sidebar-width");
    map.resize();
    scheduleOverlayDraw();
});
panelResizer.addEventListener("keydown", event => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const currentWidth = panelResizer.getBoundingClientRect().left;
    const width = event.key === "Home" ? 330
        : event.key === "End" ? window.innerWidth * 0.6
            : currentWidth + (event.key === "ArrowLeft" ? -24 : 24);
    setSidebarWidth(width);
    localStorage.setItem("baregps-sidebar-width", String(Math.round(width)));
});
document.querySelectorAll<HTMLButtonElement>("[data-colour]").forEach(button => {
    button.classList.toggle("is-selected", button.dataset.colour === polylineColor);
    button.addEventListener("click", () => {
        polylineColor = button.dataset.colour ?? polylineColors[0].value;
        localStorage.setItem("baregps-polyline-color", polylineColor);
        tracks.forEach(track => { track.color = polylineColor; });
        document.querySelectorAll<HTMLButtonElement>("[data-colour]").forEach(option => {
            option.classList.toggle("is-selected", option === button);
        });
        updateMap(false);
        void saveLibrary();
        button.closest("details")?.removeAttribute("open");
    });
});

map = new maplibregl.Map({
    container: "map",
    center: [-7.8, 53.4],
    zoom: 5.5,
    style: {
        version: 8,
        sources: {
            opentopo: {
                type: "raster",
                tiles: [
                    "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
                    "https://b.tile.opentopomap.org/{z}/{x}/{y}.png",
                    "https://c.tile.opentopomap.org/{z}/{x}/{y}.png"
                ],
                tileSize: 256,
                maxzoom: 17,
                attribution: "Map data © OpenStreetMap contributors, SRTM | Map style © OpenTopoMap"
            }
        },
        layers: [{ id: "opentopo", type: "raster", source: "opentopo" }]
    }
});
map.addControl(new maplibregl.NavigationControl(), "top-right");
map.on("load", () => updateMap(tracks.length > 0));
map.on("render", drawTrackOverlay);
map.on("resize", scheduleOverlayDraw);
map.on("mousemove", event => showTrackHover(event.point));
map.on("mouseout", hideTrackHover);
map.on("click", event => selectTrackAt(event.point));

function setSidebarWidth(requestedWidth: number): void {
    const maximumWidth = Math.max(330, window.innerWidth - 320);
    const width = Math.max(330, Math.min(maximumWidth, requestedWidth));
    appShell.style.setProperty("--sidebar-width", `${width}px`);
    panelResizer.setAttribute("aria-valuenow", String(Math.round(width)));
    if (map) map.resize();
    scheduleOverlayDraw();
}

fileInput.addEventListener("change", () => importFiles(fileInput.files));
folderInput.addEventListener("change", () => importFiles(folderInput.files));

for (const eventName of ["dragenter", "dragover"]) {
    dropZone.addEventListener(eventName, event => {
        event.preventDefault();
        dropZone.classList.add("is-dragging");
    });
}

for (const eventName of ["dragleave", "drop"]) {
    dropZone.addEventListener(eventName, event => {
        event.preventDefault();
        dropZone.classList.remove("is-dragging");
    });
}

dropZone.addEventListener("drop", event => importFiles(event.dataTransfer?.files ?? null));
exportButtons.forEach(button => {
    button.addEventListener("click", () => {
        pendingExport = button.dataset.export;
        exportButtons.forEach(option => option.classList.toggle("is-pending", option === button));
        updateExportConfirmation();
    });
});
exportConfirmButton.addEventListener("click", () => {
    if (!pendingExport) return;
    const selectedOnly = pendingExport.endsWith("selected");
    if (pendingExport.startsWith("zip")) exportZIP(selectedOnly);
    else exportGeoJSON(selectedOnly);
    exportMenu.open = false;
    pendingExport = undefined;
    exportButtons.forEach(option => option.classList.remove("is-pending"));
    updateExportConfirmation();
});
searchInput.addEventListener("input", () => {
    searchQuery = searchInput.value.trim();
    renderTracks();
    updateMap(false);
});
selectedOnlyInput.addEventListener("change", () => {
    showOnlySelected = selectedOnlyInput.checked;
    renderTracks();
    scheduleOverlayDraw();
});
document.querySelectorAll<HTMLButtonElement>("[data-sort]").forEach(button => {
    button.addEventListener("click", () => {
        const requestedSort = button.dataset.sort ?? "date";
        if (sortMode === requestedSort) {
            sortAscending = !sortAscending;
        } else {
            sortMode = requestedSort;
            sortAscending = requestedSort === "name" || requestedSort === "location";
        }
        renderTracks();
    });
});
void restoreLibrary();

async function importFiles(fileList: FileList | null): Promise<void> {
    if (!fileList?.length) return;
    await knownTrackLocationsPromise;
    errorMessage.hidden = true;
    const failures: string[] = [];
    const selectedFiles = Array.from(fileList).filter(file => {
        const name = file.name.toLocaleLowerCase();
        return name.endsWith(".gpx") || name.endsWith(".zip");
    });
    const count = document.querySelector<HTMLElement>("#track-count")!;

    if (!selectedFiles.length) {
        errorMessage.textContent = "The selected folder does not contain GPX or ZIP files.";
        errorMessage.hidden = false;
        return;
    }

    for (const [index, file] of selectedFiles.entries()) {
        count.textContent = `Importing ${index + 1} of ${selectedFiles.length}…`;
        if (index % 20 === 0) {
            await new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
        }
        try {
            const result = await importFile(file);
            failures.push(...result.failures);
            result.tracks.forEach(track => {
                track.color = polylineColor;
                tracks.push(track);
            });
        } catch (error) {
            failures.push(`${file.name}: ${error instanceof Error ? error.message : "could not be read"}`);
        }
    }

    fileInput.value = "";
    folderInput.value = "";
    if (failures.length) {
        errorMessage.textContent = failures.join(" ");
        errorMessage.hidden = false;
    }
    renderTracks();
    updateMap(true);
    void saveLibrary();
}

async function importFile(file: File): Promise<ImportResult> {
    if (file.name.toLocaleLowerCase().endsWith(".zip") || file.type === "application/zip") {
        return importZIP(file);
    }
    const displayName = file.webkitRelativePath || file.name;
    return { tracks: parseGPX(await file.text(), displayName), failures: [] };
}

async function importZIP(file: File): Promise<ImportResult> {
    const maximumArchiveSize = 100 * 1024 * 1024;
    const maximumGPXSize = 25 * 1024 * 1024;
    if (file.size > maximumArchiveSize) {
        throw new Error("ZIP archives must be 100 MB or smaller");
    }

    const archiveBytes = new Uint8Array(await file.arrayBuffer());
    const entries = await new Promise<Record<string, Uint8Array>>((resolve, reject) => {
        unzip(
            archiveBytes,
            {
                filter: entry => entry.name.toLocaleLowerCase().endsWith(".gpx")
                    && entry.originalSize <= maximumGPXSize
                    && !entry.name.startsWith("__MACOSX/")
            },
            (error, archiveEntries) => error ? reject(error) : resolve(archiveEntries)
        );
    });

    const gpxEntries = Object.entries(entries);
    if (!gpxEntries.length) throw new Error("ZIP archive does not contain any readable GPX files");

    const imported: Track[] = [];
    const failures: string[] = [];
    for (const [path, data] of gpxEntries) {
        try {
            imported.push(...parseGPX(strFromU8(data), path));
        } catch (error) {
            failures.push(`${path}: ${error instanceof Error ? error.message : "could not be read"}`);
        }
    }
    if (!imported.length) throw new Error("none of the GPX files in the ZIP could be read");
    return { tracks: imported, failures };
}

function parseGPX(source: string, fileName: string): Track[] {
    const documentNode = new DOMParser().parseFromString(source, "application/xml");
    if (documentNode.querySelector("parsererror")) throw new Error("invalid GPX XML");

    const trackElements = Array.from(documentNode.querySelectorAll("trk"));
    const routeElements = Array.from(documentNode.querySelectorAll("rte"));
    const parsed = [
        ...trackElements.map(element => parseTrackElement(element, "trkpt", fileName)),
        ...routeElements.map(element => parseTrackElement(element, "rtept", fileName))
    ].filter((track): track is Track => track !== null);

    if (!parsed.length) throw new Error("no track or route with at least two points");
    return parsed;
}

function parseTrackElement(element: Element, pointName: string, fileName: string): Track | null {
    const coordinatesIn = (container: Element): Coordinate[] => Array.from(container.querySelectorAll(pointName)).flatMap(point => {
        const latitude = Number(point.getAttribute("lat"));
        const longitude = Number(point.getAttribute("lon"));
        const elevationText = point.querySelector(":scope > ele")?.textContent;
        if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return [];
        const elevation = elevationText === undefined ? undefined : Number(elevationText);
        return [[longitude, latitude, Number.isFinite(elevation) ? elevation : undefined] as Coordinate];
    });
    const trackSegments = pointName === "trkpt"
        ? Array.from(element.querySelectorAll(":scope > trkseg"))
            .map(coordinatesIn)
            .filter(segment => segment.length >= 2)
        : [];
    const segments = trackSegments.length ? trackSegments : [coordinatesIn(element)]
        .filter(segment => segment.length >= 2);
    const coordinates = segments.flat();
    if (coordinates.length < 2) return null;

    const pathParts = fileName.split("/");
    const fallbackName = (pathParts.at(-1) ?? fileName).replace(/\.gpx$/i, "");
    const folderLocation = pathParts.length > 1 ? pathParts.at(-2) ?? "" : "";
    const rawName = element.querySelector(":scope > name")?.textContent?.trim() || fallbackName;
    const extractedMetadata = extractTrackMetadata(rawName);
    const name = extractedMetadata.name;
    const timeText = element.querySelector(`${pointName} time`)?.textContent;
    const date = timeText ? new Date(timeText) : undefined;
    const id = crypto.randomUUID();

    return {
        id,
        name,
        fileName,
        location: locationForTrack(name, coordinates, extractedMetadata.location, folderLocation),
        coordinates,
        segments,
        distanceMetres: segments.reduce((total, segment) => total + distanceOf(segment), 0),
        ascentMetres: segments.reduce((total, segment) => total + ascentOf(segment), 0),
        date: date && !Number.isNaN(date.valueOf()) ? date : undefined,
        color: polylineColor,
        visible: true
    };
}

function distanceOf(coordinates: Coordinate[]): number {
    const earthRadius = 6_371_000;
    return coordinates.slice(1).reduce((total, coordinate, index) => {
        const previous = coordinates[index];
        const latitudeDelta = toRadians(coordinate[1] - previous[1]);
        const longitudeDelta = toRadians(coordinate[0] - previous[0]);
        const startLatitude = toRadians(previous[1]);
        const endLatitude = toRadians(coordinate[1]);
        const a = Math.sin(latitudeDelta / 2) ** 2
            + Math.cos(startLatitude) * Math.cos(endLatitude) * Math.sin(longitudeDelta / 2) ** 2;
        return total + earthRadius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }, 0);
}

function ascentOf(coordinates: Coordinate[]): number {
    return coordinates.slice(1).reduce((total, coordinate, index) => {
        const previousElevation = coordinates[index][2];
        const elevation = coordinate[2];
        return total + (elevation !== undefined && previousElevation !== undefined && elevation > previousElevation
            ? elevation - previousElevation
            : 0);
    }, 0);
}

function toRadians(value: number): number {
    return value * Math.PI / 180;
}

function renderTracks(): void {
    const list = document.querySelector<HTMLElement>("#track-list")!;
    const count = document.querySelector<HTMLElement>("#track-count")!;
    const displayedTracks = sortedMatchingTracks();
    count.textContent = searchQuery
        ? `${displayedTracks.length} of ${tracks.length} tracks`
        : tracks.length === 1 ? "1 track loaded" : `${tracks.length} tracks loaded`;
    updateExportAvailability();

    document.querySelectorAll<HTMLButtonElement>("[data-sort]").forEach(button => {
        const active = button.dataset.sort === sortMode;
        button.classList.toggle("is-active", active);
        button.classList.toggle("is-descending", active && !sortAscending);
        button.setAttribute("aria-sort", active ? (sortAscending ? "ascending" : "descending") : "none");
    });

    list.replaceChildren(...displayedTracks.map(track => {
        const row = document.createElement("div");
        row.className = "track-row";
        row.tabIndex = 0;
        row.setAttribute("role", "button");
        row.dataset.trackId = track.id;
        row.classList.toggle("is-selected", selectedTrackIDs.has(track.id));
        row.title = `Zoom to ${track.name}`;
        row.innerHTML = `
          <input class="track-select" type="checkbox" data-track-id="${track.id}"
                 aria-label="Select ${escapeHTML(displayName(track.name))}"
                 ${selectedTrackIDs.has(track.id) ? "checked" : ""} />
          <span>${track.date ? track.date.toLocaleDateString() : "—"}</span>
          <span class="track-name">${escapeHTML(displayName(track.name))}</span>
          <span>${escapeHTML(track.location || "—")}</span>
          <span>${(track.distanceMetres / 1000).toFixed(1)} km</span>
          <span>${Math.round(track.ascentMetres)} m</span>`;
        row.addEventListener("click", () => {
            selectTrack(track, false);
            fitTrack(track);
        });
        row.addEventListener("keydown", event => {
            if (event.key !== "Enter" && event.key !== " ") return;
            event.preventDefault();
            selectTrack(track, false);
            fitTrack(track);
        });
        const checkbox = row.querySelector<HTMLInputElement>(".track-select")!;
        checkbox.addEventListener("click", event => event.stopPropagation());
        checkbox.addEventListener("change", () => {
            if (checkbox.checked) {
                selectTrack(track, false);
                fitTrack(track);
            } else {
                deselectTrack(track);
            }
        });
        return row;
    }));
}

function updateMap(shouldFit: boolean): void {
    scheduleOverlayDraw();
    if (shouldFit) fitAllTracks();
}

function scheduleOverlayDraw(): void {
    if (overlayFrame !== undefined) cancelAnimationFrame(overlayFrame);
    overlayFrame = requestAnimationFrame(drawTrackOverlay);
}

function drawTrackOverlay(): void {
    overlayFrame = undefined;
    const bounds = trackOverlay.getBoundingClientRect();
    if (!bounds.width || !bounds.height) return;

    const scale = window.devicePixelRatio || 1;
    const width = Math.round(bounds.width * scale);
    const height = Math.round(bounds.height * scale);
    if (trackOverlay.width !== width || trackOverlay.height !== height) {
        trackOverlay.width = width;
        trackOverlay.height = height;
    }

    const context = trackOverlay.getContext("2d");
    if (!context) return;
    context.setTransform(scale, 0, 0, scale, 0, 0);
    context.clearRect(0, 0, bounds.width, bounds.height);
    context.lineJoin = "round";
    context.lineCap = "round";
    screenTrackPaths = [];

    tracks.filter(isVisibleOnMap)
        .sort((left, right) => Number(selectedTrackIDs.has(left.id)) - Number(selectedTrackIDs.has(right.id)))
        .forEach(track => {
        const isSelected = selectedTrackIDs.has(track.id);
        track.segments.forEach(segment => {
            const pointLimit = map.getZoom() < 8 ? 180 : map.getZoom() < 11 ? 450 : 1_000;
            const step = Math.max(1, Math.floor(segment.length / pointLimit));
            const points: maplibregl.Point[] = [];
            context.beginPath();
            segment.forEach((coordinate, index) => {
                if (index % step !== 0 && index !== segment.length - 1) return;
                const point = map.project([coordinate[0], coordinate[1]]);
                points.push(point);
                if (points.length === 1) context.moveTo(point.x, point.y);
                else context.lineTo(point.x, point.y);
            });
            context.strokeStyle = "rgba(255, 255, 255, .92)";
            context.lineWidth = isSelected ? 8 : 6;
            context.stroke();
            context.strokeStyle = isSelected
                ? contrastingTrackColor(polylineColor)
                : track.color || polylineColor;
            context.lineWidth = isSelected ? 5 : 3.5;
            context.stroke();
            screenTrackPaths.push({ track, points });
        });
    });
}

function trackAtPoint(point: maplibregl.Point, tolerance = 8): Track | undefined {
    let closestTrack: Track | undefined;
    let closestDistance = tolerance;
    screenTrackPaths.forEach(path => {
        const hitStep = Math.max(1, Math.floor(path.points.length / 600));
        for (let index = hitStep; index < path.points.length; index += hitStep) {
            const start = path.points[Math.max(0, index - hitStep)];
            const end = path.points[index];
            const distance = distanceToSegment(point, start, end);
            if (distance < closestDistance) {
                closestDistance = distance;
                closestTrack = path.track;
            }
        }
    });
    return closestTrack;
}

function distanceToSegment(point: maplibregl.Point, start: maplibregl.Point, end: maplibregl.Point): number {
    const deltaX = end.x - start.x;
    const deltaY = end.y - start.y;
    if (deltaX === 0 && deltaY === 0) return point.dist(start);
    const amount = Math.max(0, Math.min(1,
        ((point.x - start.x) * deltaX + (point.y - start.y) * deltaY)
        / (deltaX * deltaX + deltaY * deltaY)
    ));
    return Math.hypot(point.x - (start.x + amount * deltaX), point.y - (start.y + amount * deltaY));
}

function showTrackHover(point: maplibregl.Point): void {
    const track = trackAtPoint(point);
    map.getCanvas().style.cursor = track ? "pointer" : "";
    if (!track) {
        hideTrackHover();
        return;
    }
    trackHoverCard.innerHTML = `
      <strong>${escapeHTML(displayName(track.name))}</strong>
      <span>${track.date ? track.date.toLocaleDateString() : "Date unknown"}</span>
      <span>${escapeHTML(track.location || "Location unknown")}</span>
      <span>${(track.distanceMetres / 1000).toFixed(1)} km · ${Math.round(track.ascentMetres)} m ascent</span>`;
    trackHoverCard.style.left = `${point.x + 14}px`;
    trackHoverCard.style.top = `${point.y + 14}px`;
    trackHoverCard.hidden = false;
}

function hideTrackHover(): void {
    trackHoverCard.hidden = true;
    map.getCanvas().style.cursor = "";
}

function selectTrackAt(point: maplibregl.Point): void {
    const track = trackAtPoint(point);
    if (!track) return;
    selectTrack(track, true);
}

function selectTrack(track: Track, shouldScroll: boolean): void {
    selectedTrackIDs.add(track.id);
    updateExportAvailability();
    if (showOnlySelected) {
        renderTracks();
        scheduleOverlayDraw();
        return;
    }
    const row = document.querySelector<HTMLElement>(`.track-row[data-track-id="${CSS.escape(track.id)}"]`);
    row?.classList.add("is-selected");
    const checkbox = row?.querySelector<HTMLInputElement>(".track-select");
    if (checkbox) checkbox.checked = true;
    if (shouldScroll) row?.scrollIntoView({ behavior: "smooth", block: "center" });
    scheduleOverlayDraw();
}

function deselectTrack(track: Track): void {
    selectedTrackIDs.delete(track.id);
    updateExportAvailability();
    if (showOnlySelected) renderTracks();
    const row = document.querySelector<HTMLElement>(`.track-row[data-track-id="${CSS.escape(track.id)}"]`);
    row?.classList.remove("is-selected");
    const checkbox = row?.querySelector<HTMLInputElement>(".track-select");
    if (checkbox) checkbox.checked = false;
    scheduleOverlayDraw();
}

function contrastingTrackColor(baseColor: string): string {
    const base = baseColor.match(/[a-f\d]{2}/gi)?.map(value => Number.parseInt(value, 16)) ?? [217, 39, 28];
    const candidates = ["#00d9ff", "#ffe000", "#ff3bd4", "#39e639"];
    return candidates
        .map(color => ({
            color,
            channels: color.match(/[a-f\d]{2}/gi)!.map(value => Number.parseInt(value, 16))
        }))
        .sort((left, right) => {
            const score = (channels: number[]) => channels.reduce(
                (total, channel, index) => total + (channel - base[index]) ** 2,
                0
            );
            return score(right.channels) - score(left.channels);
        })[0].color;
}

function trackFeature(track: Track): Feature<Geometry> {
    const segmentCoordinates = track.segments.map(segment => segment.map(
        ([longitude, latitude, elevation]) =>
            elevation === undefined ? [longitude, latitude] : [longitude, latitude, elevation]
    ));
    return {
        type: "Feature",
        properties: { id: track.id, name: track.name, color: track.color },
        geometry: segmentCoordinates.length === 1
            ? { type: "LineString", coordinates: segmentCoordinates[0] }
            : { type: "MultiLineString", coordinates: segmentCoordinates }
    };
}

function fitAllTracks(): void {
    const visibleTracks = tracks.filter(isVisibleOnMap);
    const coordinates = visibleTracks.flatMap(track => {
        const step = Math.max(1, Math.floor(track.coordinates.length / 250));
        return track.coordinates.filter((_, index) =>
            index % step === 0 || index === track.coordinates.length - 1
        );
    });
    if (coordinates.length < 20 || visibleTracks.length < 5) {
        fitCoordinates(coordinates);
        return;
    }

    const longitudes = coordinates.map(coordinate => coordinate[0]).sort((left, right) => left - right);
    const latitudes = coordinates.map(coordinate => coordinate[1]).sort((left, right) => left - right);
    const lowerIndex = Math.floor(coordinates.length * 0.1);
    const upperIndex = Math.ceil(coordinates.length * 0.9) - 1;
    const bulkBounds: Coordinate[] = [
        [longitudes[lowerIndex], latitudes[lowerIndex]],
        [longitudes[upperIndex], latitudes[upperIndex]]
    ];
    fitCoordinates(bulkBounds);
}

function sortedMatchingTracks(): Track[] {
    const query = searchQuery.toLocaleLowerCase();
    return tracks
        .filter(track => (!showOnlySelected || selectedTrackIDs.has(track.id)) && (!query || [
            displayName(track.name),
            track.fileName,
            track.location ?? "",
            track.date?.toLocaleDateString() ?? "",
            (track.distanceMetres / 1000).toFixed(1),
            Math.round(track.ascentMetres).toString()
        ]
            .some(value => value.toLocaleLowerCase().includes(query))))
        .sort((left, right) => {
            let comparison: number;
            switch (sortMode) {
            case "distance": comparison = left.distanceMetres - right.distanceMetres; break;
            case "ascent": comparison = left.ascentMetres - right.ascentMetres; break;
            case "location": comparison = (left.location ?? "").localeCompare(right.location ?? ""); break;
            case "date": comparison = (left.date?.valueOf() ?? 0) - (right.date?.valueOf() ?? 0); break;
            default: comparison = displayName(left.name).localeCompare(displayName(right.name), undefined, { numeric: true });
            }
            return sortAscending ? comparison : -comparison;
        });
}

function isVisibleOnMap(track: Track): boolean {
    return track.visible && (!showOnlySelected || selectedTrackIDs.has(track.id));
}

function openLibraryDatabase(): Promise<IDBDatabase> {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open("baregps-track-viewer", 1);
        request.onupgradeneeded = () => request.result.createObjectStore("library");
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
    });
}

async function saveLibrary(): Promise<void> {
    const database = await openLibraryDatabase();
    await new Promise<void>((resolve, reject) => {
        const transaction = database.transaction("library", "readwrite");
        transaction.objectStore("library").put(tracks, "tracks");
        transaction.oncomplete = () => resolve();
        transaction.onerror = () => reject(transaction.error);
    });
    database.close();
}

async function restoreLibrary(): Promise<void> {
    await knownTrackLocationsPromise;
    const database = await openLibraryDatabase();
    const storedTracks = await new Promise<Track[] | undefined>((resolve, reject) => {
        const request = database.transaction("library").objectStore("library").get("tracks");
        request.onsuccess = () => resolve(request.result as Track[] | undefined);
        request.onerror = () => reject(request.error);
    });
    database.close();
    if (!storedTracks?.length || tracks.length) return;
    tracks.push(...storedTracks.map(track => {
        const extractedMetadata = extractTrackMetadata(track.name);
        const segments = track.segments?.length ? track.segments : inferSegments(track.coordinates);
        return {
            ...track,
            name: extractedMetadata.name,
            location: locationForTrack(
                extractedMetadata.name,
                track.coordinates,
                extractedMetadata.location,
                track.location
            ),
            segments,
            distanceMetres: segments.reduce((total, segment) => total + distanceOf(segment), 0),
            ascentMetres: segments.reduce((total, segment) => total + ascentOf(segment), 0),
            color: polylineColor,
            visible: true
        };
    }));
    renderTracks();
    updateMap(true);
    void saveLibrary();
}

function fitTrack(track: Track): void {
    fitCoordinates(track.coordinates);
}

function fitCoordinates(coordinates: Coordinate[]): void {
    if (!coordinates.length) return;
    const bounds = coordinates.reduce(
        (current, coordinate) => current.extend([coordinate[0], coordinate[1]]),
        new maplibregl.LngLatBounds(
            [coordinates[0][0], coordinates[0][1]],
            [coordinates[0][0], coordinates[0][1]]
        )
    );
    map.fitBounds(bounds, { padding: 60, maxZoom: 15, duration: 300 });
}

function exportGeoJSON(selectedOnly: boolean): void {
    const exportedTracks = tracksForExport(selectedOnly);
    const collection: FeatureCollection<Geometry> = {
        type: "FeatureCollection",
        features: exportedTracks.map(trackFeature)
    };
    const blob = new Blob([JSON.stringify(collection, null, 2)], { type: "application/geo+json" });
    downloadBlob(blob, selectedOnly ? "baregps-selected-tracks.geojson" : "baregps-all-tracks.geojson");
}

function exportZIP(selectedOnly: boolean): void {
    const files: Record<string, Uint8Array> = {};
    tracksForExport(selectedOnly).forEach((track, index) => {
        const baseName = displayName(track.name).replace(/[^\p{L}\p{N}._-]+/gu, "-").replace(/^-|-$/g, "")
            || `track-${index + 1}`;
        const uniqueName = files[`${baseName}.gpx`] ? `${baseName}-${index + 1}` : baseName;
        files[`${uniqueName}.gpx`] = strToU8(trackAsGPX(track));
    });
    const blob = new Blob([zipSync(files, { level: 6 })], { type: "application/zip" });
    downloadBlob(blob, selectedOnly ? "baregps-selected-tracks.zip" : "baregps-all-tracks.zip");
}

function trackAsGPX(track: Track): string {
    const segments = track.segments.map(segment => `<trkseg>${segment.map(coordinate => {
        const elevation = coordinate[2] === undefined ? "" : `<ele>${coordinate[2]}</ele>`;
        return `<trkpt lat="${coordinate[1]}" lon="${coordinate[0]}">${elevation}</trkpt>`;
    }).join("")}</trkseg>`).join("");
    return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="BareGPS Track Viewer" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>${escapeXML(displayName(track.name))}</name>${segments}</trk>
</gpx>`;
}

function tracksForExport(selectedOnly: boolean): Track[] {
    return selectedOnly ? tracks.filter(track => selectedTrackIDs.has(track.id)) : tracks;
}

function updateExportAvailability(): void {
    exportButtons.forEach(button => {
        const selectedOnly = button.dataset.export?.endsWith("selected") ?? false;
        button.disabled = selectedOnly ? selectedTrackIDs.size === 0 : tracks.length === 0;
    });
    if (pendingExport) {
        const pendingButton = exportButtons.find(button => button.dataset.export === pendingExport);
        if (pendingButton?.disabled) pendingExport = undefined;
    }
    updateExportConfirmation();
}

function updateExportConfirmation(): void {
    if (!pendingExport) {
        exportSummary.textContent = "Choose an export option.";
        exportConfirmButton.disabled = true;
        exportButtons.forEach(option => option.classList.remove("is-pending"));
        return;
    }
    const selectedOnly = pendingExport.endsWith("selected");
    const count = tracksForExport(selectedOnly).length;
    const format = pendingExport.startsWith("zip") ? "ZIP" : "GeoJSON";
    exportSummary.textContent = `Export of ${count} track${count === 1 ? "" : "s"} to ${format} — press Confirm.`;
    exportConfirmButton.disabled = count === 0;
}

function downloadBlob(blob: Blob, fileName: string): void {
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = fileName;
    link.click();
    URL.revokeObjectURL(url);
}

function escapeXML(value: string): string {
    return value.replace(/[<>&"']/g, character => ({
        "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;", "'": "&apos;"
    })[character]!);
}

function inferSegments(coordinates: Coordinate[]): Coordinate[][] {
    if (coordinates.length < 2) return coordinates.length ? [coordinates] : [];
    const segments: Coordinate[][] = [[coordinates[0]]];
    coordinates.slice(1).forEach((coordinate, index) => {
        const previous = coordinates[index];
        if (distanceOf([previous, coordinate]) > 1_000) segments.push([]);
        segments.at(-1)!.push(coordinate);
    });
    return segments.filter(segment => segment.length >= 2);
}

function escapeHTML(value: string): string {
    const element = document.createElement("div");
    element.textContent = value;
    return element.innerHTML;
}

function displayName(value: string): string {
    const shortened = value
        .replace(/^track\b[\s:_-]*/i, "")
        .replace(/[\\/]+/g, " ")
        .replace(/\s+/g, " ")
        .trim();
    return shortened || value;
}

function extractTrackMetadata(value: string): { name: string; location: string } {
    const match = value.trim().match(
        /(?:track[\/\s:_-]*)?(\d+)\s+in\s+(?:the\s+)?area\s+near\s+(.+?)\s*\(([^)]+)\)/i
    );
    if (!match) return { name: value, location: "" };

    const place = match[2].trim();
    const country = match[3]?.trim();
    return {
        name: match[1],
        location: country ? `${country}, ${place}` : place
    };
}

function locationForTrack(
    name: string,
    coordinates: Coordinate[],
    extractedLocation = "",
    fallbackLocation = ""
): string {
    const number = displayName(name).match(/^\d+/)?.[0];
    const knownLocation = number ? knownTrackLocations[number] : undefined;
    if (knownLocation) return formatKnownLocation(knownLocation, coordinates);
    if (extractedLocation) {
        const country = extractedLocation.match(/^([^,]+),\s*(.+)$/);
        return country
            ? `${country[2]} · ${country[1].toLocaleLowerCase() === "ireland" ? "IRL" : country[1]}`
            : extractedLocation;
    }
    return inferOfflineLocation(coordinates) || fallbackLocation;
}
