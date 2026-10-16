/* Iron Atlas — Conquest of Europe
 * Territory is a raster grid laid over the satellite map. Players draw loops with their finger:
 * when founding a nation the land inside becomes theirs, in war it becomes an offensive that
 * pushes the front line across the drawn area. */
(function () {
  'use strict';

  // ------------------------------------------------------------------ static data
  const D = window.IA_DATA;
  const W = D.w, H = D.h, BB = D.bbox;
  const RAD = Math.PI / 180;
  const mercY = (lat) => Math.log(Math.tan(Math.PI / 4 + (lat * RAD) / 2));
  const MT = mercY(BB[3]), MB = mercY(BB[1]);
  const latOfY = (y) => (2 * Math.atan(Math.exp(MT - (y / H) * (MT - MB))) - Math.PI / 2) / RAD;
  const lonOfX = (x) => BB[0] + (x / W) * (BB[2] - BB[0]);
  const xOfLon = (lon) => ((lon - BB[0]) / (BB[2] - BB[0])) * W;
  const yOfLat = (lat) => ((MT - mercY(lat)) / (MT - MB)) * H;

  // province raster: value = province id + 1, 0 = sea
  const PROV = new Uint16Array(W * H);
  (function decode() {
    const bin = atob(D.rle);
    const u8 = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    const runs = new Uint16Array(u8.buffer);
    let o = 0;
    for (let i = 0; i < runs.length; i += 2) { PROV.fill(runs[i], o, o + runs[i + 1]); o += runs[i + 1]; }
  })();

  const P = D.provinces.map((p, id) => ({
    id, c: p.c, name: p.n, cap: !!p.cap, area: p.a, cells: p.k, lon: p.l[0], lat: p.l[1],
    val: Math.round((Math.min(3.5, 0.8 + p.a / 45000) + (p.cap ? 2 : 0)) * 10) / 10,
  }));
  // per-cell weights: economic value and area in km²
  const CELL_VAL = P.map((p) => (p.cells ? p.val / p.cells : 0));
  const CELL_KM2 = P.map((p) => (p.cells ? p.area / p.cells : 0));
  let LAND = 0;
  for (let i = 0; i < PROV.length; i++) if (PROV[i]) LAND++;

  const ISO2 = {
    ALB: 'AL', ARM: 'AM', AUT: 'AT', AZE: 'AZ', BLR: 'BY', BEL: 'BE', BIH: 'BA', BGR: 'BG', HRV: 'HR', CYP: 'CY', CZE: 'CZ',
    DNK: 'DK', EST: 'EE', FIN: 'FI', FRA: 'FR', GEO: 'GE', DEU: 'DE', GRC: 'GR', HUN: 'HU', ISL: 'IS', IRL: 'IE', ITA: 'IT',
    XKX: 'XK', LVA: 'LV', LTU: 'LT', LUX: 'LU', MKD: 'MK', MDA: 'MD', MNE: 'ME', NLD: 'NL', NOR: 'NO', POL: 'PL', PRT: 'PT',
    ROU: 'RO', RUS: 'RU', SRB: 'RS', SVK: 'SK', SVN: 'SI', ESP: 'ES', SWE: 'SE', CHE: 'CH', TUR: 'TR', UKR: 'UA', GBR: 'GB', MLT: 'MT',
  };
  const BASE_COLORS = {
    RUS: '#d23a2a', UKR: '#2f6fe0', DEU: '#5b5f66', FRA: '#3248b8', GBR: '#c2185b', ITA: '#2e9b5f', ESP: '#e8b20e', POL: '#e0607e',
    TUR: '#e06a10', SWE: '#1e9be8', NOR: '#a83a5a', FIN: '#e8e8f0', BLR: '#7fae3a', ROU: '#f0d040', HUN: '#5aa05a', AUT: '#f06060',
    GRC: '#4ec3ff', PRT: '#1f8f6a', NLD: '#ff8c1a', BEL: '#b8862f', CHE: '#ff3b3b', CZE: '#4a7bd0', SVK: '#7a62d0', DNK: '#b5283c',
    IRL: '#3cb043', ISL: '#5d7fd8', SRB: '#a0442e', BGR: '#2f9f86', HRV: '#3b5fc8', BIH: '#d8c040', SVN: '#5cb8c8', MDA: '#c7a332',
    LTU: '#c6b129', LVA: '#8e2a3a', EST: '#3a86c8', GEO: '#e05050', ARM: '#d08030', AZE: '#25a4c8', ALB: '#a4282a', MKD: '#e8a020',
    MNE: '#b08060', XKX: '#3060a0', CYP: '#c88a30', LUX: '#6ac0e8', MLT: '#d0d0d0',
  };
  const flagOf = (code) => (ISO2[code] ? String.fromCodePoint(...[...ISO2[code]].map((c) => 0x1f1a5 + c.charCodeAt(0))) : '🏴');

  // ------------------------------------------------------------------ tuning
  const DAY_MS = 1500;
  const RECRUIT_COST = 2; // gold per 1k troops
  const BASE_SPEED = 90; // cells per day at even odds
  const LOCAL_CELLS = 3500; // how much of the defender's land density counts as the local garrison

  // ------------------------------------------------------------------ state
  let S = null;
  let OWN = new Uint8Array(W * H); // nation index per cell (0 = none)
  let OFF = []; // active offensives (runtime only)
  const ui = { mode: 'title', zooming: false, commit: 0.5, draw: false, path: null, info: null, pickIdx: 0, custom: null, effects: [], lastPanel: 0, modalOpen: false };
  const settings = loadSettings();

  function loadSettings() {
    const def = { labels: true, satellite: true, autoRecruit: true };
    try { return Object.assign(def, JSON.parse(localStorage.getItem('ia_settings') || '{}')); } catch (e) { return def; }
  }
  function saveSettings() { try { localStorage.setItem('ia_settings', JSON.stringify(settings)); } catch (e) { /* ignore */ } }

  function newGame(opts) {
    OFF.forEach((o) => o.layer && map.removeLayer(o.layer));
    OFF = [];
    S = { v: 2, day: 0, speed: 1, player: 0, aggr: opts.aggr, scenario: opts.scenario, sandbox: opts.scenario === 'sandbox',
      N: [null], wars: [], truces: [], news: [], over: false, won: false, nextOff: 1 };
    const byCode = {};
    for (const c of D.countries) {
      const n = { idx: S.N.length, code: c.code, name: c.name, color: BASE_COLORS[c.code] || '#888', flag: flagOf(c.code), power: c.power,
        t: 0, gold: 60, alive: true, cells: 0, val: 0, km: 0, start: 0, cap: -1, cx: 0, cy: 0 };
      S.N.push(n); byCode[c.code] = n;
    }
    for (const p of P) {
      const n = byCode[p.c];
      n.t += (3 + p.val * 3.2) * n.power * (p.cap ? 1.5 : 1);
      if (p.cap) n.cap = cellAt(p.lat, p.lon, p.id);
    }
    for (let i = 0; i < PROV.length; i++) {
      const pv = PROV[i];
      if (!pv) { OWN[i] = 0; continue; }
      OWN[i] = byCode[P[pv - 1].c].idx;
    }
    if (opts.scenario === 'present') {
      const occ = new Set(P.filter((p) => ['Simferopol', 'Donetsk', 'Luhansk'].includes(p.name) && p.c === 'UKR').map((p) => p.id + 1));
      for (let i = 0; i < PROV.length; i++) if (occ.has(PROV[i])) OWN[i] = byCode.RUS.idx;
      S.wars.push({ a: byCode.RUS.idx, b: byCode.UKR.idx, start: 0, lostA: 0, lostB: 0 });
      byCode.UKR.t *= 1.3;
    }
    recount();
    S.N.forEach((n) => { if (n) { n.start = n.cells; n.t = Math.round(n.t); } });
    paintAll();
  }

  // cell of a lat/lon; falls back to any cell of the given province
  function cellAt(lat, lon, provId) {
    const x = Math.floor(xOfLon(lon)), y = Math.floor(yOfLat(lat));
    if (x >= 0 && y >= 0 && x < W && y < H && (provId == null || PROV[y * W + x] === provId + 1)) return y * W + x;
    let best = -1, bd = Infinity;
    for (let i = 0; i < PROV.length; i++) {
      if (PROV[i] !== provId + 1) continue;
      const d = (i % W - x) ** 2 + (Math.floor(i / W) - y) ** 2;
      if (d < bd) { bd = d; best = i; }
    }
    return best;
  }

  // full recount of cells, value, centroids and borders
  let BORDERS = new Map(); // key a*256+b -> sample of b-owned cells touching a
  function recount() {
    const N = S.N;
    N.forEach((n) => { if (n) { n.cells = 0; n.val = 0; n.km = 0; n.sx = 0; n.sy = 0; } });
    const counts = new Map();
    const samples = new Map();
    for (let i = 0; i < OWN.length; i++) {
      const o = OWN[i];
      if (!o) continue;
      const n = N[o];
      n.cells++; n.val += CELL_VAL[PROV[i] - 1]; n.km += CELL_KM2[PROV[i] - 1];
      const x = i % W, y = (i - x) / W;
      n.sx += x; n.sy += y;
      if (x + 1 < W) border(i, i + 1); if (y + 1 < H) border(i, i + W);
    }
    function border(i, j) {
      const a = OWN[i], b = OWN[j];
      if (!b || a === b) return;
      add(a, b, j); add(b, a, i);
    }
    function add(a, b, cell) {
      const k = a * 256 + b;
      const c = (counts.get(k) || 0) + 1;
      counts.set(k, c);
      let arr = samples.get(k);
      if (!arr) samples.set(k, (arr = []));
      if (arr.length < 48) arr.push(cell);
      else if (Math.random() < 48 / c) arr[(Math.random() * 48) | 0] = cell;
    }
    BORDERS = samples;
    N.forEach((n) => {
      if (!n) return;
      if (n.cells) { n.cx = n.sx / n.cells; n.cy = n.sy / n.cells; }
      if (n.alive && n.cells === 0) n.alive = false;
    });
  }

  // ------------------------------------------------------------------ helpers
  const N = (i) => S.N[i];
  const isPlayer = (i) => S && i === S.player;
  const atWar = (a, b) => a !== b && S.wars.some((w) => (w.a === a && w.b === b) || (w.a === b && w.b === a));
  const warOf = (a, b) => S.wars.find((w) => (w.a === a && w.b === b) || (w.a === b && w.b === a));
  const truceOf = (a, b) => S.truces.find((t) => ((t.a === a && t.b === b) || (t.a === b && t.b === a)) && t.until > S.day);
  const enemiesOf = (i) => S.wars.filter((w) => w.a === i || w.b === i).map((w) => (w.a === i ? w.b : w.a));
  const committed = (i) => OFF.reduce((s, o) => s + (o.a === i ? o.t : 0), 0);
  const strength = (i) => N(i).t + committed(i);
  const armyLimit = (i) => 40 + N(i).val * 8 * N(i).power;
  const neighborsOf = (i) => { const s = new Set(); BORDERS.forEach((_, k) => { if ((k >> 8) === i) s.add(k & 255); }); return s; };
  const kmOf = (c) => CELL_KM2[PROV[c] - 1];
  function fmtT(t) {
    if (t >= 1000) return (t / 1000).toFixed(1) + 'M';
    if (t >= 10) return Math.round(t) + 'k';
    return Math.max(0, Math.round(t * 10) / 10) + 'k';
  }
  function fmtKm(k) { return k >= 10000 ? Math.round(k / 1000) + 'k km²' : Math.round(k).toLocaleString('en') + ' km²'; }
  function dateStr(day) {
    const d = new Date(Date.UTC(2026, 9, 16) + day * 86400000);
    return String(d.getUTCDate()).padStart(2, '0') + '.' + String(d.getUTCMonth() + 1).padStart(2, '0') + '.' + d.getUTCFullYear();
  }
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const $ = (id) => document.getElementById(id);
  const hexRgb = (hex) => { const n = parseInt(hex.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
  const cellLatLng = (c) => [latOfY(Math.floor(c / W) + 0.5), lonOfX((c % W) + 0.5)];

  // ------------------------------------------------------------------ map
  const map = L.map('map', {
    zoomControl: false, minZoom: 3, maxZoom: 10, zoomSnap: 0.25, wheelPxPerZoomLevel: 90,
    maxBounds: [[22, -45], [80, 70]], maxBoundsViscosity: 0.8,
  });
  map.attributionControl.setPrefix(false);
  map.attributionControl.addAttribution('Borders © Natural Earth');
  const satLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
    maxZoom: 18, attribution: 'Imagery © Esri, Maxar, Earthstar Geographics',
  });
  map.createPane('labels');
  map.getPane('labels').style.zIndex = 420;
  map.getPane('labels').style.pointerEvents = 'none';
  const labelLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}', {
    maxZoom: 18, attribution: 'Labels © Esri, HERE, Garmin', pane: 'labels', opacity: 0.85,
  });
  if (settings.satellite) satLayer.addTo(map);
  if (settings.labels) labelLayer.addTo(map);
  map.fitBounds([[40, -8], [62, 35]]);
  map.on('zoomstart', () => { ui.zooming = true; });
  map.on('zoomend', () => { ui.zooming = false; });

  // territory canvas as an image overlay (the grid is in Web Mercator rows, so it lines up exactly)
  const terr = document.createElement('canvas');
  terr.width = W; terr.height = H;
  terr.className = 'terr';
  const tctx = terr.getContext('2d');
  const img = tctx.createImageData(W, H);
  const PIX = new Uint32Array(img.data.buffer);
  const CanvasOverlay = L.ImageOverlay.extend({
    _initImage() {
      const el = (this._image = terr);
      L.DomUtil.addClass(el, 'leaflet-image-layer');
      if (this._zoomAnimated) L.DomUtil.addClass(el, 'leaflet-zoom-animated');
      el.onselectstart = L.Util.falseFn;
      el.onmousemove = L.Util.falseFn;
    },
  });
  new CanvasOverlay('', [[BB[1], BB[0]], [BB[3], BB[2]]], { opacity: 1, interactive: false }).addTo(map);

  // colours as packed little-endian RGBA
  let FILL = [], EDGE = [];
  function buildPalette() {
    FILL = [0]; EDGE = [0];
    for (let i = 1; i < S.N.length; i++) {
      const n = S.N[i];
      const [r, g, b] = hexRgb(n.color);
      const focus = ui.mode === 'pick' && ui.pickIdx === i;
      const dim = ui.mode === 'pick' && ui.pickIdx && !focus;
      const a = focus ? 190 : dim ? 70 : isPlayer(i) ? 135 : 112;
      FILL[i] = ((a << 24) | (b << 16) | (g << 8) | r) >>> 0;
      const ea = focus ? 255 : 225;
      const k = focus ? 1 : 0.55;
      EDGE[i] = ((ea << 24) | (((b * k) | 0) << 16) | (((g * k) | 0) << 8) | ((r * k) | 0)) >>> 0;
    }
  }
  function pixelOf(i) {
    const o = OWN[i];
    if (!o) return 0;
    const x = i % W;
    if ((x > 0 && OWN[i - 1] !== o && PROV[i - 1]) || (x < W - 1 && OWN[i + 1] !== o && PROV[i + 1]) ||
        (i >= W && OWN[i - W] !== o && PROV[i - W]) || (i < W * (H - 1) && OWN[i + W] !== o && PROV[i + W])) return EDGE[o];
    return FILL[o];
  }
  let dirty = null;
  function paintAll() {
    buildPalette();
    for (let i = 0; i < OWN.length; i++) PIX[i] = PROV[i] ? pixelOf(i) : 0;
    tctx.putImageData(img, 0, 0);
    dirty = null;
  }
  function markDirty(i) {
    const x = i % W, y = (i - x) / W;
    PIX[i] = pixelOf(i);
    if (x > 0) PIX[i - 1] = pixelOf(i - 1);
    if (x < W - 1) PIX[i + 1] = pixelOf(i + 1);
    if (y > 0) PIX[i - W] = pixelOf(i - W);
    if (y < H - 1) PIX[i + W] = pixelOf(i + W);
    if (!dirty) dirty = [x, y, x, y];
    else { if (x < dirty[0]) dirty[0] = x; if (y < dirty[1]) dirty[1] = y; if (x > dirty[2]) dirty[2] = x; if (y > dirty[3]) dirty[3] = y; }
  }
  function flush() {
    if (!dirty) return;
    const x0 = Math.max(0, dirty[0] - 1), y0 = Math.max(0, dirty[1] - 1);
    tctx.putImageData(img, 0, 0, x0, y0, Math.min(W, dirty[2] + 2) - x0, Math.min(H, dirty[3] + 2) - y0);
    dirty = null;
  }

  // ------------------------------------------------------------------ ownership changes
  function setOwner(i, a) {
    const old = OWN[i];
    if (old === a) return;
    const v = CELL_VAL[PROV[i] - 1], km = CELL_KM2[PROV[i] - 1];
    if (old) { const o = S.N[old]; o.cells--; o.val -= v; o.km -= km; }
    const n = S.N[a]; n.cells++; n.val += v; n.km += km;
    OWN[i] = a;
    markDirty(i);
  }

  function capitulate(loser, winner) {
    for (let i = 0; i < OWN.length; i++) if (OWN[i] === loser) setOwner(i, winner);
    N(winner).t += N(loser).t * 0.3;
    news(`🏳️ ${N(loser).flag} ${N(loser).name} has capitulated to ${N(winner).flag} ${N(winner).name}!`, 'war');
    eliminate(loser);
  }
  function eliminate(i) {
    const n = N(i);
    if (!n.alive) return;
    n.alive = false; n.t = 0;
    S.wars = S.wars.filter((w) => w.a !== i && w.b !== i);
    OFF.filter((o) => o.a === i).forEach((o) => endOffensive(o, true));
    if (isPlayer(i)) gameOver();
  }
  // checks after territory changed hands
  function afterCaptures(attacker, losers) {
    for (const l of losers) {
      const n = N(l);
      if (!n.alive) continue;
      if (n.cells < 25) {
        if (n.cells) capitulate(l, attacker);
        else { news(`☠️ ${n.flag} ${n.name} has been wiped off the map.`, 'war'); eliminate(l); }
        continue;
      }
      if (S.sandbox) continue;
      if (n.cap >= 0 && OWN[n.cap] !== l) {
        if (!n.capLost) {
          n.capLost = true;
          news(`${N(OWN[n.cap]).flag} ${N(OWN[n.cap]).name} has taken the capital of ${n.flag} ${n.name}!`, 'war');
          n.t *= 0.8;
        }
        if (n.cells < n.start * 0.5) capitulate(l, OWN[n.cap]);
      } else n.capLost = false;
    }
  }

  // ------------------------------------------------------------------ lasso → cells
  // poly: array of [gridX, gridY]; returns land cells inside (even-odd)
  function cellsInPolygon(poly) {
    const out = [];
    let y0 = Infinity, y1 = -Infinity;
    poly.forEach((p) => { y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); });
    for (let r = Math.max(0, Math.floor(y0)); r <= Math.min(H - 1, Math.ceil(y1)); r++) {
      const yc = r + 0.5, xs = [];
      for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        const a = poly[j], b = poly[i];
        if ((a[1] <= yc) !== (b[1] <= yc)) xs.push(a[0] + ((yc - a[1]) / (b[1] - a[1])) * (b[0] - a[0]));
      }
      xs.sort((m, n) => m - n);
      for (let k = 0; k + 1 < xs.length; k += 2) {
        const c0 = Math.max(0, Math.ceil(xs[k] - 0.5)), c1 = Math.min(W - 1, Math.floor(xs[k + 1] - 0.5));
        for (let c = c0; c <= c1; c++) { const i = r * W + c; if (PROV[i]) out.push(i); }
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ offensives
  function launchOffensive(a, cells, latlngs, troops) {
    const target = new Set();
    for (const c of cells) if (OWN[c] !== a && atWar(a, OWN[c])) target.add(c);
    if (!target.size || troops < 0.5) return null;
    N(a).t -= troops;
    const o = { id: S.nextOff++, a, t: troops, t0: troops, target, total: target.size, taken: 0, km: 0, queue: [], latlngs, naval: false, born: S.day };
    seedFrontier(o);
    if (!o.queue.length) {
      // nothing touches our land: amphibious landing at the target cell closest to our capital/centre
      const n = N(a);
      const cx = n.cap >= 0 && OWN[n.cap] === a ? n.cap % W : n.cx, cy = n.cap >= 0 && OWN[n.cap] === a ? Math.floor(n.cap / W) : n.cy;
      let best = -1, bd = Infinity;
      target.forEach((c) => { const d = (c % W - cx) ** 2 + (Math.floor(c / W) - cy) ** 2; if (d < bd) { bd = d; best = c; } });
      o.queue.push(best);
      o.naval = true;
    }
    o.layer = L.polygon(latlngs, { color: N(a).color, weight: isPlayer(a) ? 3 : 2, opacity: 0.95, fill: false, dashArray: isPlayer(a) ? null : '6 6', interactive: false, smoothFactor: 1.5 }).addTo(map);
    OFF.push(o);
    return o;
  }
  function seedFrontier(o) {
    o.queue = [];
    o.target.forEach((c) => {
      if (OWN[c] === o.a) { o.target.delete(c); return; }
      const x = c % W;
      if ((x > 0 && OWN[c - 1] === o.a) || (x < W - 1 && OWN[c + 1] === o.a) || OWN[c - W] === o.a || OWN[c + W] === o.a) o.queue.push(c);
    });
  }
  function endOffensive(o, silent) {
    OFF = OFF.filter((x) => x !== o);
    if (o.layer) map.removeLayer(o.layer);
    if (N(o.a).alive) N(o.a).t += Math.max(0, o.t);
    if (!silent && isPlayer(o.a)) {
      const pct = Math.round((o.taken / o.total) * 100);
      toast(pct >= 99 ? `✅ Offensive complete: ${fmtKm(o.km)} taken.` : `Offensive ended at ${pct}% — troops returned to reserve.`, pct >= 99 ? 'peace' : '');
    }
  }

  function stepOffensive(o) {
    if (!N(o.a).alive) return endOffensive(o, true);
    if (!o.queue.length) { seedFrontier(o); if (!o.queue.length) return endOffensive(o); }
    // who are we mostly fighting right now?
    const probe = o.queue[(Math.random() * o.queue.length) | 0];
    const def = OWN[probe];
    let k;
    if (S.sandbox) k = 1e9;
    else {
      if (!atWar(o.a, def)) { o.queue = o.queue.filter((c) => atWar(o.a, OWN[c])); if (!o.queue.length) return endOffensive(o); return; }
      const dn = N(def);
      const dens = Math.max(0.0006, dn.t / Math.max(1, dn.cells));
      const capBonus = P[PROV[probe] - 1].cap && P[PROV[probe] - 1].c === dn.code ? 1.6 : 1;
      const ratio = o.t / (dens * LOCAL_CELLS * 1.3 * capBonus);
      if (ratio < 0.2) { o.t *= 0.93; if (o.t < 1) endOffensive(o); return; }
      k = Math.round(BASE_SPEED * Math.pow(Math.min(ratio, 4), 0.8) * (0.75 + Math.random() * 0.5) * (o.naval && o.taken < 200 ? 0.4 : 1));
    }
    const losers = new Set();
    let n = 0;
    const lostBy = {};
    while (n < k && o.queue.length) {
      const qi = (Math.random() * o.queue.length) | 0;
      const c = o.queue[qi];
      o.queue[qi] = o.queue[o.queue.length - 1]; o.queue.pop();
      const d = OWN[c];
      if (d === o.a || !o.target.has(c)) continue;
      if (!S.sandbox && !atWar(o.a, d)) continue;
      if (!S.sandbox) {
        const dn = N(d);
        const dens = Math.max(0.0006, dn.t / Math.max(1, dn.cells));
        o.t -= dens * 4;
        dn.t = Math.max(0, dn.t - dens * 2.5);
      }
      setOwner(c, o.a);
      o.target.delete(c);
      o.taken++; n++; o.km += kmOf(c);
      losers.add(d);
      lostBy[d] = (lostBy[d] || 0) + 1;
      const x = c % W;
      if (x > 0 && o.target.has(c - 1)) o.queue.push(c - 1);
      if (x < W - 1 && o.target.has(c + 1)) o.queue.push(c + 1);
      if (o.target.has(c - W)) o.queue.push(c - W);
      if (o.target.has(c + W)) o.queue.push(c + W);
      if (o.t <= 0.3) break;
    }
    for (const d in lostBy) { const w = warOf(o.a, +d); if (w) { if (w.a === +d) w.lostA += lostBy[d]; else w.lostB += lostBy[d]; } }
    afterCaptures(o.a, losers);
    if (!o.target.size || o.t <= 0.3) endOffensive(o);
  }

  // ------------------------------------------------------------------ AI
  function aiOffensive(a, e) {
    const samples = BORDERS.get(a * 256 + e);
    if (!samples || !samples.length) return;
    const n = N(a), en = N(e);
    const avail = n.t * (0.45 + Math.random() * 0.25);
    if (avail < 4) return;
    const c = samples[(Math.random() * samples.length) | 0];
    const x = c % W, y = Math.floor(c / W);
    let dx = en.cx - x, dy = en.cy - y;
    const dl = Math.hypot(dx, dy) || 1; dx /= dl; dy /= dl;
    const r = 14 + Math.random() * 22 + Math.min(30, avail / 20);
    const cx = x + dx * r * 0.7, cy = y + dy * r * 0.7;
    const poly = [];
    const sides = 14;
    for (let s = 0; s < sides; s++) {
      const ang = (s / sides) * Math.PI * 2, rr = r * (0.75 + Math.random() * 0.4);
      poly.push([cx + Math.cos(ang) * rr * 1.3, cy + Math.sin(ang) * rr]);
    }
    const cells = cellsInPolygon(poly);
    launchOffensive(a, cells, poly.map(([gx, gy]) => [latOfY(gy), lonOfX(gx)]), avail);
  }

  function spendGold(i, reserve) {
    const n = N(i);
    if (n.gold < reserve + 10) return;
    const space = armyLimit(i) - strength(i);
    if (space <= 1) return;
    const budget = Math.min((n.gold - reserve) * 0.8, space * RECRUIT_COST);
    n.gold -= budget;
    n.t += budget / RECRUIT_COST;
  }

  function aiTurn(i) {
    const n = N(i);
    if ((S.day + i) % 3 === 0) spendGold(i, 10);
    const enemies = enemiesOf(i);
    if (!enemies.length || (S.day + i) % 2) return;
    const mine = OFF.filter((o) => o.a === i).length;
    const maxOff = 1 + Math.min(3, Math.floor(n.t / 250));
    if (mine >= maxOff) return;
    // attack the weakest bordering enemy, sometimes a random one
    const bordering = enemies.filter((e) => BORDERS.has(i * 256 + e));
    if (!bordering.length) return;
    bordering.sort((x, y) => strength(x) - strength(y));
    const e = Math.random() < 0.7 ? bordering[0] : bordering[(Math.random() * bordering.length) | 0];
    if (n.t > N(e).t * 0.25 * (2 / S.aggr) || Math.random() < 0.15) aiOffensive(i, e);
  }

  function acceptsPeace(i, other) {
    const w = warOf(i, other);
    if (!w) return false;
    const lostMe = w.a === i ? w.lostA : w.lostB, lostThem = w.a === i ? w.lostB : w.lostA;
    const days = S.day - w.start;
    if (days < 45) return false;
    const ratio = strength(i) / Math.max(1, strength(other));
    if (lostMe > lostThem * 1.5 + 300) return true; // losing badly
    if (ratio < 0.5 && lostMe > lostThem) return true;
    if (days > 150 && Math.abs(lostMe - lostThem) < 500 && Math.random() < 0.4) return true; // stalemate
    if (days > 300 && Math.random() < 0.2) return true; // war weariness
    return false;
  }

  function aiDiplomacy() {
    for (let i = 1; i < S.N.length; i++) {
      const n = S.N[i];
      if (!n.alive || isPlayer(i)) continue;
      const enemies = enemiesOf(i);
      for (const e of enemies) {
        const w = warOf(i, e);
        if (S.day - w.start < 30 || Math.random() > 0.25) continue;
        if (isPlayer(e)) { if (acceptsPeace(i, e) && Math.random() < 0.15 && !ui.modalOpen) offerPeaceToPlayer(i); }
        else if (acceptsPeace(i, e) && (acceptsPeace(e, i) || (S.day - w.start > 90 && Math.random() < 0.15))) makePeace(i, e);
      }
      if (enemies.length >= 2 || Math.random() > 0.012 * S.aggr) continue;
      const my = strength(i);
      let best = 0, bestScore = 0;
      for (const o of neighborsOf(i)) {
        if (atWar(i, o) || truceOf(i, o) || !N(o).alive) continue;
        let score = my / Math.max(1, strength(o) * (1 - 0.1 * enemiesOf(o).length));
        if (N(o).cells > LAND * 0.2) score *= 1.6;
        if (isPlayer(o)) score *= 1.1;
        if (score > bestScore) { bestScore = score; best = o; }
      }
      if (best && bestScore > (enemies.length ? 3 : 1.9) / Math.sqrt(S.aggr)) declareWar(i, best);
    }
  }

  function declareWar(a, b, quiet) {
    if (atWar(a, b) || a === b || !N(a).alive || !N(b).alive) return false;
    S.truces = S.truces.filter((t) => !((t.a === a && t.b === b) || (t.a === b && t.b === a)));
    S.wars.push({ a, b, start: S.day, lostA: 0, lostB: 0 });
    if (!quiet) news(`⚔️ ${N(a).flag} ${N(a).name} declared war on ${N(b).flag} ${N(b).name}!`, 'war');
    if (isPlayer(a) || isPlayer(b)) renderPanel();
    return true;
  }
  function makePeace(a, b) {
    if (!warOf(a, b)) return;
    S.wars = S.wars.filter((w) => w !== warOf(a, b));
    S.truces.push({ a, b, until: S.day + 120 });
    OFF.filter((o) => (o.a === a || o.a === b)).forEach((o) => {
      o.target.forEach((c) => { if (OWN[c] === (o.a === a ? b : a)) o.target.delete(c); });
      if (!o.target.size) endOffensive(o, true);
    });
    news(`🕊️ ${N(a).flag} ${N(a).name} and ${N(b).flag} ${N(b).name} signed a peace treaty.`, 'peace');
    if (isPlayer(a) || isPlayer(b)) renderPanel();
  }

  // ------------------------------------------------------------------ daily tick
  function tickDay() {
    S.day++;
    for (let i = 1; i < S.N.length; i++) {
      const n = S.N[i];
      if (!n.alive) continue;
      n.gold += n.val * 0.55;
      if (strength(i) < armyLimit(i) * 0.75) n.t += 0.04 * n.val * n.power;
    }
    OFF.slice().forEach(stepOffensive);
    if (S.day % 4 === 0) recount();
    if (!S.sandbox) {
      for (let i = 1; i < S.N.length; i++) {
        if (!S.N[i].alive) continue;
        if (isPlayer(i)) { if (settings.autoRecruit && S.day % 3 === 0) spendGold(i, 100); }
        else aiTurn(i);
      }
      if (S.day % 3 === 0) aiDiplomacy();
    }
    if (!S.won && N(S.player).cells >= LAND * 0.7) { S.won = true; victory(); }
    if (S.day % 15 === 0) save();
  }

  // ------------------------------------------------------------------ overlay canvas (labels, drawing)
  const fx = $('fx');
  const ctx = fx.getContext('2d');
  let dpr = 1;
  function resize() {
    dpr = Math.min(2, window.devicePixelRatio || 1);
    fx.width = innerWidth * dpr; fx.height = innerHeight * dpr;
    fx.style.width = innerWidth + 'px'; fx.style.height = innerHeight + 'px';
    map.invalidateSize();
  }
  window.addEventListener('resize', resize);

  function roundRect(x, y, w, h, r) {
    ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }
  function pill(x, y, text, color, size) {
    ctx.font = `800 ${size}px system-ui, sans-serif`;
    const w = ctx.measureText(text).width + 12, h = size + 8;
    ctx.fillStyle = 'rgba(8,14,22,0.8)';
    roundRect(x - w / 2, y - h / 2, w, h, h / 2); ctx.fill();
    ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.stroke();
    ctx.fillStyle = '#fff'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(text, x, y + 0.5);
  }
  const gridToPt = (gx, gy) => map.latLngToContainerPoint([latOfY(gy), lonOfX(gx)]);

  function render() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    if (S && !ui.zooming && ui.mode !== 'title') {
      const z = map.getZoom();
      const pxPerCell = (256 * Math.pow(2, z)) / 360 * ((BB[2] - BB[0]) / W);
      // capitals
      for (let i = 1; i < S.N.length; i++) {
        const n = S.N[i];
        if (!n.alive || n.cap < 0) continue;
        const c = gridToPt(n.cap % W + 0.5, Math.floor(n.cap / W) + 0.5);
        ctx.font = '14px system-ui'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.fillStyle = OWN[n.cap] === i ? '#ffd34d' : '#999'; ctx.strokeStyle = 'rgba(0,0,0,.7)'; ctx.lineWidth = 3;
        ctx.strokeText('★', c.x, c.y); ctx.fillText('★', c.x, c.y);
      }
      // nation labels
      for (let i = 1; i < S.N.length; i++) {
        const n = S.N[i];
        if (!n.alive || !n.cells) continue;
        const size = Math.sqrt(n.cells) * pxPerCell;
        if (size < 46 && !isPlayer(i) && !(ui.mode === 'pick' && ui.pickIdx === i)) continue;
        const c = gridToPt(n.cx, n.cy);
        if (c.x < -60 || c.y < -20 || c.x > innerWidth + 60 || c.y > innerHeight + 20) continue;
        const fs = Math.max(10, Math.min(15, size / 9));
        pill(c.x, c.y + 14, `${n.flag} ${size > 110 ? n.name + ' ' : ''}${fmtT(n.t)}`, n.color, fs);
      }
      // offensives progress
      for (const o of OFF) {
        if (!isPlayer(o.a) && !enemiesOf(S.player).includes(o.a)) continue;
        const ll = o.latlngs;
        let la = 0, lo = 0;
        ll.forEach((p) => { la += p[0]; lo += p[1]; });
        const c = map.latLngToContainerPoint([la / ll.length, lo / ll.length]);
        pill(c.x, c.y, `⚔️ ${Math.round((o.taken / o.total) * 100)}% · ${fmtT(o.t)}`, N(o.a).color, 11);
      }
    }
    // live drawing
    if (ui.path && ui.path.length > 1) {
      const col = drawColor();
      ctx.lineWidth = 3.5; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
      ctx.strokeStyle = col; ctx.fillStyle = col + '33';
      ctx.beginPath();
      ui.path.forEach((p, k) => (k ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.closePath(); ctx.fill();
      ctx.beginPath();
      ui.path.forEach((p, k) => (k ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.stroke();
      ctx.setLineDash([5, 6]); ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(ui.path[ui.path.length - 1].x, ui.path[ui.path.length - 1].y); ctx.lineTo(ui.path[0].x, ui.path[0].y); ctx.stroke();
      ctx.setLineDash([]);
    }
  }
  function drawColor() {
    if (ui.mode === 'found') return ui.custom.color;
    return S && S.player ? '#ff3b30' : '#ff3b30';
  }

  // ------------------------------------------------------------------ drawing input
  const drawLayer = $('draw-layer');
  function setDraw(on) {
    ui.draw = on;
    drawLayer.classList.toggle('hidden', !on);
    $('btn-draw').classList.toggle('on', on);
    $('draw-banner').classList.toggle('hidden', !on || ui.mode !== 'game');
    $('draw-banner').textContent = S && S.sandbox ? '✏️ Draw a loop — the land inside becomes yours' : '✏️ Draw a loop around enemy land to invade it';
    if (on) { map.dragging.disable(); } else { map.dragging.enable(); }
  }
  let pinch = false;
  drawLayer.addEventListener('pointerdown', (e) => {
    if (!e.isPrimary) { pinch = true; ui.path = null; return; }
    pinch = false;
    drawLayer.setPointerCapture(e.pointerId);
    ui.path = [{ x: e.clientX, y: e.clientY }];
  });
  drawLayer.addEventListener('pointermove', (e) => {
    if (!ui.path || !e.isPrimary || pinch) return;
    const last = ui.path[ui.path.length - 1];
    if (Math.hypot(e.clientX - last.x, e.clientY - last.y) >= 4) ui.path.push({ x: e.clientX, y: e.clientY });
  });
  const finish = (e) => {
    if (!e.isPrimary) return;
    const path = ui.path;
    ui.path = null;
    if (!path || pinch || path.length < 6) return;
    const latlngs = path.map((p) => map.containerPointToLatLng([p.x, p.y]));
    const poly = latlngs.map((ll) => [xOfLon(ll.lng), yOfLat(ll.lat)]);
    const cells = cellsInPolygon(poly);
    const lls = latlngs.map((ll) => [ll.lat, ll.lng]);
    if (ui.mode === 'found') claimForNation(cells);
    else if (ui.mode === 'game') proposeOffensive(cells, lls);
  };
  drawLayer.addEventListener('pointerup', finish);
  drawLayer.addEventListener('pointercancel', () => { ui.path = null; });
  // two-finger pinch still zooms while in draw mode
  drawLayer.addEventListener('wheel', (e) => { e.preventDefault(); map.setZoom(map.getZoom() + (e.deltaY < 0 ? 0.5 : -0.5)); }, { passive: false });
  let pinchStart = null;
  drawLayer.addEventListener('touchstart', (e) => {
    if (e.touches.length === 2) {
      const [a, b] = e.touches;
      pinchStart = { d: Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY), z: map.getZoom(), c: map.getCenter(), mx: (a.clientX + b.clientX) / 2, my: (a.clientY + b.clientY) / 2 };
    }
  }, { passive: true });
  drawLayer.addEventListener('touchmove', (e) => {
    if (e.touches.length !== 2 || !pinchStart) return;
    const [a, b] = e.touches;
    const d = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
    const mx = (a.clientX + b.clientX) / 2, my = (a.clientY + b.clientY) / 2;
    const z = Math.max(map.getMinZoom(), Math.min(map.getMaxZoom(), pinchStart.z + Math.log2(d / pinchStart.d)));
    map.setZoomAround([pinchStart.mx, pinchStart.my], z, { animate: false });
    map.panBy([pinchStart.mx - mx, pinchStart.my - my], { animate: false });
    pinchStart.mx = mx; pinchStart.my = my; pinchStart.z = z; pinchStart.d = d;
  }, { passive: true });
  drawLayer.addEventListener('touchend', () => { pinchStart = null; }, { passive: true });

  // ------------------------------------------------------------------ player: offensives
  let pending = null;
  function proposeOffensive(cells, latlngs) {
    const me = S.player;
    const by = {}, km = {};
    for (const c of cells) if (OWN[c] !== me) { by[OWN[c]] = (by[OWN[c]] || 0) + 1; km[OWN[c]] = (km[OWN[c]] || 0) + kmOf(c); }
    const ids = Object.keys(by).map(Number).sort((a, b) => by[b] - by[a]);
    if (!ids.length) { toast('That loop has no foreign land inside. Draw around land you want to take.'); return; }
    if (S.sandbox) {
      const losers = new Set(ids);
      for (const c of cells) if (OWN[c] !== me) setOwner(c, me);
      afterCaptures(me, losers);
      recount(); updateHud(); renderPanel();
      return;
    }
    pending = { cells, latlngs, by, km, ids };
    const draft = L.polygon(latlngs, { color: '#ff3b30', weight: 3, fill: true, fillOpacity: 0.12, interactive: false }).addTo(map);
    pending.draft = draft;
    renderLaunch();
  }
  function renderLaunch() {
    const me = S.player, p = pending;
    const rows = p.ids.slice(0, 4).map((i) => `<div class="p-sub" style="margin:2px 0">${N(i).flag} ${esc(N(i).name)} · ${fmtKm(p.km[i])}
      ${atWar(me, i) ? '<span class="tag war" style="padding:1px 5px;border-radius:4px;font-size:10px">AT WAR</span>' : truceOf(me, i) ? '— truce' : '— will declare war'}</div>`).join('');
    const blocked = p.ids.every((i) => truceOf(me, i));
    const newWars = p.ids.filter((i) => !atWar(me, i) && !truceOf(me, i));
    const troops = N(me).t * ui.commit;
    $('panel').innerHTML = `<div class="p-head"><span class="flag">⚔️</span><div><div class="p-title">New offensive</div>${rows}</div>
      <button class="icon-btn p-close" data-act="cancel">✕</button></div>
      <div class="hint" style="margin:8px 0 6px">Commit troops from your reserve (${fmtT(N(me).t)}):</div>
      <div class="seg">${[0.25, 0.5, 0.75, 1].map((f) => `<button data-commit="${f}" class="${ui.commit === f ? 'on' : ''}">${f === 1 ? 'All' : f * 100 + '%'}</button>`).join('')}</div>
      <div class="p-row"><button class="danger" data-act="launch" ${blocked || troops < 1 ? 'disabled' : ''}>${newWars.length ? '⚔️ Declare war & attack' : '⚔️ Launch'} with ${fmtT(troops)}</button></div>`;
    showPanel();
  }
  function cancelPending() { if (pending && pending.draft) map.removeLayer(pending.draft); pending = null; renderPanel(); }

  // ------------------------------------------------------------------ custom nation founding
  function claimForNation(cells) {
    const c = ui.custom;
    const changed = [];
    for (const i of cells) if (OWN[i] !== c.idx) { changed.push(i, OWN[i]); setOwner(i, c.idx); }
    if (!changed.length) return;
    c.history.push(changed);
    flush();
    renderFoundSheet();
  }
  function undoClaim() {
    const ch = ui.custom.history.pop();
    if (!ch) return;
    for (let k = 0; k < ch.length; k += 2) setOwner(ch[k], ch[k + 1]);
    renderFoundSheet();
  }
  function renderFoundSheet() {
    const c = ui.custom, n = N(c.idx);
    $('pick-confirm').innerHTML = `<div class="p-head"><span class="flag">${c.flag}</span><div><div class="p-title">${esc(c.name)}</div>
      <div class="p-sub">${n.cells ? fmtKm(n.km) + ' of land' : 'Draw a loop on the map to claim land'}</div></div></div>
      <div class="p-row" style="margin-top:12px"><button id="f-mode">${ui.draw ? '✋ Move map' : '✏️ Draw'}</button>
      <button id="f-undo" ${c.history.length ? '' : 'disabled'}>↶ Undo</button>
      <button class="primary" id="f-go" ${n.cells >= 30 ? '' : 'disabled'}>Found ${esc(c.name)} ›</button></div>`;
    $('pick-confirm').classList.remove('hidden');
    $('f-undo').onclick = undoClaim;
    $('f-mode').onclick = () => { setDraw(!ui.draw); renderFoundSheet(); };
    $('f-go').onclick = foundNation;
  }
  function foundNation() {
    const c = ui.custom, me = c.idx, n = N(me);
    // take a share of each donor's army, proportional to the land taken
    recount();
    const idxOf = {};
    S.N.forEach((x) => { if (x && !x.custom) idxOf[x.code] = x.idx; });
    const taken = {};
    for (let i = 0; i < OWN.length; i++) if (OWN[i] === me) { const orig = idxOf[P[PROV[i] - 1].c]; taken[orig] = (taken[orig] || 0) + 1; }
    let troops = 0;
    for (const d in taken) {
      const dn = N(+d);
      if (!dn || +d === me) continue;
      const share = taken[d] / (taken[d] + dn.cells);
      troops += dn.t * share * 1.3;
      dn.t *= 1 - share;
      dn.start = Math.max(1, dn.start - taken[d]);
    }
    n.t = Math.round(troops + 20);
    n.start = n.cells;
    n.alive = true;
    // capital: the claimed cell closest to the centre of the new nation
    let best = -1, bd = Infinity;
    for (let i = 0; i < OWN.length; i++) if (OWN[i] === me) { const d = (i % W - n.cx) ** 2 + (Math.floor(i / W) - n.cy) ** 2; if (d < bd) { bd = d; best = i; } }
    n.cap = best;
    S.N.forEach((x) => { if (x && x !== n && x.cap >= 0 && OWN[x.cap] === me) x.cap = -1; });
    const donors = Object.keys(taken).map(Number).filter((d) => d !== me && N(d) && N(d).alive).sort((a, b) => taken[b] - taken[a]);
    beginGame(me);
    news(`${c.flag} ${c.name} has declared independence${donors.length ? ' from ' + donors.slice(0, 3).map((d) => N(d).name).join(', ') : ''}!`, c.war ? 'war' : '');
    if (c.war && !S.sandbox) donors.filter((d) => taken[d] > n.cells * 0.15).forEach((d) => declareWar(d, me, true));
  }

  // ------------------------------------------------------------------ main loop
  let last = performance.now(), acc = 0;
  function frame(now) {
    const dt = Math.min(250, now - last);
    last = now;
    if (S && ui.mode === 'game' && S.speed > 0 && !ui.modalOpen && !S.over) {
      acc += (dt * S.speed) / DAY_MS;
      let n = 0;
      while (acc >= 1 && n++ < 3) { acc -= 1; tickDay(); }
      if (now - ui.lastPanel > 500) { ui.lastPanel = now; updateHud(); if (!pending) renderPanel(true); }
    }
    flush();
    render();
    requestAnimationFrame(frame);
  }

  // ------------------------------------------------------------------ HUD & panel
  function updateHud() {
    if (!S || !S.player) return;
    const me = N(S.player);
    $('hud-flag').textContent = me.flag;
    $('hud-name').textContent = me.name;
    $('hud-gold').textContent = Math.floor(me.gold);
    $('hud-troops').textContent = fmtT(strength(S.player));
    $('hud-prov').textContent = fmtKm(me.km).replace(' km²', '');
    $('hud-date').textContent = dateStr(S.day);
    document.querySelectorAll('.speed button').forEach((b) => b.classList.toggle('on', +b.dataset.speed === S.speed));
  }

  function toast(msg, kind) {
    const box = $('toasts');
    const el = document.createElement('div');
    el.className = 'toast ' + (kind || '');
    el.textContent = msg;
    box.appendChild(el);
    while (box.children.length > 3) box.removeChild(box.firstChild);
    setTimeout(() => { el.classList.add('fade'); setTimeout(() => el.remove(), 600); }, 3600);
  }
  function news(msg, kind) {
    S.news.unshift({ d: S.day, m: msg });
    if (S.news.length > 60) S.news.pop();
    if (ui.mode === 'game') toast(msg, kind);
  }

  function showPanel() {
    const panel = $('panel');
    panel.classList.remove('hidden');
    $('hud').classList.add('panel-open');
    $('hud').style.setProperty('--panel-h', panel.offsetHeight + 8 + 'px');
  }
  function hidePanel() { $('panel').classList.add('hidden'); $('hud').classList.remove('panel-open'); }

  // info panel: tapped nation (or your own nation with its offensives)
  function renderPanel(soft) {
    if (pending) return;
    if (!S || ui.mode !== 'game' || ui.info == null) { hidePanel(); return; }
    const i = ui.info, n = N(i), me = S.player;
    if (!n.alive) { ui.info = null; hidePanel(); return; }
    const region = ui.infoProv != null ? P[ui.infoProv].name + ' region · ' : '';
    let h = `<div class="p-head"><span class="flag">${n.flag}</span><div><div class="p-title">${esc(n.name)}</div>
      <div class="p-sub"><span class="color-dot" style="background:${n.color}"></span>${esc(region)}${fmtKm(n.km)}</div></div>
      <button class="icon-btn p-close" data-act="close">✕</button></div>
      <div class="p-stats"><div>Troops<b>${fmtT(strength(i))}</b></div><div>Income<b>+${(n.val * 0.55).toFixed(0)}/d</b></div><div>${isPlayer(i) ? 'Gold' : 'Wars'}<b>${isPlayer(i) ? Math.floor(n.gold) : enemiesOf(i).length}</b></div></div>`;
    const g = Math.floor(N(me).gold);
    if (isPlayer(i)) {
      h += `<div class="hint" style="margin:-4px 0 6px">Reserve ${fmtT(n.t)} · army limit ${fmtT(armyLimit(me))}</div>
        <div class="p-row"><button data-act="recruit" data-n="10" ${g < 10 * RECRUIT_COST ? 'disabled' : ''}>+10k 🪖 <small>(${10 * RECRUIT_COST}💰)</small></button>
        <button data-act="recruit" data-n="50" ${g < 50 * RECRUIT_COST ? 'disabled' : ''}>+50k 🪖 <small>(${50 * RECRUIT_COST}💰)</small></button></div>`;
      const mine = OFF.filter((o) => o.a === me);
      h += mine.map((o) => `<div class="off-row">⚔️ <span>${fmtT(o.t)}</span><div class="bar"><i style="width:${Math.round((o.taken / o.total) * 100)}%"></i></div>
        <span>${Math.round((o.taken / o.total) * 100)}%</span><button data-stop="${o.id}">Stop</button></div>`).join('');
      if (!mine.length) h += `<div class="hint">Tap ✏️ and draw a loop around enemy land to launch an offensive.</div>`;
    } else if (atWar(me, i)) {
      h += `<div class="p-row"><button data-act="peace">🕊️ Offer peace</button></div>
        <div class="hint">Tap ✏️ and draw around their land to attack.</div>`;
    } else {
      const tr = truceOf(me, i);
      h += `<div class="p-row"><button class="danger" data-act="war" ${tr ? 'disabled' : ''}>⚔️ Declare war</button></div>
        <div class="hint">${tr ? `Truce for ${tr.until - S.day} more days.` : 'Or just draw around their land — you\'ll be asked to declare war.'}</div>`;
    }
    if (soft && $('panel').innerHTML === h) return;
    $('panel').innerHTML = h;
    showPanel();
  }

  $('panel').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    const me = S.player;
    if (b.dataset.commit) { ui.commit = +b.dataset.commit; renderLaunch(); return; }
    if (b.dataset.stop) { const o = OFF.find((x) => x.id === +b.dataset.stop); if (o) endOffensive(o); renderPanel(); return; }
    switch (b.dataset.act) {
      case 'close': ui.info = null; renderPanel(); break;
      case 'cancel': cancelPending(); break;
      case 'launch': {
        const p = pending;
        p.ids.filter((i) => !atWar(me, i) && !truceOf(me, i)).forEach((i) => declareWar(me, i));
        const o = launchOffensive(me, p.cells, p.latlngs, N(me).t * ui.commit);
        map.removeLayer(p.draft);
        pending = null;
        if (o) { toast(o.naval ? '⚓ Amphibious landing launched!' : '⚔️ Offensive launched!'); ui.info = me; }
        else toast('Nothing to attack there.');
        renderPanel(); updateHud();
        if (S.speed === 0) toast('The game is paused — press 1× to start the clock.');
        break;
      }
      case 'recruit': {
        const k = +b.dataset.n, cost = k * RECRUIT_COST;
        if (strength(me) + k > armyLimit(me)) toast('Army limit reached — conquer more land to raise it.');
        else if (N(me).gold >= cost) { N(me).gold -= cost; N(me).t += k; }
        renderPanel(); updateHud();
        break;
      }
      case 'war': confirmWar(ui.info); break;
      case 'peace': playerOffersPeace(ui.info); break;
    }
  });

  map.on('click', (e) => {
    const x = Math.floor(xOfLon(e.latlng.lng)), y = Math.floor(yOfLat(e.latlng.lat));
    const c = x >= 0 && y >= 0 && x < W && y < H ? y * W + x : -1;
    const o = c >= 0 ? OWN[c] : 0;
    if (ui.mode === 'pick') { if (o) pickCountry(o); return; }
    if (ui.mode !== 'game' || pending) return;
    ui.info = o || null;
    ui.infoProv = o ? PROV[c] - 1 : null;
    renderPanel();
  });

  // ------------------------------------------------------------------ modals
  function openModal(html, onClick) {
    ui.modalOpen = true;
    $('modal-body').innerHTML = html;
    $('modal').classList.remove('hidden');
    $('modal').onclick = (e) => {
      const b = e.target.closest('button');
      if (e.target === $('modal')) { closeModal(); return; }
      if (b && onClick) onClick(b, e);
    };
  }
  function closeModal() { ui.modalOpen = false; $('modal').classList.add('hidden'); $('modal').onclick = null; }

  function confirmWar(i) {
    const n = N(i);
    openModal(`<h2>⚔️ Declare war?</h2><p>${n.flag} <b>${esc(n.name)}</b> has about <b>${fmtT(strength(i))}</b> troops. You have ${fmtT(strength(S.player))}.</p>
      <div class="row"><button class="big ghost" data-a="no">Cancel</button><button class="big primary" data-a="yes">Declare war</button></div>`, (b) => {
      if (b.dataset.a === 'yes') declareWar(S.player, i);
      closeModal(); renderPanel();
    });
  }
  function playerOffersPeace(i) {
    if (acceptsPeace(i, S.player)) makePeace(S.player, i);
    else toast(`${N(i).flag} ${N(i).name} rejected your peace offer.`, 'war');
    if (ui.modalOpen) diplomacy();
    renderPanel();
  }
  function offerPeaceToPlayer(i) {
    const n = N(i);
    openModal(`<h2>🕊️ Peace offer</h2><p>${n.flag} <b>${esc(n.name)}</b> offers peace. Everyone keeps the land they hold now, and a 120-day truce begins.</p>
      <div class="row"><button class="big ghost" data-a="no">Refuse</button><button class="big primary" data-a="yes">Accept</button></div>`, (b) => {
      if (b.dataset.a === 'yes') makePeace(i, S.player);
      closeModal();
    });
  }
  function diplomacy() {
    const me = S.player;
    const list = S.N.filter((n) => n && n.alive)
      .sort((a, b) => (isPlayer(b.idx) - isPlayer(a.idx)) || (atWar(me, b.idx) - atWar(me, a.idx)) || b.cells - a.cells);
    const rows = list.map((n) => {
      let right;
      if (isPlayer(n.idx)) right = '<span class="tag you">YOU</span>';
      else if (atWar(me, n.idx)) right = `<span class="tag war">WAR</span><button class="ok" data-peace="${n.idx}">Peace</button>`;
      else if (truceOf(me, n.idx)) right = `<span class="tag truce">TRUCE ${truceOf(me, n.idx).until - S.day}d</span>`;
      else right = `<button class="danger" data-war="${n.idx}">War</button>`;
      const wars = enemiesOf(n.idx).filter((e) => !isPlayer(e)).map((e) => N(e).flag).join('');
      return `<div class="drow"><span class="flag">${n.flag}</span><div class="dn"><b><span class="color-dot" style="background:${n.color}"></span>${esc(n.name)}</b>
        <span>${fmtKm(n.km)} · ${fmtT(strength(n.idx))} troops${wars ? ' · at war with ' + wars : ''}</span></div>${right}</div>`;
    }).join('');
    openModal(`<h2>🤝 Diplomacy</h2><div class="dlist">${rows}</div><div class="row"><button class="big" data-close>Close</button></div>`, (b) => {
      if (b.dataset.close != null) return closeModal();
      if (b.dataset.war) { closeModal(); confirmWar(+b.dataset.war); }
      if (b.dataset.peace) playerOffersPeace(+b.dataset.peace);
    });
  }
  function newsModal() {
    const items = S.news.map((x) => `<div class="news-item"><small>${dateStr(x.d)}</small>${esc(x.m)}</div>`).join('') || '<p>No news yet.</p>';
    openModal(`<h2>📰 News</h2>${items}<div class="row"><button class="big" data-close>Close</button></div>`, () => closeModal());
  }
  function gameMenu() {
    const chk = (k, label) => `<label class="check"><input type="checkbox" data-set="${k}" ${settings[k] ? 'checked' : ''}> ${label}</label>`;
    openModal(`<h2>☰ Menu</h2>
      ${chk('satellite', 'Satellite imagery')}
      ${chk('labels', 'Place names & borders overlay')}
      ${chk('autoRecruit', 'Recruit troops with spare gold automatically (keeps 100💰)')}
      <div class="row"><button class="big" data-a="howto">How to play</button></div>
      <div class="row"><button class="big ghost" data-a="quit">Save & quit</button><button class="big primary" data-a="close">Resume</button></div>`, (b) => {
      if (b.dataset.a === 'close') closeModal();
      if (b.dataset.a === 'howto') howTo();
      if (b.dataset.a === 'quit') { save(); closeModal(); toTitle(); }
    });
    $('modal-body').querySelectorAll('input[data-set]').forEach((inp) => {
      inp.onchange = () => {
        settings[inp.dataset.set] = inp.checked;
        saveSettings();
        if (settings.satellite) satLayer.addTo(map); else map.removeLayer(satLayer);
        if (settings.labels) labelLayer.addTo(map); else map.removeLayer(labelLayer);
      };
    });
  }
  function howTo() {
    openModal(`<h2>❔ How to play</h2><ol class="howto">
      <li>Pick a country, or create your own nation and <b>draw its borders</b> with your finger anywhere on the map.</li>
      <li>To attack, tap <b>✏️ Draw</b> and draw a loop around the land you want. Choose how many troops to commit and launch — your front line pushes through the drawn area day by day.</li>
      <li>Drawing over a country you're at peace with asks you to declare war first.</li>
      <li>Bigger armies push faster. Capitals ★ are defended harder; take one after a country has lost half its land and it surrenders.</li>
      <li>Land earns 💰 gold; spend it on troops. Make peace in <b>Diplomacy</b>.</li>
      <li>Sandbox scenario: drawn loops become yours instantly — paint the map however you like.</li>
      <li>Pinch with two fingers to zoom, even while drawing. Control 70% of Europe to win.</li></ol>
      <div class="row"><button class="big primary" data-close>Got it</button></div>`, () => {
      closeModal();
      if (ui.mode === 'title') $('screen-title').classList.remove('hidden');
    });
  }
  function victory() {
    openModal(`<h2>👑 Europe is yours!</h2><p>${N(S.player).flag} <b>${esc(N(S.player).name)}</b> controls ${Math.round((N(S.player).cells / LAND) * 100)}% of Europe on ${dateStr(S.day)}.</p>
      <div class="row"><button class="big ghost" data-a="quit">Main menu</button><button class="big primary" data-a="go">Keep going</button></div>`, (b) => {
      closeModal();
      if (b.dataset.a === 'quit') { save(); toTitle(); }
    });
  }
  function gameOver() {
    S.over = true;
    try { localStorage.removeItem('ia_save2'); } catch (e) { /* ignore */ }
    openModal(`<h2>💀 Defeat</h2><p>${N(S.player).flag} <b>${esc(N(S.player).name)}</b> has fallen on ${dateStr(S.day)}.</p>
      <div class="row"><button class="big ghost" data-a="watch">Watch the world</button><button class="big primary" data-a="quit">Main menu</button></div>`, (b) => {
      closeModal();
      if (b.dataset.a === 'quit') toTitle();
      else S.over = false;
    });
  }

  // ------------------------------------------------------------------ title / pick / found flow
  const EMBLEM = `<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
    <defs><linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe9a8"/><stop offset=".5" stop-color="#f5b83d"/><stop offset="1" stop-color="#a86d0c"/></linearGradient>
    <clipPath id="sh"><path d="M60 14 L96 26 V58 C96 82 80 98 60 106 C40 98 24 82 24 58 V26 Z"/></clipPath></defs>
    <g stroke="url(#gold)" stroke-width="7" stroke-linecap="round"><line x1="18" y1="18" x2="102" y2="102"/><line x1="102" y1="18" x2="18" y2="102"/></g>
    <g fill="url(#gold)"><rect x="8" y="8" width="16" height="8" rx="3" transform="rotate(45 16 12)"/><rect x="96" y="8" width="16" height="8" rx="3" transform="rotate(-45 104 12)"/></g>
    <g clip-path="url(#sh)"><rect x="0" y="0" width="120" height="120" fill="#d23a2a"/>
    <path d="M20 10 L64 10 L56 30 L66 44 L52 58 L62 72 L48 88 L54 110 L20 110 Z" fill="#2f6fe0"/>
    <path d="M64 10 L56 30 L66 44 L52 58 L62 72 L48 88 L54 110" fill="none" stroke="#fff" stroke-width="2.5" stroke-linejoin="round"/>
    <path d="M78 46 l3.5 7.2 7.9 1.1-5.7 5.6 1.4 7.9-7.1-3.8-7.1 3.8 1.4-7.9-5.7-5.6 7.9-1.1z" fill="#ffd34d"/></g>
    <path d="M60 14 L96 26 V58 C96 82 80 98 60 106 C40 98 24 82 24 58 V26 Z" fill="none" stroke="url(#gold)" stroke-width="5" stroke-linejoin="round"/></svg>`;
  $('emblem').innerHTML = EMBLEM;

  function hideScreens() { ['screen-title', 'screen-pick', 'screen-custom', 'pick-confirm'].forEach((s) => $(s).classList.add('hidden')); }
  function clearMapExtras() {
    OFF.forEach((o) => o.layer && map.removeLayer(o.layer));
    OFF = [];
    if (pending && pending.draft) map.removeLayer(pending.draft);
    pending = null;
  }

  let titleDrift = null;
  function toTitle() {
    clearMapExtras();
    ui.mode = 'title'; ui.info = null;
    setDraw(false);
    hideScreens(); hidePanel();
    $('hud').classList.add('hidden');
    $('screen-title').classList.remove('hidden');
    $('btn-continue').classList.toggle('hidden', !hasSave());
    S = null; OWN.fill(0); PIX.fill(0); tctx.putImageData(img, 0, 0);
    map.flyToBounds([[40, -8], [62, 35]], { duration: 0.8 });
    clearInterval(titleDrift);
    let ph = 0;
    titleDrift = setInterval(() => { if (ui.mode === 'title') map.panBy([Math.sin((ph += 0.004)) * 0.7, 0], { animate: false }); }, 50);
  }
  const opts = () => ({ scenario: $('opt-scenario').value, aggr: +$('opt-aggr').value });

  function startPick() {
    clearInterval(titleDrift);
    ui.mode = 'pick'; ui.pickIdx = 0;
    newGame(opts());
    hideScreens();
    $('screen-pick').classList.remove('hidden');
    $('pick-title').textContent = 'Choose your country';
    $('pick-hint').textContent = 'Tap a country on the map or pick from the list';
    const list = S.N.filter(Boolean).sort((a, b) => a.name.localeCompare(b.name));
    $('pick-list').innerHTML = list.map((n) => `<button data-idx="${n.idx}">${n.flag} ${esc(n.name)}</button>`).join('');
  }
  $('pick-list').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-idx]');
    if (b) pickCountry(+b.dataset.idx, true);
  });
  function pickCountry(i, fly) {
    ui.pickIdx = i;
    paintAll();
    document.querySelectorAll('#pick-list button').forEach((b) => b.classList.toggle('on', +b.dataset.idx === i));
    const n = N(i);
    if (fly) map.flyTo([latOfY(n.cy), lonOfX(n.cx)], Math.max(4, Math.min(6, 9.5 - Math.log2(Math.sqrt(n.cells)))), { duration: 0.6 });
    const wars = enemiesOf(i).map((e) => N(e).flag + ' ' + N(e).name).join(', ');
    $('pick-confirm').innerHTML = `<div class="p-head"><span class="flag">${n.flag}</span><div><div class="p-title">${esc(n.name)}</div>
      <div class="p-sub">${fmtKm(n.km)} · ${fmtT(n.t)} troops${wars ? ' · at war with ' + esc(wars) : ''}</div></div></div>
      <div class="p-row" style="margin-top:12px"><button class="primary" id="pick-go">Play as ${esc(n.name)} ›</button></div>`;
    $('pick-confirm').classList.remove('hidden');
    $('pick-go').onclick = () => beginGame(i);
  }

  function beginGame(i) {
    S.player = i;
    hideScreens();
    clearInterval(titleDrift);
    ui.mode = 'game'; ui.info = i; ui.pickIdx = 0;
    setDraw(false);
    $('hud').classList.remove('hidden');
    recount(); paintAll(); updateHud(); renderPanel();
    const n = N(i);
    map.flyTo([latOfY(n.cy), lonOfX(n.cx)], Math.max(4, Math.min(7, 10 - Math.log2(Math.sqrt(n.cells)))), { duration: 0.8 });
    S.speed = 0;
    toast(S.sandbox ? `${n.flag} Sandbox: tap ✏️ and draw to paint land for ${n.name}.` : `${n.flag} You lead ${n.name}. Paused — tap ✏️ to draw an attack, then press 1×.`);
    save();
  }

  const SWATCHES = ['#f5b83d', '#ff6b00', '#e0307a', '#9b4dff', '#00c2a8', '#28c840', '#00a2ff', '#ffffff', '#111827', '#8b5a2b'];
  const EMBLEMS = ['🦅', '🐻', '🦁', '🐺', '🐉', '👑', '⚔️', '🔥', '⭐', '🌙', '🍊', '🛡️'];
  function startCustom() {
    clearInterval(titleDrift);
    ui.custom = ui.custom || { color: SWATCHES[0], flag: EMBLEMS[10] };
    hideScreens();
    $('screen-custom').classList.remove('hidden');
    $('cn-colors').innerHTML = SWATCHES.map((c) => `<button data-c="${c}" style="background:${c}" class="${ui.custom.color === c ? 'on' : ''}"></button>`).join('');
    $('cn-emblems').innerHTML = EMBLEMS.map((f) => `<button data-f="${f}" class="${ui.custom.flag === f ? 'on' : ''}">${f}</button>`).join('');
  }
  $('cn-colors').addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) { ui.custom.color = b.dataset.c; startCustom(); } });
  $('cn-emblems').addEventListener('click', (e) => { const b = e.target.closest('button'); if (b) { ui.custom.flag = b.dataset.f; startCustom(); } });
  $('cn-next').onclick = () => {
    const c = ui.custom;
    c.name = ($('cn-name').value || 'New Nation').trim().slice(0, 24);
    c.war = $('cn-war').checked;
    c.history = [];
    newGame(opts());
    const n = { idx: S.N.length, code: 'CUS', name: c.name, color: c.color, flag: c.flag, power: 1.2, t: 0, gold: 150, alive: true, cells: 0, val: 0, km: 0, start: 0, cap: -1, cx: 0, cy: 0, custom: true };
    S.N.push(n);
    c.idx = n.idx;
    buildPalette();
    ui.mode = 'found';
    hideScreens();
    $('screen-pick').classList.remove('hidden');
    $('pick-title').textContent = `${c.flag} ${c.name}`;
    $('pick-hint').textContent = 'Draw your borders with your finger · pinch to zoom';
    $('pick-list').innerHTML = '';
    setDraw(true);
    renderFoundSheet();
  };

  // ------------------------------------------------------------------ save / load
  function hasSave() { try { return !!localStorage.getItem('ia_save2'); } catch (e) { return false; } }
  function encodeOwn() {
    const runs = [];
    for (let i = 0; i < OWN.length;) { let j = i; while (j < OWN.length && OWN[j] === OWN[i] && j - i < 65535) j++; runs.push(OWN[i], j - i); i = j; }
    let s = '';
    const u8 = new Uint8Array(new Uint16Array(runs).buffer);
    for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
    return btoa(s);
  }
  function decodeOwn(b64) {
    const bin = atob(b64);
    const u8 = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    const runs = new Uint16Array(u8.buffer);
    let o = 0;
    for (let i = 0; i < runs.length; i += 2) { OWN.fill(runs[i], o, o + runs[i + 1]); o += runs[i + 1]; }
  }
  function save() {
    if (!S || !S.player || S.over || ui.mode !== 'game') return;
    // offensives in progress are refunded to the reserve in the save
    const N2 = S.N.map((n) => (n ? Object.assign({}, n, { t: n.t + committed(n.idx) }) : null));
    try { localStorage.setItem('ia_save2', JSON.stringify(Object.assign({}, S, { N: N2, own: encodeOwn() }))); } catch (e) { /* storage full */ }
  }
  function load() {
    try {
      const s = JSON.parse(localStorage.getItem('ia_save2'));
      if (!s || !s.own) return false;
      decodeOwn(s.own);
      delete s.own;
      S = s;
      return true;
    } catch (e) { return false; }
  }

  // ------------------------------------------------------------------ wiring
  $('btn-play-country').onclick = startPick;
  $('btn-play-custom').onclick = startCustom;
  $('btn-howto').onclick = () => { $('screen-title').classList.add('hidden'); howTo(); };
  $('btn-continue').onclick = () => {
    if (!load()) { toast('Save could not be loaded.'); return; }
    beginGame(S.player);
  };
  document.querySelectorAll('[data-back]').forEach((b) => { b.onclick = () => toTitle(); });
  document.querySelectorAll('.speed button').forEach((b) => { b.onclick = () => { S.speed = +b.dataset.speed; updateHud(); }; });
  $('btn-menu').onclick = gameMenu;
  $('btn-diplo').onclick = diplomacy;
  $('btn-news').onclick = newsModal;
  $('btn-draw').onclick = () => { if (pending) cancelPending(); setDraw(!ui.draw); };
  $('btn-nation').onclick = () => { ui.info = S.player; renderPanel(); const n = N(S.player); map.flyTo([latOfY(n.cy), lonOfX(n.cx)], map.getZoom(), { duration: 0.5 }); };
  document.addEventListener('visibilitychange', () => { if (document.hidden) save(); });

  window.IA = {
    save,
    onBack() {
      if (ui.modalOpen) { closeModal(); return true; }
      if (pending) { cancelPending(); return true; }
      if (ui.mode === 'game') {
        if (ui.draw) { setDraw(false); return true; }
        if (ui.info != null) { ui.info = null; renderPanel(); return true; }
        gameMenu(); return true;
      }
      if (ui.mode !== 'title') { toTitle(); return true; }
      return false;
    },
    // test hooks
    _state: () => S, _own: () => OWN, _off: () => OFF.map((o) => ({ a: S.N[o.a].code, t: Math.round(o.t), taken: o.taken, total: o.total, q: o.queue.length, naval: o.naval })), _map: map, _P: P,
    _sim(days) { for (let i = 0; i < days; i++) tickDay(); flush(); },
    _lasso(lls) { const poly = lls.map(([la, lo]) => [xOfLon(lo), yOfLat(la)]); return cellsInPolygon(poly); },
  };

  resize();
  toTitle();
  requestAnimationFrame(frame);
})();
