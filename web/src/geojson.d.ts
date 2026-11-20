declare namespace GeoJSON {
    interface LineString {
        type: "LineString";
        coordinates: number[][];
    }

    interface Feature<G> {
        type: "Feature";
        properties: Record<string, unknown>;
        geometry: G;
    }

    interface FeatureCollection<G> {
        type: "FeatureCollection";
        features: Array<Feature<G>>;
    }
}
