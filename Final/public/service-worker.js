/* Service worker — CTI Fabrício Borges
 * Guarda em cache SOMENTE arquivos estáticos públicos (interface, ícones, biblioteca e fontes).
 * Nunca intercepta nem guarda: Supabase (login, tokens, dados), YouTube, imagens de terceiros,
 * requisições com Authorization e qualquer método diferente de GET.
 * "__BUILD_ID__" é trocado a cada deploy pelo build.js (na Netlify). */
const VERSION = "__BUILD_ID__";
const PREFIX = "cti-fb-static-";
const CACHE = PREFIX + VERSION;
const SCOPE = self.registration.scope;
const INDEX = new URL("index.html", SCOPE).href;

const PRECACHE_LOCAL = [
  INDEX, "config.js", "manifest.webmanifest",
  "icons/icon-192.png", "icons/icon-512.png",
  "icons/icon-maskable-192.png", "icons/icon-maskable-512.png",
  "icons/apple-touch-icon.png", "icons/favicon-32.png"
];
// Recursos públicos de terceiros necessários para abrir a interface (melhor esforço).
const PRECACHE_CDN = [
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js",
  "https://fonts.googleapis.com/css2?family=Barlow:wght@400;500;600&family=Barlow+Condensed:ital,wght@0,600;1,700;1,800&display=swap"
];

const isCdn = u =>
  (u.hostname === "cdn.jsdelivr.net" && u.pathname.startsWith("/npm/@supabase/")) ||
  u.hostname === "fonts.googleapis.com" || u.hostname === "fonts.gstatic.com";
const cdnReq = url => new Request(url, { mode: "cors", credentials: "omit" });
const okToStore = r => r && r.ok && (r.type === "basic" || r.type === "cors");

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.all(PRECACHE_LOCAL.map(async p => {
      try {
        const req = new Request(new URL(p, SCOPE).href, { cache: "reload" });
        const res = await fetch(req);
        if (okToStore(res)) await cache.put(req, res);
      } catch (e) { /* tenta de novo no uso normal */ }
    }));
    await Promise.all(PRECACHE_CDN.map(async u => {
      try { const res = await fetch(cdnReq(u)); if (okToStore(res)) await cache.put(u, res); } catch (e) {}
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k.startsWith(PREFIX) && k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

const OFFLINE_HTML = `<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Sem conexão</title>
<body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#09090b;color:#f3f3f5;font:16px/1.5 system-ui,sans-serif;text-align:center;padding:24px">
<div><h1 style="font-size:1.5rem;margin:0 0 8px">Sem conexão</h1><p style="color:#9b9ba7;margin:0 0 18px">Abra o aplicativo uma vez com internet para usá-lo depois sem conexão.</p>
<button onclick="location.reload()" style="font:inherit;padding:12px 20px;border-radius:10px;border:0;background:#e8581f;color:#fff;font-weight:600;min-height:44px">Tentar novamente</button></div></body></html>`;

function withTimeout(p, ms) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error("timeout")), ms);
    p.then(v => { clearTimeout(t); resolve(v); }, e => { clearTimeout(t); reject(e); });
  });
}

async function handleNavigation(request) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(INDEX);
  try {
    // Com cópia local, espera no máximo 5 s pela rede (evita tela travada com sinal ruim).
    const res = await (cached ? withTimeout(fetch(request), 5000) : fetch(request));
    const u = new URL(request.url);
    const isIndex = u.pathname === new URL(SCOPE).pathname || u.pathname === new URL(INDEX).pathname;
    // Só o HTML estático é guardado, sempre sob uma chave fixa (sem ?code=, tokens etc. da URL).
    if (isIndex && okToStore(res)) cache.put(INDEX, res.clone()).catch(() => {});
    return res;
  } catch (e) {
    return cached || new Response(OFFLINE_HTML, { status: 503, headers: { "Content-Type": "text/html; charset=utf-8" } });
  }
}

async function networkFirst(request) {
  const cache = await caches.open(CACHE);
  try {
    const res = await fetch(request);
    if (okToStore(res)) cache.put(request, res.clone()).catch(() => {});
    return res;
  } catch (e) {
    const hit = await cache.match(request, { ignoreSearch: true });
    if (hit) return hit;
    throw e;
  }
}

async function cacheFirst(request, cdn) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(cdn ? request.url : request);
  if (hit) return hit;
  const res = await fetch(cdn ? cdnReq(request.url) : request);
  if (okToStore(res)) cache.put(cdn ? request.url : request, res.clone()).catch(() => {});
  return res;
}

async function staleWhileRevalidate(request, cdn) {
  const cache = await caches.open(CACHE);
  const key = cdn ? request.url : request;
  const hit = await cache.match(key);
  const update = fetch(cdn ? cdnReq(request.url) : request)
    .then(res => { if (okToStore(res)) cache.put(key, res.clone()).catch(() => {}); return res; })
    .catch(() => null);
  if (hit) { update.catch(() => {}); return hit; }
  const res = await update;
  if (res) return res;
  throw new Error("offline");
}

self.addEventListener("fetch", event => {
  const req = event.request;
  if (req.method !== "GET" || req.headers.has("authorization") || req.headers.has("range")) return;
  const url = new URL(req.url);

  if (req.mode === "navigate") {
    if (url.origin === location.origin) event.respondWith(handleNavigation(req));
    return;
  }

  if (url.origin === location.origin) {
    if (url.pathname.endsWith("/service-worker.js")) return;
    if (url.pathname.endsWith("/config.js")) { event.respondWith(networkFirst(req)); return; }
    if (/\.(?:png|webmanifest|webp|svg|ico|woff2?)$/.test(url.pathname)) { event.respondWith(staleWhileRevalidate(req, false)); return; }
    return; // qualquer outra coisa segue direto para a rede
  }

  if (isCdn(url)) {
    if (url.hostname === "fonts.googleapis.com") event.respondWith(staleWhileRevalidate(req, true));
    else event.respondWith(cacheFirst(req, true)); // jsdelivr (versão fixa) e fontes gstatic
  }
  // Supabase, YouTube etc.: não interceptado.
});
