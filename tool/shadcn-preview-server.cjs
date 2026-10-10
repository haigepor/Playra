const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../build/shadcn-preview');
const port = Number(process.env.SHADCN_PREVIEW_PORT || 8932);
const types = {'.html':'text/html; charset=utf-8', '.js':'text/javascript',
  '.json':'application/json', '.wasm':'application/wasm', '.png':'image/png',
  '.svg':'image/svg+xml', '.ttf':'font/ttf', '.woff2':'font/woff2'};
http.createServer((req, res) => {
  try {
    const url = new URL(req.url, 'http://127.0.0.1');
    const file = path.resolve(root, '.' + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
    if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
    fs.stat(file, (error, stat) => {
      if (error || !stat.isFile()) { res.writeHead(404).end(); return; }
      res.writeHead(200, {'Content-Type':types[path.extname(file)] || 'application/octet-stream',
        'Cache-Control':'no-store'});
      fs.createReadStream(file).pipe(res);
    });
  } catch { res.writeHead(400).end(); }
}).listen(port, '127.0.0.1', () => console.log(`Shadcn gallery: http://127.0.0.1:${port}`));
