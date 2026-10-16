const fs = require('node:fs');
const { stat } = require('node:fs/promises');
const { pipeline } = require('node:stream/promises');

// Flutter 的入口和资产名可跨版本复用：每次校验版本，未改变时复用本地字节。
async function serveStatic(req, res, file, contentType) {
  const info = await stat(file);
  const etag = `W/"${info.size.toString(16)}-${info.mtimeMs.toString(16)}"`;
  res.setHeader('Content-Type', contentType);
  res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
  res.setHeader('ETag', etag);
  res.setHeader('Last-Modified', info.mtime.toUTCString());
  const matches = req.headers['if-none-match']?.split(',').map(value => value.trim());
  if (matches?.includes(etag) || matches?.includes('*')) {
    res.statusCode = 304;
    res.end();
    return;
  }
  res.setHeader('Content-Length', info.size);
  if (req.method === 'HEAD') { res.end(); return; }
  await pipeline(fs.createReadStream(file), res);
}

module.exports = { serveStatic };
