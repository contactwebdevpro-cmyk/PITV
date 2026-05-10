'use strict';
const http  = require('http');
const https = require('https');
const fs    = require('fs');
const path  = require('path');
const url   = require('url');

const PORT     = process.env.PORT || 8080;
const PITV_DIR = __dirname;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js':   'application/javascript; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.m3u':  'application/x-mpegurl; charset=utf-8',
  '.m3u8': 'application/x-mpegurl; charset=utf-8',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.svg':  'image/svg+xml',
  '.ico':  'image/x-icon',
};

// ─── PROXY M3U (résout le problème CORS) ────────────────────────────────────
// Le Pi fetch les URLs en Node.js → pas de CORS. Le navigateur appelle
// /api/proxy?url=https://... et récupère le contenu directement.
function proxyFetch(targetUrl, res) {
  const parsed = url.parse(targetUrl);
  const lib    = parsed.protocol === 'https:' ? https : http;

  const options = {
    hostname: parsed.hostname,
    port:     parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
    path:     parsed.path,
    method:   'GET',
    headers: {
      'User-Agent': 'Mozilla/5.0 PiTV/2.0',
      'Accept':     '*/*',
    },
    timeout: 25000,
  };

  const req = lib.request(options, (upstream) => {
    // Suit les redirections (max 3)
    if ([301, 302, 303, 307, 308].includes(upstream.statusCode) && upstream.headers.location) {
      const redirect = upstream.headers.location.startsWith('http')
        ? upstream.headers.location
        : `${parsed.protocol}//${parsed.hostname}${upstream.headers.location}`;
      proxyFetch(redirect, res);
      return;
    }

    if (upstream.statusCode !== 200) {
      res.writeHead(upstream.statusCode, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ error: `Upstream HTTP ${upstream.statusCode}` }));
    }

    res.writeHead(200, {
      'Content-Type':                'text/plain; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control':               'public, max-age=300',
    });

    upstream.pipe(res);
  });

  req.on('timeout', () => {
    req.destroy();
    if (!res.headersSent) {
      res.writeHead(504, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Timeout' }));
    }
  });

  req.on('error', (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message }));
    }
  });

  req.end();
}

// ─── SERVEUR HTTP ─────────────────────────────────────────────────────────────
http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  const pathname = parsed.pathname;

  // CORS preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin':  '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    return res.end();
  }

  // ── /api/status ───────────────────────────────────────────────────────────
  if (pathname === '/api/status') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({
      status:    'ok',
      uptime:    process.uptime(),
      version:   '2.1.0',
      nodeVersion: process.version,
    }));
  }

  // ── /api/proxy?url=... ────────────────────────────────────────────────────
  // Proxy côté serveur : résout les blocages CORS du navigateur
  if (pathname === '/api/proxy') {
    const targetUrl = parsed.query.url;
    if (!targetUrl || !targetUrl.startsWith('http')) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ error: 'Paramètre url manquant ou invalide' }));
    }
    console.log(`[proxy] ${targetUrl}`);
    return proxyFetch(targetUrl, res);
  }

  // ── Fichiers statiques ────────────────────────────────────────────────────
  let filePath = path.join(PITV_DIR, 'public',
    pathname === '/' ? 'index.html' : pathname
  );

  // Fallback SPA → index.html
  if (!fs.existsSync(filePath)) {
    filePath = path.join(PITV_DIR, 'public', 'index.html');
  }

  const ext  = path.extname(filePath);
  const mime = MIME[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); return res.end('Not found'); }
    res.writeHead(200, { 'Content-Type': mime });
    res.end(data);
  });

}).listen(PORT, '0.0.0.0', () => {
  console.log(`✓ PiTV OS en ligne → http://0.0.0.0:${PORT}`);
  console.log(`  Proxy M3U actif : http://0.0.0.0:${PORT}/api/proxy?url=<URL>`);
});
