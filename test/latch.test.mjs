// The gesture latch: one swipe makes exactly one step, on one axis.
import assert from "node:assert/strict"
import { test } from "node:test"
import { load } from "./load.mjs"

const L = load("Latch", ["create", "units", "DEFAULTS"])

// Feed a run of wheel events; collect the steps fired.
function run(latch, events) {
  const out = []
  for (const [t, dx, dy] of events) {
    const step = latch.wheel(dx, dy, t)
    if (step) out.push(`${step.axis}${step.dir > 0 ? "+" : "-"}`)
  }
  return out
}
// A swipe: `total` pixels spread over `n` events `gap` ms apart, starting at t0.
const swipe = (t0, total, n, gap, axis = "y") =>
  Array.from({ length: n }, (_, i) => axis === "y" ? [t0 + i * gap, 0, total / n] : [t0 + i * gap, total / n, 0])

test("a long swipe down is one step forward, however far it travels", () => {
  assert.deepEqual(run(L.create(), swipe(0, -600, 40, 8)), ["y+"])
})

test("a swipe and an 800 ms tail of fading deltas is still one step", () => {
  const tail = Array.from({ length: 50 }, (_, i) => [320 + i * 16, 0, -Math.max(1, 30 - i)])
  assert.deepEqual(run(L.create(), [...swipe(0, -300, 20, 16), ...tail]), ["y+"])
})

test("movement below the threshold does nothing", () => {
  assert.deepEqual(run(L.create(), swipe(0, -49, 7, 10)), [])
})

test("a slanted swipe goes to one axis only: never a skip and a mood change together", () => {
  const events = Array.from({ length: 30 }, (_, i) => [i * 10, -8, -11])
  assert.deepEqual(run(L.create(), events), ["y+"])
  const sideways = Array.from({ length: 30 }, (_, i) => [i * 10, 12, 7])
  assert.deepEqual(run(L.create(), sideways), ["x-"])
})

test("once an axis owns the gesture the other is ignored until the wheel is quiet", () => {
  const latch = L.create()
  assert.deepEqual(run(latch, swipe(0, -80, 8, 10)), ["y+"])
  assert.deepEqual(run(latch, swipe(100, 400, 10, 10, "x")), [], "sideways travel inside the latch")
  assert.deepEqual(run(latch, swipe(100 + 90 + 241, 80, 8, 10, "x")), ["x-"], "after the quiet gap it is a new gesture")
})

test("a deliberate swipe back inside the latch undoes the step at once", () => {
  const latch = L.create()
  assert.deepEqual(run(latch, swipe(0, -80, 8, 10)), ["y+"])
  assert.deepEqual(run(latch, swipe(90, 80, 8, 10)), [], "80 px back is not enough")
  assert.deepEqual(run(latch, swipe(180, 20, 2, 10)), ["y-"], "past 90 px it fires the reverse")
})

test("jitter against the direction does not add up across forward movement", () => {
  const latch = L.create()
  const events = [...swipe(0, -80, 8, 10)]
  for (let i = 0; i < 20; i++) events.push([100 + i * 10, 0, i % 2 ? 40 : -40])
  assert.deepEqual(run(latch, events), ["y+"])
})

test("two wheel notches more than the quiet gap apart are two steps; a fast spin is one", () => {
  const notch = L.units(0, -15, 0, -120, 0, false)
  assert.deepEqual(notch, { x: 0, y: -L.DEFAULTS.threshold })
  const slow = L.create()
  assert.deepEqual(run(slow, [[0, 0, notch.y], [400, 0, notch.y]]), ["y+", "y+"])
  const fast = L.create()
  assert.deepEqual(run(fast, [[0, 0, notch.y], [60, 0, notch.y], [120, 0, notch.y]]), ["y+"])
})

test("lifting the fingers ends the gesture: a second swipe straight after is a second step", () => {
  const latch = L.create()
  assert.deepEqual(run(latch, swipe(0, -80, 8, 10)), ["y+"])
  latch.end()
  assert.deepEqual(run(latch, swipe(90, -80, 8, 10)), ["y+"])
  latch.end()
  assert.deepEqual(run(latch, swipe(180, 80, 8, 10, "x")), ["x-"], "and it may be on the other axis")
})

test("directions: down and right are forward, up and left are back", () => {
  assert.deepEqual(run(L.create(), [[0, 0, -60]]), ["y+"])
  assert.deepEqual(run(L.create(), [[0, 0, 60]]), ["y-"])
  assert.deepEqual(run(L.create(), [[0, -60, 0]]), ["x+"])
  assert.deepEqual(run(L.create(), [[0, 60, 0]]), ["x-"])
})

test("units, from wheel events recorded in the shell", () => {
  // A mouse notch down: pixels 0,-15, angle 0,-120, no phase.
  assert.deepEqual(L.units(0, -15, 0, -120, 0, false), { x: 0, y: -50 })
  // A notch on a sideways wheel.
  assert.deepEqual(L.units(-15, 0, -120, 0, 0, false), { x: -50, y: 0 })
  // Two notches in one event, as a fast wheel sends.
  assert.deepEqual(L.units(0, -15, 0, -240, 0, false), { x: 0, y: -100 })
  // A trackpad update: pixels rounded to -3, angle -29: 3.6 px of travel.
  assert.deepEqual(L.units(-3, 0, -29, 0, 2, false), { x: -29 / 8, y: 0 })
  assert.deepEqual(L.units(0, -2, 0, -19, 2, false), { x: 0, y: -19 / 8 })
  // Pixels alone, where a platform gives no angle.
  assert.deepEqual(L.units(4, -9, 0, 0, 2, false), { x: 4, y: -9 })
})

test("units: sideways turns a vertical wheel into a horizontal one and leaves a sideways one alone", () => {
  assert.deepEqual(L.units(0, -15, 0, -120, 0, true), { x: -50, y: 0 })
  assert.deepEqual(L.units(0, 0, 0, -240, 2, true), { x: -30, y: 0 })
  assert.deepEqual(L.units(0, 0, -320, 40, 2, true), { x: -40, y: 5 })
})

test("a recorded trackpad swipe of 58 px is one step; one of 29 px is none", () => {
  const long = Array.from({ length: 24 }, (_, i) => [i * 8, 0, L.units(0, -2, 0, -19.4, 2, false).y])
  assert.deepEqual(run(L.create(), long), ["y+"])
  const short = Array.from({ length: 8 }, (_, i) => [i * 8, L.units(-3, 0, -29, 0, 2, false).x, 0])
  assert.deepEqual(run(L.create(), short), [])
})
