export type GeoCoordinate = [longitude: number, latitude: number, elevation?: number];

interface NamedPoint {
    name: string;
    code: string;
    latitude: number;
    longitude: number;
    radius?: number;
}

const counties: NamedPoint[] = [
    ["Carlow","IRL",52.72,-6.84],["Cavan","IRL",53.99,-7.36],["Clare","IRL",52.84,-9.00],
    ["Cork","IRL",51.90,-8.75],["Donegal","IRL",54.95,-7.90],["Dublin","IRL",53.35,-6.26],
    ["Galway","IRL",53.35,-9.05],["Kerry","IRL",52.15,-9.75],["Kildare","IRL",53.16,-6.91],
    ["Kilkenny","IRL",52.58,-7.25],["Laois","IRL",53.00,-7.33],["Leitrim","IRL",54.13,-8.00],
    ["Limerick","IRL",52.52,-8.75],["Longford","IRL",53.73,-7.73],["Louth","IRL",53.90,-6.47],
    ["Mayo","IRL",53.90,-9.30],["Meath","IRL",53.65,-6.67],["Monaghan","IRL",54.18,-6.95],
    ["Offaly","IRL",53.23,-7.56],["Roscommon","IRL",53.70,-8.25],["Sligo","IRL",54.15,-8.55],
    ["Tipperary","IRL",52.65,-7.95],["Waterford","IRL",52.18,-7.50],["Westmeath","IRL",53.53,-7.47],
    ["Wexford","IRL",52.45,-6.58],["Wicklow","IRL",53.00,-6.42],
    ["Antrim","GBR",54.85,-6.15],["Armagh","GBR",54.35,-6.65],["Down","GBR",54.38,-5.95],
    ["Fermanagh","GBR",54.35,-7.65],["Londonderry","GBR",54.90,-6.95],["Tyrone","GBR",54.60,-7.20],
    ["Cumbria","GBR",54.58,-2.90],["Northumberland","GBR",55.25,-2.05],["Durham","GBR",54.70,-1.85],
    ["North Yorkshire","GBR",54.25,-1.50],["Derbyshire","GBR",53.18,-1.65],["Lancashire","GBR",53.85,-2.60],
    ["Gwynedd","GBR",52.90,-4.15],["Powys","GBR",52.35,-3.40],["Ceredigion","GBR",52.25,-4.05],
    ["Carmarthenshire","GBR",51.85,-4.20],["Pembrokeshire","GBR",51.82,-4.90],["Conwy","GBR",53.10,-3.75],
    ["Highland","GBR",57.25,-4.70],["Perth and Kinross","GBR",56.55,-3.80],["Argyll and Bute","GBR",56.20,-5.25],
    ["Aberdeenshire","GBR",57.20,-2.70],["Dumfries and Galloway","GBR",55.05,-4.00],
    ["Scottish Borders","GBR",55.55,-2.75],["Cornwall","GBR",50.40,-4.85],["Devon","GBR",50.72,-3.85]
].map(([name, code, latitude, longitude]) => ({ name, code, latitude, longitude })) as NamedPoint[];

const ranges: NamedPoint[] = [
    ["Wicklow Mountains","IRL",53.05,-6.38,42],["Mourne Mountains","GBR",54.18,-6.02,28],
    ["MacGillycuddy's Reeks","IRL",52.00,-9.72,28],["Dunkerron Mountains","IRL",51.95,-9.85,32],
    ["Galty Mountains","IRL",52.37,-8.18,28],["Comeragh Mountains","IRL",52.23,-7.53,26],
    ["Knockmealdown Mountains","IRL",52.23,-7.92,23],["Slieve Bloom","IRL",53.08,-7.55,26],
    ["Blackstairs Mountains","IRL",52.62,-6.80,26],["Cooley Mountains","IRL",54.04,-6.22,20],
    ["Twelve Bens","IRL",53.50,-9.83,24],["Maumturk Mountains","IRL",53.50,-9.65,24],
    ["Partry Mountains","IRL",53.62,-9.55,25],["Nephin Beg Range","IRL",54.02,-9.65,32],
    ["Ox Mountains","IRL",54.12,-8.85,34],["Dartry Mountains","IRL",54.35,-8.35,28],
    ["Bluestack Mountains","IRL",54.75,-8.05,34],["Derryveagh Mountains","IRL",55.02,-8.10,35],
    ["Sperrin Mountains","GBR",54.72,-7.05,38],["Antrim Hills","GBR",54.95,-6.10,32],
    ["Snowdonia","GBR",53.07,-4.08,48],["Cambrian Mountains","GBR",52.35,-3.70,55],
    ["Brecon Beacons","GBR",51.88,-3.43,38],["Lake District","GBR",54.50,-3.12,48],
    ["Pennines","GBR",54.10,-2.20,115],["Cairngorms","GBR",57.08,-3.65,55],
    ["Grampian Mountains","GBR",56.75,-4.25,80],["Northwest Highlands","GBR",57.55,-5.15,80],
    ["Southern Uplands","GBR",55.35,-3.60,90],["Dartmoor","GBR",50.58,-3.90,32],
    ["Alps","",46.55,10.00,520],["Pyrenees","",42.75,0.50,310],["Carpathians","",47.50,24.50,500],
    ["Dolomites","ITA",46.50,11.90,100],["Appalachians","USA",37.50,-81.00,900],
    ["Rocky Mountains","",43.00,-110.00,1300],["Southern Alps","NZL",-43.60,170.20,450]
].map(([name, code, latitude, longitude, radius]) => ({ name, code, latitude, longitude, radius })) as NamedPoint[];

