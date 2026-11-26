// The per-mood queue: shuffle without immediate repeats, and a history of
// tracks that were actually heard. Run: node --test test/
import assert from "node:assert/strict"
import { test } from "node:test"
import { load, seeded } from "./load.mjs"

const Q = load("Queue", ["create", "HISTORY_LIMIT"])
const ids = n => Array.from({ length: n }, (_, i) => "t" + i)

test("every track plays once before any repeats, and a new round never opens with the last track", () => {
  for (let seed = 1; seed <= 200; seed++) {
    const q = Q.create(ids(5), seeded(seed))
    let last = null
    for (let round = 0; round < 4; round++) {
      const seen = new Set()
      for (let i = 0; i < 5; i++) {
        const id = q.next()
        assert.notEqual(id, last, `seed ${seed}: ${id} played twice running`)
        seen.add(id)
        last = id
      }
      assert.equal(seen.size, 5, `seed ${seed}: a round repeated a track`)
    }
  }
})

test("back returns to tracks that were heard, most recent first", () => {
  const q = Q.create(ids(6), seeded(7))
  const a = q.next(); q.markHeard()
  const b = q.next(); q.markHeard()
  const c = q.next(); q.markHeard()
  assert.equal(q.back(), b)
  q.markHeard()
  assert.equal(q.back(), a)
  assert.equal(q.back(), null, "nothing earlier than the first track")
  assert.equal(q.current(), a, "a refused back leaves the current track alone")
  assert.ok(c)
})

test("a track skipped before it was heard leaves no trail", () => {
  const q = Q.create(ids(8), seeded(3))
  const a = q.next(); q.markHeard()
  q.next()            // skipped at once
  q.next()            // skipped at once
  const d = q.next(); q.markHeard()
  assert.equal(q.back(), a)
  assert.equal(q.canBack(), false)
  assert.ok(d)
})

test("skip after back returns exactly where you were", () => {
  const q = Q.create(ids(8), seeded(11))
  const a = q.next(); q.markHeard()
  const b = q.next(); q.markHeard()
  const c = q.next(); q.markHeard()
  assert.equal(q.back(), b); q.markHeard()
  assert.equal(q.back(), a); q.markHeard()
  assert.equal(q.next(), b); q.markHeard()
  assert.equal(q.next(), c); q.markHeard()
  const d = q.next()
  assert.ok(![a, b, c].includes(d), "past the stack, the bag continues")
})

test("with nothing played, there is nothing to go back to", () => {
  const q = Q.create(ids(3), seeded(1))
  assert.equal(q.back(), null)
  assert.equal(q.current(), null)
})

test("entering a mood keeps an unheard track and moves past a heard one", () => {
  const q = Q.create(ids(4), seeded(5))
  const a = q.enter()
  assert.equal(q.enter(), a, "still unheard: stay")
  q.markHeard()
  const b = q.enter()
  assert.notEqual(b, a)
  assert.equal(q.back(), a, "the heard track is one step back")
})

test("a single-track mood and an empty one behave", () => {
  const one = Q.create(["only"], seeded(2))
  assert.equal(one.next(), "only")
  one.markHeard()
  assert.equal(one.next(), "only", "one track can only repeat")
  const none = Q.create([], seeded(2))
  assert.equal(none.next(), null)
  assert.equal(none.back(), null)
})

test("the history is bounded", () => {
  const q = Q.create(ids(10), seeded(9))
  for (let i = 0; i < 200; i++) { q.next(); q.markHeard() }
  assert.equal(q.history.length, Q.HISTORY_LIMIT)
})
