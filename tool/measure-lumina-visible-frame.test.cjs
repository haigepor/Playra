'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { VisibleFrameGate } = require('./measure-lumina-visible-frame.cjs');
test('poster alone cannot count as a new video frame', () => {
  const gate = new VisibleFrameGate();
  assert.equal(gate.update(.7, 100), null);
  assert.equal(gate.update(.8, 200), null);
});
test('loading icon remains below the visible frame threshold', () => {
  const gate = new VisibleFrameGate();
  assert.equal(gate.update(.03, 100), null);
  assert.equal(gate.update(.07, 200), null);
  assert.equal(gate.update(.4, 300), null);
  assert.equal(gate.update(.5, 400), 300);
});
test('a single bright flash cannot count as a stable video frame', () => {
  const gate = new VisibleFrameGate();
  gate.update(.03, 100); gate.update(.4, 200); gate.update(.1, 300);
  assert.equal(gate.update(.5, 400), null);
  assert.equal(gate.update(.6, 500), 400);
});
