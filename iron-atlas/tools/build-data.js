// Builds www/data/provinces.js for Iron Atlas.
// Country borders come from Natural Earth (via world-atlas, 1:50m). Each country
// is split into "provinces" with k-means seeded Voronoi cells, then adjacency
// (land + sea lanes) is precomputed so the game can stay lightweight.
// Usage: node build-data.js
const fs = require('fs');
const path = require('path');
const topo = require('world-atlas/countries-50m.json');
const tc = require('topojson-client');
const ts = require('topojson-simplify');
const { Delaunay } = require('d3-delaunay');
const pc = require('polygon-clipping');

const BBOX = [-25, 34, 50, 71.5]; // lon/lat
const KM_PER_PROVINCE = 30000;
const MAX_PROVINCES = 34;

// name in world-atlas -> [code, display name, power, group members merged in]
const COUNTRIES = {
  'Albania': ['ALB', 'Albania', 0.8], 'Andorra': null, 'Armenia': ['ARM', 'Armenia', 0.9],
  'Austria': ['AUT', 'Austria', 1.0], 'Azerbaijan': ['AZE', 'Azerbaijan', 1.0],
  'Belarus': ['BLR', 'Belarus', 1.1], 'Belgium': ['BEL', 'Belgium', 1.0],
  'Bosnia and Herz.': ['BIH', 'Bosnia', 0.8], 'Bulgaria': ['BGR', 'Bulgaria', 0.9],
  'Croatia': ['HRV', 'Croatia', 0.9], 'Cyprus': ['CYP', 'Cyprus', 0.8], 'N. Cyprus': 'Cyprus',
  'Czechia': ['CZE', 'Czechia', 1.0], 'Denmark': ['DNK', 'Denmark', 1.0], 'Faeroe Is.': 'Denmark',
  'Estonia': ['EST', 'Estonia', 0.9], 'Finland': ['FIN', 'Finland', 1.2], 'Åland': 'Finland',
  'France': ['FRA', 'France', 1.6], 'Georgia': ['GEO', 'Georgia', 0.9],
  'Germany': ['DEU', 'Germany', 1.5], 'Greece': ['GRC', 'Greece', 1.2],
  'Hungary': ['HUN', 'Hungary', 1.0], 'Iceland': ['ISL', 'Iceland', 0.6],
  'Ireland': ['IRL', 'Ireland', 0.8], 'Italy': ['ITA', 'Italy', 1.4], 'Kosovo': ['XKX', 'Kosovo', 0.7],
  'Latvia': ['LVA', 'Latvia', 0.9], 'Lithuania': ['LTU', 'Lithuania', 0.9],
  'Luxembourg': ['LUX', 'Luxembourg', 0.8], 'Macedonia': ['MKD', 'North Macedonia', 0.8],
  'Moldova': ['MDA', 'Moldova', 0.8], 'Montenegro': ['MNE', 'Montenegro', 0.7],
  'Netherlands': ['NLD', 'Netherlands', 1.1], 'Norway': ['NOR', 'Norway', 1.1],
  'Poland': ['POL', 'Poland', 1.4], 'Portugal': ['PRT', 'Portugal', 1.0],
  'Romania': ['ROU', 'Romania', 1.1], 'Russia': ['RUS', 'Russia', 1.5],
  'Serbia': ['SRB', 'Serbia', 1.0], 'Slovakia': ['SVK', 'Slovakia', 0.9],
  'Slovenia': ['SVN', 'Slovenia', 0.9], 'Spain': ['ESP', 'Spain', 1.3],
  'Sweden': ['SWE', 'Sweden', 1.2], 'Switzerland': ['CHE', 'Switzerland', 1.2],
  'Turkey': ['TUR', 'Türkiye', 1.5], 'Ukraine': ['UKR', 'Ukraine', 1.4],
  'United Kingdom': ['GBR', 'United Kingdom', 1.6], 'Jersey': 'United Kingdom',
  'Guernsey': 'United Kingdom', 'Isle of Man': 'United Kingdom', 'Malta': ['MLT', 'Malta', 0.7],
};

