# BareGPS Track Viewer

Open `Track Viewer.xcodeproj` in Xcode for the macOS app. The app's existing track library uses local copies of `OnzyTracks.geojson` and `TrackMetadata.json` in `Track Viewer/TrackData/`. Restore both files there when setting up the app on a new Mac.

The source for the browser version lives in `web/`. From that directory, run `npm ci` and `npm run build` to produce `dist/`. The browser app can also use an optional local track-location lookup at `web/public/known-track-locations.json`.
