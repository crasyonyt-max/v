/* Iron Atlas — Conquest of Europe */
(function () {
  'use strict';

  // ------------------------------------------------------------------ data
  const D = window.IA_DATA;
  const RAD = Math.PI / 180;
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

  const P = D.provinces.map((p) => ({
    id: p.id, c: p.c, name: p.n, cap: !!p.cap, area: p.a, coast: !!p.coast,
    lat: p.l[1], lon: p.l[0], g: p.g,
    adj: p.adj.map((a) => ({ id: Math.abs(a) - 1, sea: a < 0 })),
    val: Math.round((Math.min(3.5, 0.8 + p.a / 45000) + (p.cap ? 2 : 0)) * 10) / 10,
  }));
  const COUNTRY = {};
  D.countries.forEach((c) => { COUNTRY[c.code] = c; });

  function pointInRing(pt, r) {
    let inside = false;
    for (let i = 0, j = r.length - 1; i < r.length; j = i++) {
      const [xi, yi] = r[i], [xj, yj] = r[j];
      if ((yi > pt[1]) !== (yj > pt[1]) && pt[0] < ((xj - xi) * (pt[1] - yi)) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }
  const provinceAt = (lon, lat) => P.find((p) => p.g.some((poly) => pointInRing([lon, lat], poly[0]) && !poly.slice(1).some((h) => pointInRing([lon, lat], h))));
  const distKm = (a, b) => Math.hypot((a.lon - b.lon) * Math.cos(((a.lat + b.lat) / 2) * RAD) * 111.32, (a.lat - b.lat) * 111.32);

  // ------------------------------------------------------------------ state
  const RECRUIT_COST = 2; // gold per 1k troops
  const DAY_MS = 1500;
  let S = null; // game state
  const ui = { sel: null, sendFrac: 0.75, mode: 'title', zooming: false, effects: [], pickCode: null, custom: null, lastPanel: 0 };
  const settings = loadSettings();

  function loadSettings() {
    const def = { labels: true, satellite: true, autoFront: true, autoRecruit: true, autoAttack: false };
    try { return Object.assign(def, JSON.parse(localStorage.getItem('ia_settings') || '{}')); } catch (e) { return def; }
  }
  function saveSettings() { try { localStorage.setItem('ia_settings', JSON.stringify(settings)); } catch (e) { /* ignore */ } }

  function newGame(opts) {
    S = {
      v: 1, day: 0, speed: 1, player: null, aggr: opts.aggr, nations: {}, prov: [], armies: [], wars: [], truces: [], news: [],
      nextArmy: 1, over: false, won: false,
    };
    for (const c of D.countries) {
      S.nations[c.code] = {
        code: c.code, name: c.name, color: BASE_COLORS[c.code] || '#888', flag: flagOf(c.code), power: c.power,
        gold: 60, alive: true, start: 0, capital: null, lost: 0,
      };
    }
    for (const p of P) {
      const n = S.nations[p.c];
      n.start++;
      if (p.cap) n.capital = p.id;
      S.prov.push({ o: p.c, t: Math.round((3 + p.val * 3.2) * n.power * (p.cap ? 1.5 : 1) * 10) / 10, f: p.cap ? 1 : 0 });
    }
    if (opts.scenario === 'present') {
      const crimea = provinceAt(34.1, 44.95);
      const occupied = [crimea, P.find((p) => p.name === 'Donetsk'), P.find((p) => p.name === 'Luhansk')];
      occupied.forEach((p) => { if (p && S.prov[p.id].o === 'UKR') { S.prov[p.id].o = 'RUS'; S.nations.UKR.start--; S.nations.RUS.start++; } });
      S.wars.push({ a: 'RUS', b: 'UKR', start: -900, lostA: 0, lostB: 0 });
      // an entrenched front line
      P.forEach((p) => {
        if (S.prov[p.id].o === 'UKR' && p.adj.some((a) => !a.sea && S.prov[a.id].o === 'RUS')) { S.prov[p.id].f = 2; S.prov[p.id].t *= 1.6; }
      });
    }
  }

  // ------------------------------------------------------------------ helpers
  const N = (code) => S.nations[code];
  const owner = (id) => S.prov[id].o;
  const isPlayer = (code) => S && code === S.player;
  const atWar = (a, b) => a !== b && S.wars.some((w) => (w.a === a && w.b === b) || (w.a === b && w.b === a));
  const warOf = (a, b) => S.wars.find((w) => (w.a === a && w.b === b) || (w.a === b && w.b === a));
  const truceOf = (a, b) => S.truces.find((t) => ((t.a === a && t.b === b) || (t.a === b && t.b === a)) && t.until > S.day);
  const provsOf = (code) => S.prov.reduce((arr, p, i) => (p.o === code && arr.push(i), arr), []);
  const strength = (code) => S.prov.reduce((s, p) => s + (p.o === code ? p.t : 0), 0) + S.armies.reduce((s, a) => s + (a.o === code ? a.t : 0), 0);
  const armyLimit = (code) => {
    const n = S.nations[code];
    return 40 + S.prov.reduce((s, p, i) => s + (p.o === code ? P[i].val : 0), 0) * 8 * n.power;
  };
  const enemiesOf = (code) => S.wars.filter((w) => w.a === code || w.b === code).map((w) => (w.a === code ? w.b : w.a));
  const defense = (id) => {
    const p = S.prov[id];
    return p.t * (1.4 + 0.3 * p.f) * (P[id].cap ? 1.2 : 1) * (P[id].c === p.o ? 1.15 : 1);
  };
  function fmtT(t) {
    if (t >= 1000) return (t / 1000).toFixed(1) + 'M';
    if (t >= 10) return Math.round(t) + 'k';
    return (Math.round(t * 10) / 10) + 'k';
  }
  function dateStr(day) {
    const d = new Date(Date.UTC(2026, 9, 16) + day * 86400000);
    return String(d.getUTCDate()).padStart(2, '0') + '.' + String(d.getUTCMonth() + 1).padStart(2, '0') + '.' + d.getUTCFullYear();
  }
  function darken(hex, f) {
    const n = parseInt(hex.slice(1), 16);
    const r = Math.round(((n >> 16) & 255) * f), g = Math.round(((n >> 8) & 255) * f), b = Math.round((n & 255) * f);
    return 'rgb(' + r + ',' + g + ',' + b + ')';
  }
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const $ = (id) => document.getElementById(id);

  // ------------------------------------------------------------------ map
  const map = L.map('map', {
    zoomControl: false, preferCanvas: true, minZoom: 3, maxZoom: 10, zoomSnap: 0.25, wheelPxPerZoomLevel: 90,
    maxBounds: [[22, -45], [80, 70]], maxBoundsViscosity: 0.8, attributionControl: true,
  });
  map.attributionControl.setPrefix(false);
  const renderer = L.canvas({ padding: 0.4, tolerance: 3 });
  const satLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
    maxZoom: 18, attribution: 'Imagery © Esri, Maxar, Earthstar Geographics', crossOrigin: false,
  });
  const labelLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}', {
    maxZoom: 18, attribution: 'Labels © Esri, HERE, Garmin', pane: 'overlayPane', opacity: 0.9,
  });
  map.createPane('labels');
  map.getPane('labels').style.zIndex = 420;
  map.getPane('labels').style.pointerEvents = 'none';
  labelLayer.options.pane = 'labels';
  if (settings.satellite) satLayer.addTo(map);
  if (settings.labels) labelLayer.addTo(map);
  L.control.attribution({ prefix: false }).addAttribution('Borders © Natural Earth');
  map.fitBounds([[40, -8], [62, 35]]);

  const polys = P.map((p) => {
    const latlngs = p.g.map((poly) => poly.map((ring) => ring.map(([x, y]) => [y, x])));
    const layer = L.polygon(latlngs, { renderer, weight: 0.8, fillOpacity: 0.42, smoothFactor: 0.6 });
    layer.on('click', (e) => { L.DomEvent.stopPropagation(e); onProvinceTap(p.id); });
    layer.addTo(map);
    return layer;
  });
  map.on('click', () => { if (ui.mode === 'game') select(null); });
  map.on('zoomstart', () => { ui.zooming = true; });
  map.on('zoomend', () => { ui.zooming = false; });

  function baseStyle(id) {
    if (!S) return { color: 'rgba(255,255,255,0.35)', weight: 0.6, fillColor: '#ffffff', fillOpacity: 0.05, dashArray: null };
    const n = N(owner(id));
    const mine = isPlayer(n.code);
    return { color: darken(n.color, 0.55), weight: mine ? 1 : 0.7, fillColor: n.color, fillOpacity: mine ? 0.5 : 0.4, dashArray: null, opacity: 0.85 };
  }
  function restyleAll() {
    P.forEach((p) => polys[p.id].setStyle(baseStyle(p.id)));
    applyHighlights();
  }
  let highlighted = [];
  function applyHighlights() {
    highlighted.forEach((id) => polys[id].setStyle(baseStyle(id)));
    highlighted = [];
    const hl = (id, style) => { polys[id].setStyle(style); polys[id].bringToFront(); highlighted.push(id); };
    if (ui.mode === 'pick' && ui.pickCode) {
      P.forEach((p) => { if (S && owner(p.id) === ui.pickCode) hl(p.id, { color: '#ffffff', weight: 2, fillOpacity: 0.65 }); });
    }
    if (ui.mode === 'pickCustom' && ui.custom && ui.custom.claim) {
      ui.custom.claim.forEach((id) => hl(id, { color: '#ffffff', weight: 2.5, fillColor: ui.custom.color, fillOpacity: 0.75 }));
    }
    if (ui.mode === 'game' && ui.sel != null) {
      const me = S.player;
      if (owner(ui.sel) === me) {
        for (const a of P[ui.sel].adj) {
          const o = owner(a.id);
          if (o === me) hl(a.id, { color: '#34c759', weight: 2.5, dashArray: a.sea ? '6 5' : null });
          else if (atWar(me, o)) hl(a.id, { color: '#ff3b30', weight: 3, dashArray: a.sea ? '6 5' : null });
          else hl(a.id, { color: '#ffcc00', weight: 1.5, dashArray: '3 5' });
        }
      }
      hl(ui.sel, { color: '#ffffff', weight: 3.5, dashArray: null });
    }
  }

  // ------------------------------------------------------------------ overlay canvas (labels, armies, battles)
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

  const pxSize = P.map(() => 0);
  function computeSizes() {
    const z = map.getZoom();
    const scale = 256 * Math.pow(2, z) / 360; // px per degree lon at equator
    P.forEach((p) => { pxSize[p.id] = Math.sqrt(p.area) / 111.32 * scale * 0.9; });
  }
  map.on('zoomend', computeSizes);

  function drawPill(x, y, text, color, bold) {
    ctx.font = (bold ? '800 ' : '700 ') + '11px system-ui, sans-serif';
    const w = ctx.measureText(text).width + 10;
    ctx.fillStyle = 'rgba(8,14,22,0.78)';
    roundRect(x - w / 2, y - 8, w, 16, 8); ctx.fill();
    ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.stroke();
    ctx.fillStyle = '#fff'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(text, x, y + 0.5);
  }
  function roundRect(x, y, w, h, r) {
    ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }

  function render() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    if (!S || ui.zooming) return;
    const W = innerWidth, H = innerHeight;
    const pt = (p) => map.latLngToContainerPoint([p.lat, p.lon]);
    const near = new Set();
    if (ui.sel != null) { near.add(ui.sel); P[ui.sel].adj.forEach((a) => near.add(a.id)); }
    // capitals
    for (const code in S.nations) {
      const n = S.nations[code];
      if (!n.alive || n.capital == null) continue;
      const c = pt(P[n.capital]);
      if (c.x < -20 || c.y < -20 || c.x > W + 20 || c.y > H + 20) continue;
      ctx.font = '13px system-ui'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillStyle = '#ffd34d'; ctx.strokeStyle = 'rgba(0,0,0,.7)'; ctx.lineWidth = 3;
      ctx.strokeText('★', c.x, c.y - 14); ctx.fillText('★', c.x, c.y - 14);
    }
    // troop labels
    if (ui.mode === 'game' || ui.mode === 'pick' || ui.mode === 'pickCustom') {
      for (const p of P) {
        const o = owner(p.id);
        const show = near.has(p.id) || pxSize[p.id] > 26 || (isPlayer(o) && pxSize[p.id] > 16);
        if (!show) continue;
        const c = pt(p);
        if (c.x < -30 || c.y < -20 || c.x > W + 30 || c.y > H + 20) continue;
        const sp = S.prov[p.id];
        drawPill(c.x, c.y, (sp.f ? '🛡' : '') + fmtT(sp.t), N(o).color, isPlayer(o));
      }
    }
    // armies
    const now = performance.now();
    for (const a of S.armies) {
      const A = pt(P[a.from]), B = pt(P[a.to]);
      const col = N(a.o).color;
      ctx.strokeStyle = col; ctx.lineWidth = 2.5; ctx.setLineDash(a.sea ? [6, 5] : []);
      ctx.globalAlpha = 0.9;
      ctx.beginPath(); ctx.moveTo(A.x, A.y); ctx.lineTo(B.x, B.y); ctx.stroke();
      ctx.setLineDash([]);
      // arrow head
      const ang = Math.atan2(B.y - A.y, B.x - A.x);
      ctx.fillStyle = col;
      ctx.beginPath(); ctx.moveTo(B.x, B.y);
      ctx.lineTo(B.x - 11 * Math.cos(ang - 0.45), B.y - 11 * Math.sin(ang - 0.45));
      ctx.lineTo(B.x - 11 * Math.cos(ang + 0.45), B.y - 11 * Math.sin(ang + 0.45));
      ctx.closePath(); ctx.fill();
      ctx.globalAlpha = 1;
      const x = A.x + (B.x - A.x) * a.p, y = A.y + (B.y - A.y) * a.p;
      ctx.beginPath(); ctx.arc(x, y, 6, 0, 7); ctx.fillStyle = col; ctx.fill(); ctx.lineWidth = 2; ctx.strokeStyle = '#fff'; ctx.stroke();
      if (isPlayer(a.o) || near.has(a.to) || near.has(a.from)) drawPill(x, y - 15, fmtT(a.t), col, true);
    }
    // effects
    ui.effects = ui.effects.filter((e) => now - e.t0 < e.dur);
    for (const e of ui.effects) {
      const c = pt(P[e.id]);
      const k = (now - e.t0) / e.dur;
      ctx.globalAlpha = 1 - k;
      ctx.beginPath(); ctx.arc(c.x, c.y, 8 + k * 30, 0, 7);
      ctx.strokeStyle = e.color; ctx.lineWidth = 3; ctx.stroke();
      ctx.font = (18 + k * 6) + 'px system-ui'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(e.icon, c.x, c.y - 4 - k * 10);
      ctx.globalAlpha = 1;
    }
  }

  // ------------------------------------------------------------------ simulation
  function sendArmy(from, to, frac, code) {
    const sp = S.prov[from];
    const o = code || sp.o;
    if (sp.o !== o) return false;
    const link = P[from].adj.find((a) => a.id === to);
    if (!link) return false;
    const t = Math.floor(sp.t * frac * 10) / 10;
    if (t < 0.5) return false;
    const target = owner(to);
    if (target !== o && !atWar(o, target)) return false;
    if (target !== o && (sp.r || 0) > S.day) return false; // troops still regrouping after a battle
    sp.t = Math.round((sp.t - t) * 10) / 10;
    const dur = 1.2 + distKm(P[from], P[to]) / 160 + (link.sea ? 1.5 : 0);
    S.armies.push({ id: S.nextArmy++, o, from, to, t, p: 0, dur, sea: link.sea });
    return true;
  }

  function advanceArmies(days) {
    const arrived = [];
    for (const a of S.armies) {
      a.p += days / a.dur;
      if (a.p >= 1) arrived.push(a);
    }
    if (!arrived.length) return;
    S.armies = S.armies.filter((a) => a.p < 1);
    arrived.forEach(resolveArrival);
  }

  function resolveArrival(a) {
    const tp = S.prov[a.to];
    if (!N(a.o).alive) return;
    if (tp.o === a.o) { tp.t += a.t; return; }
    if (!atWar(a.o, tp.o)) {
      // war ended while marching: return home if possible
      if (S.prov[a.from].o === a.o) S.prov[a.from].t += a.t;
      return;
    }
    const r = () => 0.85 + Math.random() * 0.3;
    const att = a.t * r() * (a.sea ? 0.75 : 1);
    const def = defense(a.to) * r();
    const visible = isPlayer(a.o) || isPlayer(tp.o);
    if (att > def) {
      const survivors = Math.max(0.3, a.t * (1 - 0.75 * (def / att)));
      capture(a.to, a.o, survivors);
      if (visible || inView(a.to)) ui.effects.push({ id: a.to, t0: performance.now(), dur: 1300, color: N(a.o).color, icon: '🚩' });
    } else {
      const ratio = att / Math.max(def, 0.01);
      tp.t = Math.max(0.2, Math.round(tp.t * (1 - 0.5 * ratio) * 10) / 10);
      if (visible || inView(a.to)) ui.effects.push({ id: a.to, t0: performance.now(), dur: 1100, color: '#ffffff', icon: '💥' });
      if (isPlayer(a.o)) toast(`Attack on ${P[a.to].name} failed (${fmtT(a.t)} lost)`, 'war');
    }
  }
  function inView(id) { return map.getBounds().contains([P[id].lat, P[id].lon]); }

  function capture(id, code, troops) {
    const sp = S.prov[id];
    const prev = sp.o;
    sp.o = code; sp.t = Math.round(troops * 10) / 10; sp.f = Math.max(0, sp.f - 1); sp.r = S.day + 5;
    const w = warOf(code, prev);
    if (w) { if (w.a === prev) w.lostA++; else w.lostB++; }
    N(prev).lost++;
    polys[id].setStyle(baseStyle(id));
    if (isPlayer(code)) toast(`${N(code).flag} We captured ${P[id].name}!`);
    if (isPlayer(prev)) toast(`⚠️ ${N(code).flag} ${N(code).name} captured ${P[id].name}!`, 'war');
    const loser = N(prev);
    const left = provsOf(prev).length;
    if (left === 0) { eliminate(prev, code); }
    else if (loser.capital === id || (loser.capital != null && owner(loser.capital) !== prev)) {
      if (left <= Math.max(1, loser.start * 0.4)) capitulate(prev, code);
      else if (loser.capital === id) {
        news(`${N(code).flag} ${N(code).name} has taken ${P[id].name}, the capital of ${loser.name}!`, 'war');
        provsOf(prev).forEach((i) => { S.prov[i].t = Math.round(S.prov[i].t * 0.8 * 10) / 10; });
      }
    }
    if (ui.sel != null) applyHighlights();
  }

  function capitulate(loser, winner) {
    const ids = provsOf(loser);
    ids.forEach((i) => { S.prov[i].o = winner; S.prov[i].t = Math.round(S.prov[i].t * 0.3 * 10) / 10; polys[i].setStyle(baseStyle(i)); });
    news(`🏳️ ${N(loser).name} has capitulated to ${N(winner).flag} ${N(winner).name}!`, 'war');
    eliminate(loser, winner, true);
  }

  function eliminate(code, by, quiet) {
    const n = N(code);
    if (!n.alive) return;
    n.alive = false;
    S.wars = S.wars.filter((w) => w.a !== code && w.b !== code);
    S.armies = S.armies.filter((a) => a.o !== code);
    if (!quiet) news(`☠️ ${n.flag} ${n.name} has been wiped off the map by ${N(by).name}.`, 'war');
    if (isPlayer(code)) gameOver(false);
  }

  function declareWar(a, b, quiet) {
    if (atWar(a, b) || a === b || !N(a).alive || !N(b).alive) return false;
    S.truces = S.truces.filter((t) => !((t.a === a && t.b === b) || (t.a === b && t.b === a)));
    S.wars.push({ a, b, start: S.day, lostA: 0, lostB: 0 });
    if (!quiet) news(`⚔️ ${N(a).flag} ${N(a).name} declared war on ${N(b).flag} ${N(b).name}!`, 'war');
    restyleIfInvolved(a, b);
    return true;
  }
  function makePeace(a, b) {
    const w = warOf(a, b);
    if (!w) return;
    S.wars = S.wars.filter((x) => x !== w);
    S.truces.push({ a, b, until: S.day + 120 });
    news(`🕊️ ${N(a).flag} ${N(a).name} and ${N(b).flag} ${N(b).name} signed a peace treaty.`, 'peace');
    restyleIfInvolved(a, b);
  }
  function restyleIfInvolved(a, b) { if (isPlayer(a) || isPlayer(b)) { applyHighlights(); renderPanel(); } }

  // Would `code` accept peace with `other`?
  function acceptsPeace(code, other) {
    const w = warOf(code, other);
    if (!w) return false;
    const lostMe = w.a === code ? w.lostA : w.lostB;
    const lostThem = w.a === code ? w.lostB : w.lostA;
    const days = S.day - w.start;
    const ratio = strength(code) / Math.max(1, strength(other));
    if (lostMe > lostThem && ratio < 1.2) return true;
    if (ratio < 0.6) return true;
    if (days > 90 && lostMe >= lostThem && Math.random() < 0.5) return true;
    if (days > 200 && Math.random() < 0.3) return true;
    return false;
  }

  function tickDay() {
    S.day++;
    // economy & natural recruitment (only while below the army limit)
    const room = {};
    for (const code in S.nations) if (S.nations[code].alive) room[code] = strength(code) < armyLimit(code) * 0.75;
    for (let i = 0; i < S.prov.length; i++) {
      const sp = S.prov[i], n = N(sp.o), v = P[i].val;
      n.gold += v * 0.55;
      if (room[sp.o]) sp.t = Math.round((sp.t + 0.04 * v * n.power) * 100) / 100;
    }
    for (const code in S.nations) {
      const n = S.nations[code];
      if (!n.alive) continue;
      if (!isPlayer(code)) aiTurn(code);
      else playerAutomation(code);
    }
    if (S.day % 3 === 0) aiDiplomacy();
    checkVictory();
    if (S.day % 15 === 0) save();
  }

  // distance (in steps) from each province of `code` to its front line
  function frontDistance(code, enemies) {
    const mine = provsOf(code);
    const dist = new Map();
    const q = [];
    const hostile = (o) => (enemies.size ? enemies.has(o) : o !== code);
    for (const id of mine) {
      if (P[id].adj.some((a) => hostile(owner(a.id)))) { dist.set(id, 0); q.push(id); }
    }
    while (q.length) {
      const u = q.shift();
      for (const a of P[u].adj) {
        if (owner(a.id) === code && !dist.has(a.id)) { dist.set(a.id, dist.get(u) + 1); q.push(a.id); }
      }
    }
    return { mine, dist };
  }

  function moveTowardFront(code, enemies, frac) {
    const { mine, dist } = frontDistance(code, enemies);
    for (const id of mine) {
      const d = dist.get(id);
      if (!d) continue;
      const sp = S.prov[id];
      const keep = 1 + P[id].val;
      if (sp.t < keep + 2) continue;
      let best = null;
      for (const a of P[id].adj) {
        if (owner(a.id) !== code) continue;
        const da = dist.get(a.id);
        if (da != null && da < d && (!best || da < dist.get(best) || (da === dist.get(best) && S.prov[a.id].t < S.prov[best].t))) best = a.id;
      }
      if (best != null) sendArmy(id, best, Math.min(frac, (sp.t - keep) / sp.t), code);
    }
  }

  function planAttacks(code, enemies, aggressiveness) {
    const incoming = {};
    S.armies.forEach((a) => { if (a.o === code) incoming[a.to] = (incoming[a.to] || 0) + a.t; });
    const targets = new Map();
    for (const id of provsOf(code)) {
      for (const a of P[id].adj) {
        const o = owner(a.id);
        if (!enemies.has(o)) continue;
        if (!targets.has(a.id)) targets.set(a.id, []);
        targets.get(a.id).push({ from: id, sea: a.sea });
      }
    }
    const order = [...targets.keys()].sort((x, y) => defense(x) - defense(y));
    const used = new Set();
    for (const tid of order) {
      const need = defense(tid) * (1.25 / aggressiveness) - (incoming[tid] || 0) * 0.9;
      if (need <= 0) continue;
      const srcs = targets.get(tid).filter((s) => !used.has(s.from));
      let total = 0;
      srcs.forEach((s) => { total += S.prov[s.from].t * 0.8 * (s.sea ? 0.75 : 1); });
      if (total > need && total > 1) {
        srcs.forEach((s) => { if (sendArmy(s.from, tid, 0.8, code)) used.add(s.from); });
      }
    }
  }

  function spendGold(code, reserve) {
    const n = N(code);
    const isAI = !reserve;
    reserve = reserve || 10;
    if (n.gold < reserve + 10) return;
    const enemies = new Set(enemiesOf(code));
    const { mine, dist } = frontDistance(code, enemies);
    const front = mine.filter((id) => dist.get(id) === 0);
    const pool = front.length ? front : mine;
    if (!pool.length) return;
    // fortify the capital once in a while
    if (isAI && n.capital != null && owner(n.capital) === code && S.prov[n.capital].f < 2 && n.gold > 150 && enemies.size) {
      n.gold -= fortCost(n.capital); S.prov[n.capital].f++;
    }
    const space = armyLimit(code) - strength(code);
    if (space <= 1) return;
    const budget = Math.min((n.gold - reserve) * 0.8, space * RECRUIT_COST);
    const troops = budget / RECRUIT_COST;
    n.gold -= budget;
    // weakest frontline provinces get reinforcements first
    pool.sort((x, y) => S.prov[x].t - S.prov[y].t);
    const k = Math.min(pool.length, 4);
    for (let i = 0; i < k; i++) S.prov[pool[i]].t = Math.round((S.prov[pool[i]].t + troops / k) * 10) / 10;
  }

  function aiTurn(code) {
    const enemies = new Set(enemiesOf(code));
    if ((S.day + code.charCodeAt(0)) % 3 === 0) spendGold(code);
    if (enemies.size) {
      if ((S.day + code.charCodeAt(1)) % 3 === 0) planAttacks(code, enemies, Math.min(1.4, 0.8 + S.aggr * 0.25));
      if ((S.day + code.charCodeAt(2)) % 2 === 0) moveTowardFront(code, enemies, 0.6);
    } else if (S.day % 6 === code.charCodeAt(0) % 6) {
      moveTowardFront(code, enemies, 0.3);
    }
  }

  function playerAutomation(code) {
    const enemies = new Set(enemiesOf(code));
    if (settings.autoFront && S.day % 2 === 0) moveTowardFront(code, enemies, 0.5);
    if (settings.autoRecruit && S.day % 3 === 0) spendGold(code, 100);
    if (settings.autoAttack && enemies.size && S.day % 2 === 1) planAttacks(code, enemies, 1);
  }

  function neighborsOf(code) {
    const set = new Set();
    for (const id of provsOf(code)) for (const a of P[id].adj) { const o = owner(a.id); if (o !== code) set.add(o); }
    return set;
  }

  function aiDiplomacy() {
    const total = S.prov.length;
    for (const code in S.nations) {
      const n = S.nations[code];
      if (!n.alive || isPlayer(code)) continue;
      const enemies = enemiesOf(code);
      // peace
      for (const e of enemies) {
        const w = warOf(code, e);
        if (S.day - w.start < 30 || Math.random() > 0.25) continue;
        if (isPlayer(e)) {
          if (acceptsPeace(code, e) && Math.random() < 0.15 && !ui.modalOpen) offerPeaceToPlayer(code);
        } else if (acceptsPeace(code, e) && acceptsPeace(e, code)) makePeace(code, e);
        else if (acceptsPeace(code, e) && Math.random() < 0.3) makePeace(code, e);
      }
      // war
      if (enemies.length >= 2) continue;
      if (Math.random() > 0.012 * S.aggr) continue;
      const my = strength(code);
      let best = null, bestScore = 0;
      for (const o of neighborsOf(code)) {
        if (atWar(code, o) || truceOf(code, o) || !N(o).alive) continue;
        const their = strength(o) + enemiesOf(o).length * -0.1 * strength(o);
        let score = my / Math.max(1, their);
        const size = provsOf(o).length / total;
        if (size > 0.2) score *= 1.6; // everyone gangs up on a superpower
        if (isPlayer(o)) score *= 1.1;
        if (score > bestScore) { bestScore = score; best = o; }
      }
      const threshold = enemies.length ? 3 : 1.9;
      if (best && bestScore > threshold / Math.sqrt(S.aggr)) declareWar(code, best);
    }
  }

  function checkVictory() {
    if (S.over) return;
    const mine = provsOf(S.player).length;
    if (!S.won && mine >= S.prov.length * 0.7) { S.won = true; victory(); }
  }

  // ------------------------------------------------------------------ main loop
  let last = performance.now(), acc = 0;
  function frame(now) {
    const dt = Math.min(250, now - last);
    last = now;
    if (S && ui.mode === 'game' && S.speed > 0 && !ui.modalOpen && !S.over) {
      const days = (dt * S.speed) / DAY_MS;
      advanceArmies(days);
      acc += days;
      let n = 0;
      while (acc >= 1 && n++ < 4) { acc -= 1; tickDay(); }
      if (now - ui.lastPanel > 400) { ui.lastPanel = now; updateHud(); renderPanel(true); }
    }
    render();
    requestAnimationFrame(frame);
  }

  // ------------------------------------------------------------------ HUD & panel
  function updateHud() {
    if (!S) return;
    const me = N(S.player);
    $('hud-flag').textContent = me.flag;
    $('hud-name').textContent = me.name;
    $('hud-gold').textContent = Math.floor(me.gold);
    $('hud-troops').textContent = fmtT(strength(S.player));
    $('hud-prov').textContent = provsOf(S.player).length;
    $('hud-date').textContent = dateStr(S.day);
    document.querySelectorAll('.speed button').forEach((b) => b.classList.toggle('on', +b.dataset.speed === S.speed));
  }

  let toastQ = 0;
  function toast(msg, kind) {
    const box = $('toasts');
    const el = document.createElement('div');
    el.className = 'toast ' + (kind || '');
    el.textContent = msg;
    box.appendChild(el);
    while (box.children.length > 3) box.removeChild(box.firstChild);
    toastQ++;
    setTimeout(() => { el.classList.add('fade'); setTimeout(() => el.remove(), 600); }, 3600);
  }
  function news(msg, kind) {
    S.news.unshift({ d: S.day, m: msg });
    if (S.news.length > 60) S.news.pop();
    if (ui.mode === 'game') toast(msg, kind);
  }

  function select(id) {
    ui.sel = id;
    applyHighlights();
    renderPanel();
  }

  function onProvinceTap(id) {
    if (ui.mode === 'pick') return pickCountry(owner(id));
    if (ui.mode === 'pickCustom') return pickCustomLand(id);
    if (ui.mode !== 'game' || S.over && !S.spectate) return;
    const me = S.player;
    const sel = ui.sel;
    if (sel != null && sel !== id && owner(sel) === me && P[sel].adj.some((a) => a.id === id)) {
      const o = owner(id);
      if (o === me || atWar(me, o)) {
        if (sendArmy(sel, id, ui.sendFrac, me)) {
          if (o !== me) ui.effects.push({ id, t0: performance.now(), dur: 700, color: '#ff3b30', icon: '⚔️' });
          renderPanel();
          updateHud();
        } else if (o !== me && (S.prov[sel].r || 0) > S.day) toast(`Troops in ${P[sel].name} are regrouping (${S.prov[sel].r - S.day} days).`);
        else toast('Not enough troops to send.');
        return;
      }
    }
    select(sel === id ? null : id);
  }

  function fortCost(id) { return 40 * (S.prov[id].f + 1); }

  function renderPanel(soft) {
    const panel = $('panel');
    if (!S || ui.mode !== 'game' || ui.sel == null) { panel.classList.add('hidden'); return; }
    if (soft && panel.contains(document.activeElement) && document.activeElement.tagName === 'SELECT') return;
    const id = ui.sel, p = P[id], sp = S.prov[id], n = N(sp.o), me = S.player, mine = sp.o === me;
    const core = sp.o !== p.c && COUNTRY[p.c] ? `occupied ${COUNTRY[p.c].name}` : (p.cap && sp.o === p.c ? 'Capital' : n.name);
    const incomeStr = (p.val * 0.55).toFixed(1);
    let h = `<div class="p-head"><span class="flag">${n.flag}</span><div><div class="p-title">${esc(p.name)}${p.cap ? ' ★' : ''}</div>
      <div class="p-sub"><span class="color-dot" style="background:${n.color}"></span>${esc(n.name)} · ${esc(core)}</div></div>
      <button class="icon-btn p-close" data-act="close">✕</button></div>
      <div class="p-stats"><div>Troops<b>${fmtT(sp.t)}</b></div><div>Fortress<b>${'🛡'.repeat(sp.f) || '—'}</b></div><div>Income<b>+${incomeStr}/d</b></div></div>`;
    if (mine) h += `<div class="hint" style="margin:-4px 0 8px">Army ${fmtT(strength(me))} / limit ${fmtT(armyLimit(me))}</div>`;
    const g = Math.floor(N(me).gold);
    if (mine) {
      h += `<div class="seg">${[0.25, 0.5, 0.75, 1].map((f) => `<button data-frac="${f}" class="${ui.sendFrac === f ? 'on' : ''}">${f === 1 ? 'All' : f * 100 + '%'}</button>`).join('')}</div>
        <div class="p-row">
          <button data-act="recruit" data-n="5" ${g < 5 * RECRUIT_COST ? 'disabled' : ''}>+5k 🪖 <small>(${5 * RECRUIT_COST}💰)</small></button>
          <button data-act="recruit" data-n="25" ${g < 25 * RECRUIT_COST ? 'disabled' : ''}>+25k 🪖 <small>(${25 * RECRUIT_COST}💰)</small></button>
          <button data-act="fort" ${sp.f >= 3 || g < fortCost(id) ? 'disabled' : ''}>Fortify <small>(${sp.f >= 3 ? 'max' : fortCost(id) + '💰'})</small></button>
        </div>
        <div class="hint">Tap a <b style="color:#ff3b30">red</b> neighbor to attack or a <b style="color:#34c759">green</b> one to move troops (dashed = by sea). <b style="color:#ffcc00">Yellow</b> neighbors need a war declaration first.</div>`;
    } else if (atWar(me, sp.o)) {
      const attackers = p.adj.filter((a) => owner(a.id) === me);
      const avail = attackers.reduce((s, a) => s + S.prov[a.id].t * 0.75, 0);
      h += `<div class="p-row"><button class="danger" data-act="allin" ${attackers.length ? '' : 'disabled'}>⚔️ Attack from all neighbors (${fmtT(avail)})</button>
        <button data-act="peace">🕊️ Offer peace</button></div>
        <div class="hint">Enemy defense: ~${fmtT(defense(id))} effective (forts & capitals defend better).</div>`;
    } else {
      const tr = truceOf(me, sp.o);
      h += `<div class="p-row"><button class="danger" data-act="war" ${tr ? 'disabled' : ''}>⚔️ Declare war on ${esc(n.name)}</button></div>
        <div class="hint">${tr ? `Truce in effect for ${tr.until - S.day} more days.` : `${esc(n.name)}: ${provsOf(sp.o).length} provinces, ${fmtT(strength(sp.o))} troops.`}</div>`;
    }
    panel.innerHTML = h;
    panel.classList.remove('hidden');
  }

  $('panel').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    const id = ui.sel, me = S.player;
    if (b.dataset.frac) { ui.sendFrac = +b.dataset.frac; renderPanel(); return; }
    switch (b.dataset.act) {
      case 'close': select(null); break;
      case 'recruit': {
        const k = +b.dataset.n, cost = k * RECRUIT_COST;
        if (N(me).gold >= cost && strength(me) + k <= armyLimit(me)) { N(me).gold -= cost; S.prov[id].t += k; }
        else if (N(me).gold >= cost) toast('Army limit reached — conquer more land to raise it.');
        break;
      }
      case 'fort':
        if (S.prov[id].f < 3 && N(me).gold >= fortCost(id)) { N(me).gold -= fortCost(id); S.prov[id].f++; }
        break;
      case 'war': confirmWar(owner(id)); return;
      case 'peace': playerOffersPeace(owner(id)); return;
      case 'allin': {
        let sent = 0;
        P[id].adj.forEach((a) => { if (owner(a.id) === me && sendArmy(a.id, id, 0.75, me)) sent++; });
        if (sent) ui.effects.push({ id, t0: performance.now(), dur: 700, color: '#ff3b30', icon: '⚔️' });
        break;
      }
    }
    updateHud(); renderPanel();
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

  function confirmWar(code) {
    const n = N(code);
    openModal(`<h2>⚔️ Declare war?</h2><p>${n.flag} <b>${esc(n.name)}</b> has ${provsOf(code).length} provinces and about <b>${fmtT(strength(code))}</b> troops.
      You have ${fmtT(strength(S.player))}.</p>
      <div class="row"><button class="big ghost" data-a="no">Cancel</button><button class="big primary" data-a="yes">Declare war</button></div>`, (b) => {
      if (b.dataset.a === 'yes') declareWar(S.player, code);
      closeModal(); renderPanel();
    });
  }

  function playerOffersPeace(code) {
    const ok = acceptsPeace(code, S.player);
    if (ok) makePeace(S.player, code);
    else toast(`${N(code).flag} ${N(code).name} rejected your peace offer.`, 'war');
    if (ui.modalOpen) diplomacy();
    renderPanel();
  }

  function offerPeaceToPlayer(code) {
    const n = N(code);
    openModal(`<h2>🕊️ Peace offer</h2><p>${n.flag} <b>${esc(n.name)}</b> offers you a white peace. Every province stays with whoever holds it now, and a 120-day truce begins.</p>
      <div class="row"><button class="big ghost" data-a="no">Refuse</button><button class="big primary" data-a="yes">Accept</button></div>`, (b) => {
      if (b.dataset.a === 'yes') makePeace(code, S.player);
      closeModal();
    });
  }

  function diplomacy() {
    const me = S.player;
    const list = Object.values(S.nations).filter((n) => n.alive)
      .map((n) => ({ n, c: provsOf(n.code).length, s: strength(n.code) }))
      .sort((a, b) => (isPlayer(b.n.code) - isPlayer(a.n.code)) || (atWar(me, b.n.code) - atWar(me, a.n.code)) || b.c - a.c);
    const rows = list.map(({ n, c, s }) => {
      let right = '';
      if (isPlayer(n.code)) right = '<span class="tag you">YOU</span>';
      else if (atWar(me, n.code)) right = `<span class="tag war">WAR</span><button class="ok" data-peace="${n.code}">Peace</button>`;
      else if (truceOf(me, n.code)) right = `<span class="tag truce">TRUCE ${truceOf(me, n.code).until - S.day}d</span>`;
      else right = `<button class="danger" data-war="${n.code}">War</button>`;
      const wars = enemiesOf(n.code).filter((e) => !isPlayer(e)).map((e) => N(e).flag).join('');
      return `<div class="drow"><span class="flag">${n.flag}</span><div class="dn"><b><span class="color-dot" style="background:${n.color}"></span>${esc(n.name)}</b>
        <span>${c} prov · ${fmtT(s)} troops${wars ? ' · at war with ' + wars : ''}</span></div>${right}</div>`;
    }).join('');
    openModal(`<h2>🤝 Diplomacy</h2><div class="dlist">${rows}</div><div class="row"><button class="big" data-close>Close</button></div>`, (b) => {
      if (b.dataset.close != null) return closeModal();
      if (b.dataset.war) { closeModal(); confirmWar(b.dataset.war); }
      if (b.dataset.peace) playerOffersPeace(b.dataset.peace);
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
      ${chk('autoFront', 'Generals move idle troops to the front')}
      ${chk('autoRecruit', 'Generals recruit troops with spare gold (keeps 100💰)')}
      ${chk('autoAttack', 'Generals launch attacks automatically')}
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
      <li>Pick a country — or found your own nation by breaking away from one.</li>
      <li>Each province earns 💰 gold and slowly raises 🪖 troops. Spend gold to recruit troops or build 🛡 forts.</li>
      <li>Declare war from <b>Diplomacy</b> or by tapping a foreign province.</li>
      <li>Tap one of your provinces, then tap a <b style="color:#ff3b30">red</b> neighbor to attack. Choose how many troops to send (25%–All).</li>
      <li>Dashed lines are sea crossings: slower and 25% weaker.</li>
      <li>Take an enemy capital ★ while they've lost half their land and the whole country surrenders to you.</li>
      <li>Control 70% of Europe to win. Lose every province and it's game over.</li>
      <li>Pinch to zoom; the game saves automatically.</li></ol>
      <div class="row"><button class="big primary" data-close>Got it</button></div>`, () => {
      closeModal();
      if (ui.mode === 'title') $('screen-title').classList.remove('hidden');
    });
  }

  function victory() {
    openModal(`<h2>👑 Europe is yours!</h2><p>${N(S.player).flag} <b>${esc(N(S.player).name)}</b> controls ${provsOf(S.player).length} of ${S.prov.length} provinces on ${dateStr(S.day)}.</p>
      <div class="row"><button class="big ghost" data-a="quit">Main menu</button><button class="big primary" data-a="go">Keep conquering</button></div>`, (b) => {
      closeModal();
      if (b.dataset.a === 'quit') { save(); toTitle(); }
    });
  }

  function gameOver() {
    S.over = true;
    try { localStorage.removeItem('ia_save'); } catch (e) { /* ignore */ }
    openModal(`<h2>💀 Defeat</h2><p>${N(S.player).flag} <b>${esc(N(S.player).name)}</b> has fallen on ${dateStr(S.day)}. History is written by the victors.</p>
      <div class="row"><button class="big ghost" data-a="watch">Watch the world</button><button class="big primary" data-a="quit">Main menu</button></div>`, (b) => {
      closeModal();
      if (b.dataset.a === 'quit') toTitle();
      else { S.over = false; S.spectate = true; }
    });
  }

  // ------------------------------------------------------------------ title / pick flow
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

  let titleDrift = null;
  function toTitle() {
    ui.mode = 'title'; ui.sel = null; S = null;
    hideScreens();
    $('hud').classList.add('hidden');
    $('screen-title').classList.remove('hidden');
    $('btn-continue').classList.toggle('hidden', !hasSave());
    restyleAll();
    map.flyToBounds([[40, -8], [62, 35]], { duration: 0.8 });
    clearInterval(titleDrift);
    let ph = 0;
    titleDrift = setInterval(() => { if (ui.mode === 'title') map.panBy([Math.sin((ph += 0.004)) * 0.7, 0], { animate: false }); }, 50);
  }

  function opts() { return { scenario: $('opt-scenario').value, aggr: +$('opt-aggr').value }; }

  function startPick() {
    newGame(opts());
    ui.mode = 'pick'; ui.pickCode = null;
    hideScreens();
    $('screen-pick').classList.remove('hidden');
    $('pick-title').textContent = 'Choose your country';
    $('pick-hint').textContent = 'Tap a country on the map or pick from the list';
    const list = Object.values(S.nations).sort((a, b) => a.name.localeCompare(b.name));
    $('pick-list').innerHTML = list.map((n) => `<button data-code="${n.code}">${n.flag} ${esc(n.name)}</button>`).join('');
    restyleAll();
  }
  $('pick-list').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-code]');
    if (b) pickCountry(b.dataset.code, true);
  });

  function pickCountry(code, fly) {
    ui.pickCode = code;
    applyHighlights();
    document.querySelectorAll('#pick-list button').forEach((b) => b.classList.toggle('on', b.dataset.code === code));
    const n = N(code);
    const ids = provsOf(code);
    if (fly && ids.length) map.flyToBounds(L.latLngBounds(ids.map((i) => [P[i].lat, P[i].lon])).pad(0.6), { duration: 0.6, maxZoom: 6 });
    const wars = enemiesOf(code).map((e) => N(e).flag + ' ' + N(e).name).join(', ');
    $('pick-confirm').innerHTML = `<div class="p-head"><span class="flag">${n.flag}</span><div><div class="p-title">${esc(n.name)}</div>
      <div class="p-sub">${ids.length} provinces · ${fmtT(strength(code))} troops${wars ? ' · at war with ' + esc(wars) : ''}</div></div></div>
      <div class="p-row" style="margin-top:12px"><button class="primary" id="pick-go">Play as ${esc(n.name)} ›</button></div>`;
    $('pick-confirm').classList.remove('hidden');
    $('pick-go').onclick = () => beginGame(code);
  }

  function beginGame(code) {
    S.player = code;
    hideScreens();
    clearInterval(titleDrift);
    ui.mode = 'game'; ui.sel = null; ui.pickCode = null;
    $('hud').classList.remove('hidden');
    restyleAll(); updateHud(); renderPanel();
    const ids = provsOf(code);
    if (ids.length) map.flyToBounds(L.latLngBounds(ids.map((i) => [P[i].lat, P[i].lon])).pad(0.9), { duration: 0.8, maxZoom: 6 });
    S.speed = 0;
    toast(`${N(code).flag} You lead ${N(code).name}. The game is paused — press 1× when ready, commander!`);
    save();
  }

  // custom nation
  const SWATCHES = ['#f5b83d', '#ff6b00', '#e0307a', '#9b4dff', '#00c2a8', '#28c840', '#00a2ff', '#ffffff', '#111827', '#8b5a2b'];
  const EMBLEMS = ['🦅', '🐻', '🦁', '🐺', '🐉', '👑', '⚔️', '🔥', '⭐', '🌙', '🍊', '🛡️'];
  function startCustom() {
    ui.custom = ui.custom || { color: SWATCHES[0], flag: EMBLEMS[10] };
    hideScreens();
    $('screen-custom').classList.remove('hidden');
    $('cn-colors').innerHTML = SWATCHES.map((c) => `<button data-c="${c}" style="background:${c}" class="${ui.custom.color === c ? 'on' : ''}"></button>`).join('');
    $('cn-emblems').innerHTML = EMBLEMS.map((f) => `<button data-f="${f}" class="${ui.custom.flag === f ? 'on' : ''}">${f}</button>`).join('');
  }
  $('cn-colors').addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    ui.custom.color = b.dataset.c; startCustom();
  });
  $('cn-emblems').addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    ui.custom.flag = b.dataset.f; startCustom();
  });
  $('cn-next').onclick = () => {
    ui.custom.name = ($('cn-name').value || 'New Nation').trim().slice(0, 24);
    ui.custom.war = $('cn-war').checked;
    ui.custom.claim = null;
    newGame(opts());
    ui.mode = 'pickCustom';
    hideScreens();
    $('screen-pick').classList.remove('hidden');
    $('pick-title').textContent = `${ui.custom.flag} ${ui.custom.name}`;
    $('pick-hint').textContent = 'Tap the province where your nation will rise';
    $('pick-list').innerHTML = '';
    restyleAll();
  };

  function pickCustomLand(id) {
    const from = owner(id);
    const claim = [id];
    const extra = P[id].adj.filter((a) => !a.sea && owner(a.id) === from && !P[a.id].cap).map((a) => a.id)
      .sort((x, y) => P[y].val - P[x].val).slice(0, 2);
    claim.push(...extra);
    ui.custom.claim = claim;
    ui.custom.from = from;
    applyHighlights();
    const c = ui.custom;
    const total = claim.reduce((s, i) => s + S.prov[i].t, 0) * 1.4;
    $('pick-confirm').innerHTML = `<div class="p-head"><span class="flag">${c.flag}</span><div><div class="p-title">${esc(c.name)}</div>
      <div class="p-sub">${claim.length} provinces around ${esc(P[id].name)} · ~${fmtT(total)} troops · breaking away from ${N(from).flag} ${esc(N(from).name)}</div></div></div>
      <div class="p-row" style="margin-top:12px"><button class="primary" id="pick-go">Found ${esc(c.name)} ›</button></div>`;
    $('pick-confirm').classList.remove('hidden');
    $('pick-go').onclick = foundNation;
  }

  function foundNation() {
    const c = ui.custom;
    const code = 'CUS';
    S.nations[code] = { code, name: c.name, color: c.color, flag: c.flag, power: 1.2, gold: 150, alive: true, start: c.claim.length, capital: c.claim[0], lost: 0, custom: true };
    for (const id of c.claim) {
      const prev = S.prov[id].o;
      S.nations[prev].start--;
      if (S.nations[prev].capital === id) S.nations[prev].capital = null;
      S.prov[id].o = code;
      S.prov[id].t = Math.round(S.prov[id].t * 1.4 * 10) / 10;
    }
    S.prov[c.claim[0]].f = Math.max(1, S.prov[c.claim[0]].f);
    if (c.war) declareWar(c.from, code, true);
    beginGame(code);
    news(`${c.flag} ${c.name} has declared independence from ${N(c.from).name}!`, c.war ? 'war' : '');
  }

  // ------------------------------------------------------------------ save / load
  function hasSave() { try { return !!localStorage.getItem('ia_save'); } catch (e) { return false; } }
  function save() {
    if (!S || !S.player || S.over) return;
    try { localStorage.setItem('ia_save', JSON.stringify(S)); } catch (e) { /* storage full or disabled */ }
  }
  function load() {
    try {
      const s = JSON.parse(localStorage.getItem('ia_save'));
      if (!s || s.prov.length !== P.length) return false;
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
    hideScreens();
    clearInterval(titleDrift);
    ui.mode = 'game'; ui.sel = null;
    $('hud').classList.remove('hidden');
    restyleAll(); updateHud();
    const ids = provsOf(S.player);
    if (ids.length) map.flyToBounds(L.latLngBounds(ids.map((i) => [P[i].lat, P[i].lon])).pad(0.9), { duration: 0.8, maxZoom: 6 });
  };
  document.querySelectorAll('[data-back]').forEach((b) => { b.onclick = () => toTitle(); });
  document.querySelectorAll('.speed button').forEach((b) => { b.onclick = () => { S.speed = +b.dataset.speed; updateHud(); }; });
  $('btn-menu').onclick = gameMenu;
  $('btn-diplo').onclick = diplomacy;
  $('btn-news').onclick = newsModal;
  $('btn-nation').onclick = () => {
    const ids = provsOf(S.player);
    if (ids.length) map.flyToBounds(L.latLngBounds(ids.map((i) => [P[i].lat, P[i].lon])).pad(0.6), { duration: 0.6, maxZoom: 7 });
  };
  document.addEventListener('visibilitychange', () => { if (document.hidden) save(); });

  // Android back button: returns true when handled
  window.IA = {
    save,
    onBack() {
      if (ui.modalOpen) { closeModal(); return true; }
      if (ui.mode === 'game') { if (ui.sel != null) { select(null); return true; } gameMenu(); return true; }
      if (ui.mode === 'pick' || ui.mode === 'pickCustom' || !$('screen-custom').classList.contains('hidden')) { toTitle(); return true; }
      return false;
    },
    // test hooks
    _state: () => S, _P: P, _xy: (id) => map.latLngToContainerPoint([P[id].lat, P[id].lon]), _map: map, _sim(days) { for (let i = 0; i < days; i++) { advanceArmies(1); tickDay(); } },
  };

  resize();
  computeSizes();
  toTitle();
  requestAnimationFrame(frame);
})();