// Cities used to name provinces: [name, lat, lon, capital?]
const CITIES = [
  ['London', 51.51, -0.13, 1], ['Birmingham', 52.48, -1.9], ['Manchester', 53.48, -2.24], ['Glasgow', 55.86, -4.25],
  ['Edinburgh', 55.95, -3.19], ['Belfast', 54.6, -5.93], ['Cardiff', 51.48, -3.18], ['Newcastle', 54.97, -1.61],
  ['Plymouth', 50.38, -4.14], ['Inverness', 57.48, -4.22], ['Norwich', 52.63, 1.3], ['Leeds', 53.8, -1.55],
  ['Dublin', 53.35, -6.26, 1], ['Cork', 51.9, -8.47], ['Galway', 53.27, -9.05],
  ['Paris', 48.86, 2.35, 1], ['Marseille', 43.3, 5.37], ['Lyon', 45.76, 4.84], ['Toulouse', 43.6, 1.44],
  ['Bordeaux', 44.84, -0.58], ['Nantes', 47.22, -1.55], ['Lille', 50.63, 3.06], ['Strasbourg', 48.57, 7.75],
  ['Brest', 48.39, -4.49], ['Rouen', 49.44, 1.1], ['Limoges', 45.83, 1.26], ['Dijon', 47.32, 5.04],
  ['Ajaccio', 41.93, 8.74], ['Montpellier', 43.61, 3.88], ['Clermont-Ferrand', 45.78, 3.08], ['Tours', 47.39, 0.69],
  ['Reims', 49.26, 4.03], ['Grenoble', 45.19, 5.72],
  ['Berlin', 52.52, 13.4, 1], ['Hamburg', 53.55, 9.99], ['Munich', 48.14, 11.58], ['Cologne', 50.94, 6.96],
  ['Frankfurt', 50.11, 8.68], ['Stuttgart', 48.78, 9.18], ['Dresden', 51.05, 13.74], ['Hanover', 52.37, 9.73],
  ['Leipzig', 51.34, 12.37], ['Nuremberg', 49.45, 11.08], ['Rostock', 54.09, 12.1], ['Kiel', 54.32, 10.13],
  ['Madrid', 40.42, -3.7, 1], ['Barcelona', 41.39, 2.17], ['Valencia', 39.47, -0.38], ['Seville', 37.39, -5.98],
  ['Bilbao', 43.26, -2.93], ['Zaragoza', 41.65, -0.89], ['Málaga', 36.72, -4.42], ['A Coruña', 43.36, -8.41],
  ['Valladolid', 41.65, -4.72], ['Palma', 39.57, 2.65], ['Murcia', 37.99, -1.13], ['Badajoz', 38.88, -6.97],
  ['Oviedo', 43.36, -5.85], ['Albacete', 38.99, -1.86],
  ['Lisbon', 38.72, -9.14, 1], ['Porto', 41.15, -8.61], ['Faro', 37.02, -7.93], ['Coimbra', 40.2, -8.42],
  ['Rome', 41.9, 12.5, 1], ['Milan', 45.46, 9.19], ['Naples', 40.85, 14.27], ['Turin', 45.07, 7.69],
  ['Palermo', 38.12, 13.36], ['Venice', 45.44, 12.32], ['Florence', 43.77, 11.26], ['Bari', 41.12, 16.87],
  ['Cagliari', 39.22, 9.12], ['Bologna', 44.49, 11.34], ['Catania', 37.5, 15.09], ['Reggio Calabria', 38.11, 15.65],
  ['Pescara', 42.46, 14.21], ['Sassari', 40.73, 8.56],
  ['Amsterdam', 52.37, 4.9, 1], ['Rotterdam', 51.92, 4.48], ['Groningen', 53.22, 6.57],
  ['Brussels', 50.85, 4.35, 1], ['Antwerp', 51.22, 4.4], ['Liège', 50.63, 5.57], ['Luxembourg', 49.61, 6.13, 1],
  ['Bern', 46.95, 7.45, 1], ['Zürich', 47.37, 8.54], ['Geneva', 46.2, 6.14],
  ['Vienna', 48.21, 16.37, 1], ['Innsbruck', 47.27, 11.4], ['Graz', 47.07, 15.44], ['Salzburg', 47.8, 13.04],
  ['Copenhagen', 55.68, 12.57, 1], ['Aarhus', 56.16, 10.2], ['Tórshavn', 62.01, -6.77],
  ['Oslo', 59.91, 10.75, 1], ['Bergen', 60.39, 5.32], ['Trondheim', 63.43, 10.39], ['Tromsø', 69.65, 18.96],
  ['Bodø', 67.28, 14.4], ['Stavanger', 58.97, 5.73], ['Kristiansand', 58.15, 8.0], ['Hammerfest', 70.66, 23.68],
  ['Stockholm', 59.33, 18.07, 1], ['Gothenburg', 57.71, 11.97], ['Malmö', 55.6, 13.0], ['Umeå', 63.83, 20.26],
  ['Kiruna', 67.86, 20.23], ['Luleå', 65.58, 22.15], ['Östersund', 63.18, 14.64], ['Sundsvall', 62.39, 17.31],
  ['Örebro', 59.27, 15.21], ['Visby', 57.64, 18.29], ['Kalmar', 56.66, 16.36],
  ['Helsinki', 60.17, 24.94, 1], ['Tampere', 61.5, 23.79], ['Oulu', 65.01, 25.47], ['Rovaniemi', 66.5, 25.73],
  ['Turku', 60.45, 22.27], ['Kuopio', 62.89, 27.68], ['Inari', 68.9, 27.03], ['Vaasa', 63.1, 21.6],
  ['Reykjavík', 64.15, -21.94, 1], ['Akureyri', 65.68, -18.09],
  ['Tallinn', 59.44, 24.75, 1], ['Tartu', 58.38, 26.72], ['Riga', 56.95, 24.11, 1], ['Daugavpils', 55.87, 26.54],
  ['Vilnius', 54.69, 25.28, 1], ['Kaunas', 54.9, 23.9], ['Klaipėda', 55.71, 21.13],
  ['Warsaw', 52.23, 21.01, 1], ['Kraków', 50.06, 19.94], ['Gdańsk', 54.35, 18.65], ['Poznań', 52.41, 16.93],
  ['Wrocław', 51.11, 17.04], ['Łódź', 51.76, 19.46], ['Lublin', 51.25, 22.57], ['Szczecin', 53.43, 14.55],
  ['Białystok', 53.13, 23.16], ['Rzeszów', 50.04, 22.0], ['Olsztyn', 53.78, 20.48],
  ['Prague', 50.08, 14.44, 1], ['Brno', 49.2, 16.61], ['Ostrava', 49.82, 18.26],
  ['Bratislava', 48.15, 17.11, 1], ['Košice', 48.72, 21.26], ['Banská Bystrica', 48.74, 19.15],
  ['Budapest', 47.5, 19.04, 1], ['Debrecen', 47.53, 21.63], ['Szeged', 46.25, 20.15], ['Pécs', 46.07, 18.23],
  ['Győr', 47.69, 17.63],
  ['Ljubljana', 46.06, 14.51, 1], ['Zagreb', 45.81, 15.98, 1], ['Split', 43.51, 16.44], ['Rijeka', 45.33, 14.44],
  ['Osijek', 45.55, 18.69], ['Sarajevo', 43.86, 18.41, 1], ['Banja Luka', 44.77, 17.19], ['Mostar', 43.34, 17.81],
  ['Belgrade', 44.79, 20.45, 1], ['Novi Sad', 45.27, 19.83], ['Niš', 43.32, 21.9],
  ['Podgorica', 42.44, 19.26, 1], ['Pristina', 42.66, 21.17, 1], ['Skopje', 42.0, 21.43, 1], ['Tirana', 41.33, 19.82, 1],
  ['Vlorë', 40.47, 19.49],
  ['Athens', 37.98, 23.73, 1], ['Thessaloniki', 40.64, 22.94], ['Patras', 38.25, 21.73], ['Heraklion', 35.34, 25.13],
  ['Ioannina', 39.67, 20.85], ['Larissa', 39.64, 22.42], ['Alexandroupoli', 40.85, 25.87], ['Rhodes', 36.43, 28.22],
  ['Sofia', 42.7, 23.32, 1], ['Varna', 43.21, 27.91], ['Plovdiv', 42.14, 24.75], ['Burgas', 42.5, 27.47],
  ['Pleven', 43.42, 24.61],
  ['Bucharest', 44.43, 26.1, 1], ['Cluj-Napoca', 46.77, 23.59], ['Timișoara', 45.75, 21.23], ['Iași', 47.16, 27.59],
  ['Constanța', 44.18, 28.63], ['Craiova', 44.32, 23.8], ['Brașov', 45.66, 25.61], ['Oradea', 47.07, 21.92],
  ['Suceava', 47.65, 26.26], ['Galați', 45.44, 28.05],
  ['Chișinău', 47.01, 28.86, 1], ['Bălți', 47.76, 27.93],
  ['Kyiv', 50.45, 30.52, 1], ['Kharkiv', 49.99, 36.23], ['Odesa', 46.48, 30.72], ['Dnipro', 48.46, 35.05],
  ['Lviv', 49.84, 24.03], ['Donetsk', 48.0, 37.8], ['Zaporizhzhia', 47.84, 35.14], ['Simferopol', 44.95, 34.1],
  ['Kherson', 46.64, 32.62], ['Mykolaiv', 46.98, 32.0], ['Vinnytsia', 49.23, 28.47], ['Poltava', 49.59, 34.55],
  ['Chernihiv', 51.5, 31.29], ['Sumy', 50.91, 34.8], ['Rivne', 50.62, 26.25], ['Zhytomyr', 50.25, 28.66],
  ['Luhansk', 48.57, 39.31], ['Uzhhorod', 48.62, 22.29], ['Kropyvnytskyi', 48.51, 32.26], ['Khmelnytskyi', 49.42, 26.99],
  ['Cherkasy', 49.44, 32.06], ['Ternopil', 49.55, 25.59], ['Kryvyi Rih', 47.91, 33.39],
  ['Minsk', 53.9, 27.56, 1], ['Brest', 52.1, 23.69], ['Gomel', 52.44, 30.98], ['Vitebsk', 55.19, 30.2],
  ['Grodno', 53.68, 23.83], ['Mogilev', 53.9, 30.33], ['Pinsk', 52.11, 26.1],
  ['Moscow', 55.76, 37.62, 1], ['Saint Petersburg', 59.94, 30.31], ['Kaliningrad', 54.71, 20.51],
  ['Murmansk', 68.97, 33.09], ['Arkhangelsk', 64.54, 40.54], ['Petrozavodsk', 61.79, 34.39],
  ['Nizhny Novgorod', 56.33, 44.0], ['Kazan', 55.79, 49.12], ['Voronezh', 51.67, 39.18], ['Rostov-on-Don', 47.24, 39.71],
  ['Volgograd', 48.71, 44.51], ['Krasnodar', 45.04, 38.98], ['Smolensk', 54.78, 32.05], ['Pskov', 57.82, 28.33],
  ['Vologda', 59.22, 39.89], ['Yaroslavl', 57.63, 39.87], ['Kursk', 51.73, 36.19], ['Bryansk', 53.24, 34.36],
  ['Saratov', 51.53, 46.03], ['Penza', 53.2, 45.0], ['Tver', 56.86, 35.9], ['Kirov', 58.6, 49.66],
  ['Syktyvkar', 61.67, 50.84], ['Stavropol', 45.04, 41.97], ['Makhachkala', 42.98, 47.5], ['Astrakhan', 46.35, 48.04],
  ['Ryazan', 54.63, 39.74], ['Tula', 54.19, 37.62], ['Kotlas', 61.25, 46.65], ['Naryan-Mar', 67.64, 53.0],
  ['Velikiy Novgorod', 58.52, 31.27], ['Belgorod', 50.6, 36.59], ['Kostroma', 57.77, 40.93], ['Mezen', 65.85, 44.24],
  ['Elista', 46.31, 44.26], ['Lipetsk', 52.61, 39.6], ['Tambov', 52.72, 41.45], ['Ulyanovsk', 54.32, 48.4],
  ['Kandalaksha', 67.15, 32.41], ['Kem', 64.95, 34.58], ['Ukhta', 63.56, 53.68], ['Vorkuta', 67.5, 64.0],
  ['Ankara', 39.93, 32.86, 1], ['Istanbul', 41.01, 28.98], ['Izmir', 38.42, 27.14], ['Antalya', 36.9, 30.7],
  ['Trabzon', 41.0, 39.72], ['Erzurum', 39.9, 41.27], ['Konya', 37.87, 32.48], ['Adana', 37.0, 35.32],
  ['Diyarbakır', 37.91, 40.24], ['Samsun', 41.29, 36.33], ['Van', 38.49, 43.38], ['Kayseri', 38.73, 35.48],
  ['Sivas', 39.75, 37.02], ['Bursa', 40.19, 29.06], ['Edirne', 41.68, 26.56], ['Gaziantep', 37.07, 37.38],
  ['Malatya', 38.36, 38.31], ['Eskişehir', 39.78, 30.52], ['Denizli', 37.78, 29.09], ['Kastamonu', 41.38, 33.78],
  ['Tbilisi', 41.72, 44.79, 1], ['Batumi', 41.64, 41.63], ['Kutaisi', 42.27, 42.7],
  ['Yerevan', 40.18, 44.51, 1], ['Gyumri', 40.79, 43.85], ['Baku', 40.41, 49.87, 1], ['Ganja', 40.68, 46.36],
  ['Nakhchivan', 39.21, 45.41],
  ['Nicosia', 35.17, 33.36, 1], ['Valletta', 35.9, 14.51, 1],
];

