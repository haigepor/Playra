'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const adbPath = process.env.PLAYRA_ADB || 'D:/leidian/LDPlayer14/adb.exe';
const serial = process.env.PLAYRA_ADB_SERIAL || 'emulator-5554';
const adb = (...args) => cp.execFileSync(adbPath, ['-s', serial, ...args], { maxBuffer: 16 * 1024 * 1024 });
const sleep = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
class VisibleFrameGate {
  darkSeen = false;
  pending = null;
  update(fraction, elapsed) {
    if (fraction <= .08) { this.darkSeen = true; this.pending = null; return null; }
    if (this.darkSeen && fraction >= .25) {
      if (this.pending !== null) return this.pending;
      this.pending = elapsed;
    } else this.pending = null;
    return null;
  }
}
function sample() {
  const b = adb('exec-out', 'screencap');
  const width = b.readUInt32LE(0), height = b.readUInt32LE(4), format = b.readUInt32LE(8);
  // 本次雷电采样固定为竖屏 720x1280；拒绝把错误区域当作视频。
  if (width !== 720 || height !== 1280 || ![1, 2].includes(format)) throw Error('UNSUPPORTED_CAPTURE');
  const offset = b.length - width * height * 4;
  if (offset < 12 || offset > 64) throw Error('INVALID_CAPTURE');
  let bright = 0, count = 0;
  for (let y = 128; y < 358; y += 4) for (let x = 80; x < 640; x += 4) {
    const p = offset + (y * width + x) * 4;
    if ((3 * b[p] + 6 * b[p + 1] + b[p + 2]) / 10 > 50) bright++;
    count++;
  }
  return bright / count;
}
function main(args) {
  const [directory, label, ...points] = args;
  if (!directory || !/^[a-z0-9_-]{1,64}$/.test(label || '') || !points.length) throw Error('Usage: output-dir label x,y [x,y ...]');
  fs.mkdirSync(directory, { recursive: true });
  const results = [];
  for (const [index, point] of points.entries()) {
    const xy = /^([0-9]{1,3}),([0-9]{1,4})$/.exec(point);
    if (!xy || +xy[1] >= 720 || +xy[2] >= 1280) throw Error('INVALID_TAP');
    const before = sample();
    if (before < .25) throw Error('START_FRAME_NOT_VISIBLE');
    const gate = new VisibleFrameGate(), samples = [];
    const start = process.hrtime.bigint();
    adb('shell', `input tap ${+xy[1]} ${+xy[2]}`);
    let visible = null, lastDarkCaptureStart = null;
    while (Number(process.hrtime.bigint() - start) / 1e6 < 45000) {
      const captureStartMs = Number(process.hrtime.bigint() - start) / 1e6;
      const fraction = sample(), ms = Number(process.hrtime.bigint() - start) / 1e6;
      samples.push({ captureStartMs, ms, fraction });
      if (fraction <= .08) lastDarkCaptureStart = captureStartMs;
      visible = gate.update(fraction, ms);
      if (visible !== null) break;
      sleep(120);
    }
    if (visible === null) throw Error(gate.darkSeen ? 'NO_VISIBLE_FRAME' : 'NO_DARK_TRANSITION');
    const screenshot = `${label}-${index}.png`;
    fs.writeFileSync(path.join(directory, screenshot), adb('exec-out', 'screencap', '-p'));
    const result = { index, tap: [+xy[1], +xy[2]], tapToVisibleMs: visible, visibleBoundsMs: [lastDarkCaptureStart, visible], beforeFraction: before, screenshot, samples };
    results.push(result);
    console.log(JSON.stringify({ index, tapToVisibleMs: Math.round(visible), screenshot }));
    fs.writeFileSync(path.join(directory, `${label}-visible.json`), JSON.stringify({ capture: 'adb-screencap-rgba', timing: 'visibleBoundsMs brackets screenshot acquisition, not a VSYNC timestamp', viewport: [720, 1280], roi: [80, 128, 640, 358], darkThreshold: .08, visibleThreshold: .25, consecutiveVisibleSamples: 2, results }, null, 2));
  }
}
if (require.main === module) { try { main(process.argv.slice(2)); } catch (e) { console.error(e.message); process.exitCode = 1; } }
module.exports = { VisibleFrameGate };
