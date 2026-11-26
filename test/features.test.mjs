// The feature store: values by position, scaled to the track's own range.
import assert from "node:assert/strict"
import { test } from "node:test"
import { load } from "./load.mjs"

const F = load("Features", ["create", "MAX_BATCH"])
const rows = (n, fn) => Array.from({ length: n }, (_, i) => fn(i))

test("nothing measured means no answer, so a visual can go calm", () => {
  const s = F.create()
  assert.equal(s.at(0), null)
  assert.equal(s.covers(1), false)
})

test("levels are scaled to the track's own quiet and loud", () => {
  const quiet = F.create(), loud = F.create()
  // The same shape, one master 60 steps (about 20 dB) quieter than the other.
  quiet.add(0, 0.04, rows(500, i => [80 + (i % 50), 70, 60, 50, 0]))
  loud.add(0, 0.04, rows(500, i => [140 + (i % 50), 130, 120, 110, 0]))
  for (const t of [0.1, 1, 5, 12.3]) {
    assert.ok(Math.abs(quiet.at(t).level - loud.at(t).level) < 1e-9, `at ${t}s`)
  }
  const top = quiet.at(49 * 0.04 + 0.001).level, bottom = quiet.at(0.001).level
  assert.equal(top, 1)
  assert.ok(bottom < 0.2, `the quiet end reads low (${bottom})`)
})

test("values stay within 0 and 1 and silence reads as zero", () => {
  const s = F.create()
  s.add(0, 0.04, rows(300, i => [i % 3 === 0 ? 0 : 200, 255, 0, 128, 0]))
  for (let i = 0; i < 300; i++) {
    const v = s.at(i * 0.04 + 0.001)
    for (const k of ["level", "low", "mid", "high"]) assert.ok(v[k] >= 0 && v[k] <= 1)
  }
  assert.equal(s.at(0.001).level, 0)
})

test("batches must arrive in order; anything else turns the features off", () => {
  const s = F.create()
  assert.equal(s.add(0, 0.04, rows(125, () => [100, 100, 100, 100, 0])), true)
  assert.equal(s.add(125, 0.04, rows(125, () => [100, 100, 100, 100, 0])), true)
  assert.equal(s.seconds(), 10)
  assert.equal(s.add(500, 0.04, rows(10, () => [1, 1, 1, 1, 0])), false, "a gap")
  assert.equal(s.at(1), null, "and from then on it says it doesn't know")
  for (const bad of [null, [], rows(F.MAX_BATCH + 1, () => [1, 1, 1, 1, 0]), [[1, 2]], "x"]) {
    const t = F.create()
    assert.equal(t.add(0, 0.04, bad), false)
  }
  assert.equal(F.create().add(0, 5, rows(3, () => [1, 1, 1, 1, 0])), false, "an absurd frame length")
})

test("out-of-range numbers are clamped, not trusted", () => {
  const s = F.create()
  s.add(0, 0.04, [[999, -5, "40", NaN, 300], ...rows(50, () => [100, 100, 100, 100, 0])])
  assert.deepEqual(s.rows[0], [0, 0, 40, 0, 0])
})

test("onsets are found between two positions, and a jump is not a run of onsets", () => {
  const s = F.create()
  s.add(0, 0.04, rows(400, i => [100, 100, 100, 100, i === 10 ? 128 : (i === 12 ? 255 : 0)]))
  assert.equal(s.onsetBetween(8, 9), 0)
  assert.ok(Math.abs(s.onsetBetween(9, 10) - 128 / 255) < 1e-9)
  assert.equal(s.onsetBetween(9, 13), 1, "the strongest in the span")
  assert.equal(s.onsetBetween(10, 10), 0, "nothing new since the last look")
  assert.equal(s.onsetBetween(0, 300), 0, "a seek across them fires nothing")
})

test("reset forgets the last track", () => {
  const s = F.create()
  s.add(0, 0.04, rows(50, () => [100, 100, 100, 100, 0]))
  s.fail("x")
  s.reset()
  assert.equal(s.broken, "")
  assert.equal(s.seconds(), 0)
  assert.equal(s.add(0, 0.04, rows(50, () => [100, 100, 100, 100, 0])), true)
})