// extra hand-placed province seeds (lon, lat)
const FORCED = { UKR: [[34.1, 45.2]], RUS: [[20.5, 54.7]] };
// Natural Earth draws Crimea as Russian (de facto); the game uses de jure borders
// and the 'present day' scenario re-applies the occupation.
const TRANSFER = [{ from: 'RUS', to: 'UKR', at: [34.1, 44.95] }];

const RAD = Math.PI / 180;
const KM_LAT = 111.32;
const proj = ([x, y]) => [x * Math.cos(50 * RAD), y]; // mild scaling for Voronoi
const unproj = ([x, y]) => [x / Math.cos(50 * RAD), y];

function ringArea(r) { // km^2, sinusoidal (equal-area) projection
  let a = 0;
  for (let i = 0, n = r.length; i < n; i++) {
    const [x1, y1] = r[i], [x2, y2] = r[(i + 1) % n];
    a += x1 * Math.cos(y1 * RAD) * y2 - x2 * Math.cos(y2 * RAD) * y1;
  }
  return Math.abs(a / 2) * KM_LAT * KM_LAT;
}
const polyArea = (p) => ringArea(p[0]) - p.slice(1).reduce((s, h) => s + ringArea(h), 0);
const mpArea = (mp) => mp.reduce((s, p) => s + polyArea(p), 0);

