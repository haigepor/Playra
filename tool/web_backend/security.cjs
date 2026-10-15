const dns = require('node:dns/promises');
const net = require('node:net');
const path = require('node:path');

function isPublicAddress(ip) {
  if (net.isIP(ip) === 4) {
    const [a, b, c] = ip.split('.').map(Number);
    return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
      (a === 192 && b === 0) || (a === 198 && (b === 18 || b === 19 || b === 51)) ||
      (a === 203 && b === 0 && c === 113));
  }
  if (net.isIP(ip) === 6) {
    // 仅允许 IPv6 全球单播；同时拒绝映射 IPv4 与文档网段。
    return /^[23][0-9a-f]{3}:/i.test(ip) && !/^2001:db8:/i.test(ip);
  }
  return false;
}

async function validateTarget(raw, lookup = dns.lookup) {
  const url = new URL(raw);
  const host = url.hostname.replace(/^\[|\]$/g, '');
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password ||
      (url.port && !['80', '443'].includes(url.port) &&
        !(url.protocol === 'https:' && host === 'play.xfvod.pro' && url.port === '8088')) || host === 'localhost' ||
      host.endsWith('.localhost') || host.endsWith('.local')) throw new Error('目标地址不允许');
  const addresses = net.isIP(host) ? [{ address: host, family: net.isIP(host) }] :
    await lookup(host, { all: true });
  if (!addresses.length || addresses.some(({ address }) => !isPublicAddress(address))) {
    throw new Error('目标必须是公网地址');
  }
  return { url, address: addresses.find((a) => a.family === 4) || addresses[0] };
}

function resolveStaticPath(root, raw) {
  const decoded = decodeURIComponent(raw).replaceAll('\\', '/');
  if (decoded.includes('\0') || decoded.split('/').includes('..')) throw new Error('路径不允许');
  const base = path.resolve(root);
  const result = path.resolve(base, '.' + decoded);
  if (result !== base && !result.startsWith(base + path.sep)) throw new Error('路径不允许');
  return result;
}
module.exports = { isPublicAddress, validateTarget, resolveStaticPath };
