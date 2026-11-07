// Biinge light theme, derived from the dark tokens.
// Any subtree under [data-theme="light"] is re-coloured from the dark literals the prototypes use.
// Subtrees under [data-media] (scrims, controls and badges that sit on artwork or video) keep their dark values.
(function () {
  if (window.BiingeTheme) return;

  // Named tokens: dark value -> light value. Neutrals not listed here are derived by the rules in mapColor().
  const TOKENS = [
    ['bg', '#101014', '#f3f3f1'],
    ['surface', '#17171d', '#eaeae7'],
    ['surface-raised', '#1b1b20', '#ffffff'],
    ['placeholder', '#282828', '#deded9'],
    ['text', '#f4f4f2', '#16161a'],
    ['text-secondary', '#91919a', '#62626a'],
    ['text-tertiary', '#64646d', '#8c8c94'],
    ['fill (white α)', 'rgba(255,255,255,α)', 'rgba(0,0,0,0.75α)'],
    ['glass', 'rgba(36,36,42,.5)', 'rgba(255,255,255,.62)'],
    ['primary pill', '#f4f4f2 on #101014', '#16161a on #f3f3f1'],
    ['watched', '#34c46f', '#1f9a52'],
    ['new / rating', '#eec01e', '#a77d00'],
    ['error', '#ff8a8d', '#c8383d'],
  ];

  const hex = h => { h = h.replace('#', ''); if (h.length === 3) h = h.split('').map(c => c + c).join(''); return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]; };
  const FIXED = new Map([
    ['16,16,20', [243, 243, 241]], ['23,23,29', [234, 234, 231]], ['27,27,32', [255, 255, 255]], ['40,40,40', [222, 222, 217]],
    ['244,244,242', [22, 22, 26]], ['255,255,255', [22, 22, 26]], ['145,145,154', [98, 98, 106]], ['100,100,109', [140, 140, 148]],
    ['36,36,42', [255, 255, 255]], ['40,40,46', [255, 255, 255]], ['30,30,36', [255, 255, 255]], ['44,44,50', [255, 255, 255]], ['34,34,40', [255, 255, 255]], ['60,60,68', [255, 255, 255]],
    ['52,196,111', [31, 154, 82]], ['238,192,30', [167, 125, 0]], ['255,138,141', [200, 56, 61]], ['255,107,107', [200, 56, 61]],
    ['42,42,48', [206, 206, 210]], ['58,58,66', [186, 186, 192]],
  ]);
  const GLASS = new Set(['36,36,42', '40,40,46', '30,30,36', '44,44,50', '34,34,40', '60,60,68', '28,28,34']);

  function mapColor(r, g, b, a, kind) {
    const key = `${r},${g},${b}`;
    const max = Math.max(r, g, b), min = Math.min(r, g, b), L = (r + g + b) / 3;
    const neutral = max - min <= 14;
    if (r === 0 && g === 0 && b === 0) return kind === 'shadow' ? [0, 0, 0, a * 0.45] : kind === 'fill' && a < .5 ? [0, 0, 0, a * 0.3] : [0, 0, 0, a];
    if (GLASS.has(key) && a < 1 && kind !== 'text') return [255, 255, 255, a >= .8 ? .97 : Math.min(.78, a + .15)];
    if (neutral && L > 225 && a < .95 && kind !== 'text') return [0, 0, 0, a * (kind === 'shadow' ? .5 : .75)];
    if (FIXED.has(key)) { const c = FIXED.get(key); return [c[0], c[1], c[2], a]; }
    if (neutral) {
      const L2 = L < 52 ? 251 - L * 0.6 : 255 - L;
      return [r - L + L2, g - L + L2, b - L + L2, a].map((v, i) => i < 3 ? Math.max(0, Math.min(255, Math.round(v))) : v);
    }
    if (kind === 'text' && L > 150) return [Math.round(r * .72), Math.round(g * .72), Math.round(b * .72), a];
    return [r, g, b, a];
  }

  const COLOR_RE = /rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)(?:[,\s/]+([\d.]+))?\s*\)|#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b/g;
  function mapValue(v, kind) {
    return v.replace(COLOR_RE, (m, r, g, b, a, h) => {
      let c = h ? hex(h).concat(1) : [+r, +g, +b, a == null ? 1 : +a];
      const o = mapColor(c[0], c[1], c[2], c[3], kind);
      return o[3] >= 1 ? `rgb(${o[0]}, ${o[1]}, ${o[2]})` : `rgba(${o[0]}, ${o[1]}, ${o[2]}, ${+o[3].toFixed(3)})`;
    });
  }
  const kindOf = p => p === 'color' || p === '-webkit-text-fill-color' || p === 'caret-color' ? 'text' : /shadow/.test(p) ? 'shadow' : 'fill';
  const PROPS = /^(color|background|background-color|background-image|border|border-.*color|outline-color|box-shadow|text-shadow|fill|stroke|-webkit-text-fill-color|filter|text-decoration-color)$/;

  const written = new WeakMap();
  function isLight(el) { const t = el.closest('[data-theme]'); return !!t && t.getAttribute('data-theme') === 'light'; }
  function isMedia(el) { const m = el.closest('[data-media],[data-theme]'); return !!m && m.hasAttribute('data-media'); }

  function processEl(el) {
    if (!el.style) return;
    if (el.getAttribute && el.getAttribute('data-theme') === 'light' && !el.hasAttribute('data-media') && el.parentElement && el.parentElement.closest('[data-media]') && !el.style.color) el.style.color = '#f4f4f2';
    if (!el.style.length) return;
    const light = isLight(el) && !isMedia(el);
    let rec = written.get(el);
    if (!light) {
      if (rec) { for (const p in rec.orig) el.style.setProperty(p, rec.orig[p]); written.delete(el); }
      return;
    }
    if (!rec) { rec = { out: {}, orig: {} }; written.set(el, rec); }
    for (let i = 0; i < el.style.length; i++) {
      const p = el.style[i];
      if (!PROPS.test(p)) continue;
      const v = el.style.getPropertyValue(p);
      if (rec.out[p] === v) continue;
      let nv;
      const ov = p === 'filter' ? el.getAttribute('data-light-filter') : /^background(-image)?$/.test(p) ? el.getAttribute('data-light-background') : null;
      if (ov) { rec.orig[p] = v; el.style.setProperty(p === 'background-image' ? 'background' : p, ov); rec.out[p] = el.style.getPropertyValue(p); continue; }
      if (p === 'filter') nv = /blur\(/.test(v) ? v.replace(/brightness\(([\d.]+)\)/, (m, x) => +x < 1 ? 'brightness(1.12)' : m) : v;
      else nv = mapValue(v, kindOf(p));
      rec.orig[p] = v;
      if (nv !== v) el.style.setProperty(p, nv, el.style.getPropertyPriority(p));
      rec.out[p] = el.style.getPropertyValue(p);
    }
  }
  function processTree(root) {
    if (root.nodeType !== 1) return;
    processEl(root);
    root.querySelectorAll('[style]').forEach(processEl);
  }
  let queued = new Set(), raf = 0;
  function flush() { raf = 0; const q = queued; queued = new Set(); q.forEach(processTree); }
  function queue(n) { if (n && n.nodeType === 1) { queued.add(n); if (!raf) raf = requestAnimationFrame(flush); } }

  function start() {
    processTree(document.body);
    new MutationObserver(list => {
      for (const m of list) {
        if (m.type === 'childList') m.addedNodes.forEach(queue);
        else if (m.attributeName === 'data-theme' || m.attributeName === 'data-media') { if (m.target.getAttribute('data-theme') !== 'light' && written.has(m.target) && !('color' in written.get(m.target).orig)) m.target.style.removeProperty('color'); queue(m.target); }
        else if (m.attributeName === 'style') { const rec = written.get(m.target); if (!rec || isLight(m.target)) processEl(m.target); }
      }
    }).observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ['style', 'data-theme', 'data-media'] });
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
  window.BiingeTheme = { TOKENS, mapValue };
})();