const countries: Array<{ code: string; south: number; west: number; north: number; east: number }> = [
    { code:"IRL", south:51.35, west:-10.75, north:55.48, east:-5.35 },
    { code:"GBR", south:49.8, west:-8.7, north:60.9, east:2.0 },
    { code:"FRA", south:41.2, west:-5.3, north:51.2, east:9.7 },
    { code:"ESP", south:35.7, west:-9.5, north:43.9, east:3.4 },
    { code:"PRT", south:36.8, west:-9.6, north:42.2, east:-6.1 },
    { code:"ITA", south:36.4, west:6.6, north:47.2, east:18.7 },
    { code:"CHE", south:45.8, west:5.9, north:47.9, east:10.5 },
    { code:"AUT", south:46.3, west:9.4, north:49.1, east:17.2 },
    { code:"DEU", south:47.2, west:5.8, north:55.2, east:15.1 },
    { code:"NOR", south:57.8, west:4.0, north:71.3, east:31.2 },
    { code:"SWE", south:55.2, west:10.8, north:69.2, east:24.2 },
    { code:"ISL", south:63.2, west:-24.7, north:66.7, east:-13.2 },
    { code:"USA", south:24.0, west:-125.0, north:49.5, east:-66.0 },
    { code:"CAN", south:41.5, west:-141.0, north:83.5, east:-52.0 },
    { code:"NZL", south:-47.5, west:166.0, north:-34.0, east:179.9 },
    { code:"AUS", south:-44.0, west:112.0, north:-10.0, east:154.0 }
];

export function inferOfflineLocation(coordinates: GeoCoordinate[]): string {
    if (!coordinates.length) return "";
    const centre = trackCentre(coordinates);
    const code = countryCode(centre.latitude, centre.longitude);
    const county = nearest(counties.filter(item => item.code === code), centre.latitude, centre.longitude, code === "IRL" ? 85 : 140);
    const range = nearest(ranges.filter(item => !item.code || item.code === code), centre.latitude, centre.longitude);
    return unique([range?.name, county?.name, code]).join(" · ");
}

export function formatKnownLocation(raw: string, coordinates: GeoCoordinate[]): string {
    const inferred = inferOfflineLocation(coordinates).split(" · ");
    const parts = raw.split(",").map(value => value.trim()).filter(value =>
        value && !/^(ireland|britain|unid)$/i.test(value)
    );
    const rawCountry = /^ireland,/i.test(raw) ? "IRL" : /^britain,/i.test(raw) ? "GBR" : "";
    const code = rawCountry || inferred.at(-1) || "";
    const inferredCounty = inferred.length > 1 ? inferred.at(-2) ?? "" : "";
    return unique([...parts, inferredCounty, code]).join(" · ");
}

function trackCentre(coordinates: GeoCoordinate[]): { latitude: number; longitude: number } {
    const elevated = coordinates.filter(coordinate => coordinate[2] !== undefined);
    const candidates = elevated.length
        ? elevated.sort((left, right) => (right[2] ?? 0) - (left[2] ?? 0)).slice(0, Math.max(1, Math.ceil(elevated.length * 0.1)))
        : coordinates;
    return {
        longitude: candidates.reduce((sum, coordinate) => sum + coordinate[0], 0) / candidates.length,
        latitude: candidates.reduce((sum, coordinate) => sum + coordinate[1], 0) / candidates.length
    };
}

function countryCode(latitude: number, longitude: number): string {
    if (latitude > 54.0 && longitude > -8.2 && longitude < -5.3) return "GBR";
    return countries.find(country =>
        latitude >= country.south && latitude <= country.north
        && longitude >= country.west && longitude <= country.east
    )?.code ?? "";
}

function nearest(items: NamedPoint[], latitude: number, longitude: number, maximum?: number): NamedPoint | undefined {
    return items
        .map(item => ({ item, distance: distance(latitude, longitude, item.latitude, item.longitude) }))
        .filter(candidate => candidate.distance <= (candidate.item.radius ?? maximum ?? 0))
        .sort((left, right) => left.distance - right.distance)[0]?.item;
}

function distance(latitude: number, longitude: number, otherLatitude: number, otherLongitude: number): number {
    const latitudeScale = 111.32;
    const longitudeScale = latitudeScale * Math.cos(latitude * Math.PI / 180);
    return Math.hypot((latitude - otherLatitude) * latitudeScale, (longitude - otherLongitude) * longitudeScale);
}

function unique(values: Array<string | undefined>): string[] {
    return values.filter((value, index, all): value is string =>
        Boolean(value) && all.findIndex(item => item?.toLocaleLowerCase() === value?.toLocaleLowerCase()) === index
    );
}