function pointInRing(pt, r) {
  let inside = false;
  for (let i = 0, j = r.length - 1; i < r.length; j = i++) {
    const [xi, yi] = r[i], [xj, yj] = r[j];
    if ((yi > pt[1]) !== (yj > pt[1]) && pt[0] < ((xj - xi) * (pt[1] - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
const pointInPoly = (pt, p) => pointInRing(pt, p[0]) && !p.slice(1).some((h) => pointInRing(pt, h));
const pointInMP = (pt, mp) => mp.some((p) => pointInPoly(pt, p));

function distKm(a, b) {
  const dx = (a[0] - b[0]) * Math.cos(((a[1] + b[1]) / 2) * RAD) * KM_LAT;
  const dy = (a[1] - b[1]) * KM_LAT;
  return Math.hypot(dx, dy);
}

let seed = 1337;
const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);

function samplePoints(poly, n) {
  const xs = poly[0].map((c) => c[0]), ys = poly[0].map((c) => c[1]);
  const [x0, x1, y0, y1] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
  const pts = [];
  let guard = 0;
  while (pts.length < n && guard++ < n * 400) {
    const p = [x0 + rnd() * (x1 - x0), y0 + rnd() * (y1 - y0)];
    if (pointInPoly(p, poly)) pts.push(p);
  }
  return pts;
}

function kmeans(points, k) {
  let centers = points.slice(0, k).map((p) => proj(p));
  const P = points.map(proj);
  for (let it = 0; it < 25; it++) {
    const sums = centers.map(() => [0, 0, 0]);
    for (const p of P) {
      let best = 0, bd = Infinity;
      centers.forEach((c, i) => { const d = (c[0] - p[0]) ** 2 + (c[1] - p[1]) ** 2; if (d < bd) { bd = d; best = i; } });
      sums[best][0] += p[0]; sums[best][1] += p[1]; sums[best][2]++;
    }
    centers = centers.map((c, i) => (sums[i][2] ? [sums[i][0] / sums[i][2], sums[i][1] / sums[i][2]] : c));
  }
  // snap each center to the nearest sample (guarantees it lies on land)
  return centers.map((c) => {
    let best = P[0], bd = Infinity;
    for (const p of P) { const d = (c[0] - p[0]) ** 2 + (c[1] - p[1]) ** 2; if (d < bd) { bd = d; best = p; } }
    return unproj(best);
  });
}

// ---- 1. simplify topology (keeps shared borders identical) and extract countries
const pre = ts.presimplify(topo);
const simp = ts.simplify(pre, ts.quantile(pre, 0.45));
const geoms = simp.objects.countries.geometries;
const groups = {};
for (const g of geoms) {
  let key = COUNTRIES[g.properties.name];
  if (key === undefined || key === null) continue;
  const owner = typeof key === 'string' ? key : g.properties.name;
  (groups[owner] = groups[owner] || []).push(g);
}
const bboxPoly = [[[BBOX[0], BBOX[1]], [BBOX[2], BBOX[1]], [BBOX[2], BBOX[3]], [BBOX[0], BBOX[3]], [BBOX[0], BBOX[1]]]];

const countries = [];
for (const [name, gs] of Object.entries(groups)) {
  const [code, display, power] = COUNTRIES[name];
  const merged = tc.merge(simp, gs);
  let mp = merged.type === 'Polygon' ? [merged.coordinates] : merged.coordinates;
  mp = mp.map((poly) => poly.map((r) => r.map(([x, y]) => [x < -100 ? x + 360 : x, y]))); // antimeridian
  mp = pc.intersection(mp, bboxPoly);
  mp = mp.filter((p) => polyArea(p) > 40); // drop specks
  if (!mp.length) continue;
  countries.push({ code, name: display, power, mp, area: mpArea(mp) });
}

for (const t of TRANSFER) {
  const a = countries.find((c) => c.code === t.from), b = countries.find((c) => c.code === t.to);
  const part = a.mp.find((poly) => pointInPoly(t.at, poly));
  if (!part) continue;
  a.mp = a.mp.filter((poly) => poly !== part); b.mp.push(part);
  a.area = mpArea(a.mp); b.area = mpArea(b.mp);
}

// ---- 2. provinces
const provinces = [];
for (const c of countries) {
  const total = Math.min(MAX_PROVINCES, Math.max(c.area > 20000 ? 2 : 1, Math.round(c.area / KM_PER_PROVINCE)));
  const parts = c.mp.map((p) => ({ p, a: polyArea(p) })).sort((a, b) => b.a - a.a);
  const ks = parts.map((part, i) => {
    if (i === 0) return 0;
    const k = Math.round((part.a / c.area) * total);
    return k === 0 && part.a > 3500 ? 1 : k;
  });
  ks[0] = Math.max(1, total - ks.reduce((a, b) => a + b, 0));
  const mine = [];
  const pb = [BBOX[0] - 10, BBOX[1] - 10, BBOX[2] + 10, BBOX[3] + 10].map((v, i) => (i % 2 === 0 ? proj([v, 0])[0] : v));
  parts.forEach((part, i) => {
    if (!ks[i]) return;
    const forced = (FORCED[c.code] || []).filter((f) => pointInPoly(f, part.p));
    const k = Math.max(0, ks[i] - forced.length);
    const pts = samplePoints(part.p, Math.max(300, k * 120));
    const seeds = (k ? kmeans(pts, k) : []).concat(forced);
    if (seeds.length === 1) { mine.push({ country: c.code, mp: [part.p], seed: seeds[0] }); return; }
    const vor = Delaunay.from(seeds.map(proj)).voronoi(pb);
    seeds.forEach((sd, j) => {
      const cp = vor.cellPolygon(j);
      if (!cp) return;
      const inter = pc.intersection([part.p], [cp.map(unproj)]).filter((q) => polyArea(q) > 15);
      if (inter.length) mine.push({ country: c.code, mp: inter, seed: sd });
    });
  });
  // small unseeded islands join the nearest province of the same country
  parts.forEach((part, i) => {
    if (ks[i]) return;
    const v = part.p[0][0];
    const best = mine.reduce((b, q) => (distKm(q.seed, v) < distKm(b.seed, v) ? q : b));
    best.mp = best.mp.concat([part.p]);
  });
  provinces.push(...mine);
}

// ---- 3. names, capitals
const usedNames = new Set();
const dirName = (p, c) => {
  const cc = countries.find((x) => x.code === p.country);
  const xs = [], ys = [];
  cc.mp.forEach((poly) => poly[0].forEach(([x, y]) => { xs.push(x); ys.push(y); }));
  const mx = (Math.min(...xs) + Math.max(...xs)) / 2, my = (Math.min(...ys) + Math.max(...ys)) / 2;
  const dx = (p.seed[0] - mx) * Math.cos(my * RAD), dy = p.seed[1] - my;
  if (Math.hypot(dx, dy) < 0.8) return 'Central ' + cc.name;
  const dirs = ['East', 'North-East', 'North', 'North-West', 'West', 'South-West', 'South', 'South-East'];
  const a = (Math.atan2(dy, dx) * 180) / Math.PI;
  return dirs[(Math.round(a / 45) + 8) % 8] + ' ' + cc.name;
};
function uniq(base) {
  let name = base, n = 0;
  while (usedNames.has(name)) name = base + ' ' + ['II', 'III', 'IV', 'V', 'VI', 'VII'][n++];
  usedNames.add(name);
  return name;
}
for (const p of provinces) {
  const inside = CITIES.filter(([, la, lo]) => pointInMP([lo, la], p.mp));
  inside.sort((a, b) => (b[3] || 0) - (a[3] || 0));
  let city = inside[0];
  if (!city) {
    // nearest unused city within 120 km
    let best = null, bd = 120;
    for (const ct of CITIES) {
      const d = distKm([ct[2], ct[1]], p.seed);
      if (d < bd && !usedNames.has(ct[0])) { bd = d; best = ct; }
    }
    city = best && inside.length === 0 ? best : null;
  }
  p.name = uniq(city && !usedNames.has(city[0]) ? city[0] : dirName(p));
  p.capital = !!(city && city[3] && inside[0] === city);
  if (city && inside[0] === city) p.label = [city[2], city[1]];
  else p.label = p.seed;
  p.area = mpArea(p.mp);
}
// capitals: the province containing (or nearest to) each capital city
provinces.forEach((p) => { p.capital = false; });
for (const ct of CITIES.filter((x) => x[3])) {
  const pt = [ct[2], ct[1]];
  let prov = provinces.find((p) => pointInMP(pt, p.mp));
  if (!prov) prov = provinces.reduce((b, p) => (distKm(p.seed, pt) < distKm(b.seed, pt) ? p : b));
  if (provinces.some((p) => p.country === prov.country && p.capital)) continue;
  prov.capital = true;
  if (prov.name !== ct[0]) {
    const other = provinces.find((p) => p.name === ct[0]);
    if (other) other.name = uniq(dirName(other));
    usedNames.delete(prov.name);
    prov.name = ct[0];
  }
  prov.label = pt;
}
for (const c of countries) {
  const ps = provinces.filter((p) => p.country === c.code);
  if (!ps.some((p) => p.capital)) ps.sort((a, b) => b.area - a.area)[0].capital = true;
}

// ---- 4. adjacency
const round = (v) => Math.round(v * 1000) / 1000;
provinces.forEach((p, i) => {
  p.id = i;
  p.mp = p.mp.map((poly) => poly.map((r) => r.map(([x, y]) => [round(x), round(y)])));
  p.verts = [];
  p.mp.forEach((poly) => poly.forEach((r) => r.forEach((v) => p.verts.push(v))));
  const xs = p.verts.map((v) => v[0]), ys = p.verts.map((v) => v[1]);
  p.bb = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
});
const CELL = 0.5;
const grid = new Map();
provinces.forEach((p) => p.verts.forEach((v, vi) => {
  const k = Math.floor(v[0] / CELL) + ':' + Math.floor(v[1] / CELL);
  if (!grid.has(k)) grid.set(k, []);
  grid.get(k).push([p.id, v]);
}));
function near(v, km) {
  const out = [];
  const gx = Math.floor(v[0] / CELL), gy = Math.floor(v[1] / CELL);
  for (let dx = -2; dx <= 2; dx++) for (let dy = -1; dy <= 1; dy++) {
    const arr = grid.get(gx + dx + ':' + (gy + dy));
    if (arr) for (const [id, w] of arr) if (distKm(v, w) <= km) out.push([id, w]);
  }
  return out;
}
const land = provinces.map(() => new Set());
const strait = provinces.map(() => new Set());
const coastal = provinces.map(() => []);
for (const p of provinces) {
  for (const v of p.verts) {
    let shared = false;
    for (const [id, w] of near(v, 32)) {
      if (id === p.id) continue;
      const d = distKm(v, w);
      if (d < 1.5) { land[p.id].add(id); shared = true; } else strait[p.id].add(id);
    }
    if (!shared) coastal[p.id].push(v);
  }
}
const links = provinces.map(() => new Map()); // id -> type (0 land, 1 sea)
provinces.forEach((p) => {
  land[p.id].forEach((q) => { links[p.id].set(q, 0); links[q].set(p.id, 0); });
});
provinces.forEach((p) => {
  strait[p.id].forEach((q) => { if (!links[p.id].has(q)) { links[p.id].set(q, 1); links[q].set(p.id, 1); } });
});
// longer sea lanes between coasts (max 4 per province), only if the lane crosses water
const onLand = (pt) => provinces.some((q) => pt[0] >= q.bb[0] && pt[0] <= q.bb[2] && pt[1] >= q.bb[1] && pt[1] <= q.bb[3] && pointInMP(pt, q.mp));
const sampled = coastal.map((cv) => cv.filter((_, i) => i % 3 === 0));
for (const p of provinces) {
  if (!sampled[p.id].length) continue;
  const cands = [];
  for (const q of provinces) {
    if (q.id === p.id || links[p.id].has(q.id) || !sampled[q.id].length) continue;
    if (q.bb[0] > p.bb[2] + 5 || q.bb[2] < p.bb[0] - 5 || q.bb[1] > p.bb[3] + 3 || q.bb[3] < p.bb[1] - 3) continue;
    let bd = Infinity, pair = null;
    for (const a of sampled[p.id]) for (const b of sampled[q.id]) {
      const d = distKm(a, b);
      if (d < bd) { bd = d; pair = [a, b]; }
    }
    if (bd > 320) continue;
    let wet = true;
    for (let t = 0.15; t <= 0.851; t += 0.1) {
      const pt = [pair[0][0] + (pair[1][0] - pair[0][0]) * t, pair[0][1] + (pair[1][1] - pair[0][1]) * t];
      if (onLand(pt)) { wet = false; break; }
    }
    if (wet) cands.push([bd, q.id]);
  }
  cands.sort((a, b) => a[0] - b[0]).slice(0, 4).forEach(([, q]) => { links[p.id].set(q, 1); links[q].set(p.id, 1); });
}

// connect islands that are still cut off (e.g. Iceland) to the nearest other coast
for (;;) {
  const comp = new Array(provinces.length).fill(-1);
  let nc = 0;
  for (const p of provinces) {
    if (comp[p.id] >= 0) continue;
    const st = [p.id]; comp[p.id] = nc;
    while (st.length) { const u = st.pop(); for (const v of links[u].keys()) if (comp[v] < 0) { comp[v] = nc; st.push(v); } }
    nc++;
  }
  if (nc === 1) break;
  const sizes = new Array(nc).fill(0); comp.forEach((c) => sizes[c]++);
  const small = sizes.indexOf(Math.min(...sizes));
  let best = [Infinity];
  for (const p of provinces) if (comp[p.id] === small) for (const q of provinces) if (comp[q.id] !== small) {
    for (const a of sampled[p.id]) for (const b of sampled[q.id]) { const d = distKm(a, b); if (d < best[0]) best = [d, p.id, q.id]; }
  }
  links[best[1]].set(best[2], 1); links[best[2]].set(best[1], 1);
  console.log('linked island', provinces[best[1]].name, '<->', provinces[best[2]].name, Math.round(best[0]), 'km');
}

// ---- 5. output
const out = {
  countries: countries.map((c) => ({ code: c.code, name: c.name, power: c.power })),
  provinces: provinces.map((p) => ({
    id: p.id, c: p.country, n: p.name, cap: p.capital ? 1 : 0,
    a: Math.round(p.area), l: [round(p.label[0]), round(p.label[1])],
    coast: coastal[p.id].length > 0 ? 1 : 0,
    adj: [...links[p.id].entries()].map(([q, t]) => (t ? -(q + 1) : q + 1)),
    g: p.mp,
  })),
};
const target = path.join(__dirname, '..', 'www', 'data', 'provinces.js');
fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, 'window.IA_DATA=' + JSON.stringify(out) + ';\n');
const isolated = out.provinces.filter((p) => !p.adj.length).map((p) => p.n);
console.log(`countries ${out.countries.length}, provinces ${out.provinces.length}, size ${(fs.statSync(target).size / 1024).toFixed(0)} KB`);
console.log('isolated:', isolated.join(', ') || 'none');
console.log('capitals:', out.provinces.filter((p) => p.cap).map((p) => p.c + ':' + p.n).join(', '));
