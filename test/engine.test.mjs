// The playback core's decisions, driven by a recording set of effects and a
// hand-wound clock: no player, no network, no desktop.
import assert from "node:assert/strict"
import { test } from "node:test"
import { load, seeded } from "./load.mjs"

const E = load("Engine", ["create", "COALESCE_MS", "LOAD_TIMEOUT_MS", "NAME_MS", "RELEASE_MS", "IDLE_RELEASE_MS",
  "SOURCE_RETRY_MS", "SOURCE_SKIPS", "BACKOFF_MS"])
const Q = load("Queue", ["create"])

function catalog(sizes = { calm: 6, busy: 5, deep: 4 }) {
  const moods = [], tracks = {}
  for (const [id, n] of Object.entries(sizes)) {
    const ids = Array.from({ length: n }, (_, i) => `${id}-${i}`)
    for (const t of ids) tracks[t] = { id: t, mood: id, title: t, creator: "c", size: 1000, seconds: 100, location: {} }
    moods.push({ id, label: id.toUpperCase(), tracks: ids })
  }
  return { moods, tracks }
}

// A world for one engine: recorded effects, timers that fire when told.
function world(options = {}) {
  const w = { now: 0, timers: {}, log: [], events: [], saved: [], fetch: null, playerUp: false }
  const fx = {
    now: () => w.now,
    timer: (name, ms) => { if (ms < 0) delete w.timers[name]; else w.timers[name] = w.now + ms },
    startPlayer: () => { w.log.push("startPlayer"); w.playerUp = true },
    stopPlayer: () => { w.log.push("stopPlayer"); w.playerUp = false },
    playerLoad: (seq, title) => w.log.push(`load ${seq} ${title}`),
    playerCommand: c => w.log.push("cmd " + c.join(" ")),
    playerAsk: p => w.log.push("ask " + p),
    startFetcher: (seq, track, start) => { w.fetch = { seq, id: track.id, start }; w.log.push(`fetch ${track.id}`) },
    stopFetcher: () => { w.fetch = null },
    featuresReset: () => {},
    save: id => w.saved.push(id),
    emit: (...a) => w.events.push(a.join(":")),
    changed: () => {}
  }
  w.e = E.create(fx, catalog(options.sizes), { makeQueue: ids => Q.create(ids, seeded(options.seed || 1)) }, options)
  // Move the clock, firing timers that come due in order.
  w.advance = ms => {
    const end = w.now + ms
    for (;;) {
      const due = Object.entries(w.timers).filter(([, t]) => t <= end).sort((a, b) => a[1] - b[1])[0]
      if (!due) break
      w.now = due[1]
      delete w.timers[due[0]]
      w.e.onTimer(due[0])
    }
    w.now = end
  }
  // The player and fetcher doing what they do when all is well.
  w.playerReady = () => w.e.onPlayerReady()
  w.sound = () => {
    const seq = w.fetch.seq
    w.e.onFetcher(seq, { ev: "ready" })
    w.e.onPlayer({ type: "pause", value: false })
    w.e.onPlayer({ type: "started", seq })
    return seq
  }
  w.playThrough = () => { w.e.play(); w.advance(0); if (w.e.player === "starting") w.playerReady(); return w.sound() }
  w.fetches = () => w.log.filter(l => l.startsWith("fetch ")).map(l => l.slice(6))
  return w
}

test("nothing plays until asked, and the last mood is where it starts", () => {
  const w = world({ mood: "busy" })
  assert.equal(w.e.status, "stopped")
  assert.equal(w.e.mood().id, "busy")
  w.advance(60 * 60000)
  assert.deepEqual(w.log, [], "an hour of waiting starts no player and fetches nothing")
})

test("play is loading until the player reports sound, then playing", () => {
  const w = world()
  w.e.play()
  assert.equal(w.e.status, "loading")
  w.advance(0)
  assert.deepEqual(w.log, ["startPlayer"])
  w.playerReady()
  assert.equal(w.fetches().length, 1)
  w.e.onFetcher(w.fetch.seq, { ev: "ready" })
  assert.equal(w.e.status, "loading", "bytes are flowing but nothing has been heard")
  w.e.onPlayer({ type: "started", seq: w.fetch.seq })
  assert.equal(w.e.status, "playing")
})

test("pause and resume follow the player's word, including a pause from outside", () => {
  const w = world()
  w.playThrough()
  w.e.pause()
  assert.equal(w.e.status, "playing", "asked, not yet confirmed")
  w.e.onPlayer({ type: "pause", value: true })
  assert.equal(w.e.status, "paused")
  w.e.toggle()
  assert.ok(w.log.includes("cmd set_property pause false"))
  w.e.onPlayer({ type: "pause", value: false })
  assert.equal(w.e.status, "playing")
  w.e.onPlayer({ type: "pause", value: true })      // a media key, say
  assert.equal(w.e.status, "paused")
  assert.equal(w.e.wantPlay, false)
})

test("rapid skips coalesce into one fetch, of the last track asked for", () => {
  const w = world()
  w.playThrough()
  const before = w.fetches().length
  for (let i = 0; i < 6; i++) { w.e.skip(); w.advance(100) }
  assert.equal(w.e.status, "loading")
  assert.equal(w.fetches().length, before, "nothing fetched while the skips keep coming")
  w.advance(E.COALESCE_MS)
  assert.equal(w.fetches().length, before + 1)
  assert.equal(w.fetches().at(-1), w.e.track().id)
  assert.ok(w.log.includes("cmd stop"), "the old track is silenced at the first skip")
})

test("back goes to the track actually heard, not the ones skipped past", () => {
  const w = world()
  w.playThrough()
  const first = w.e.track().id
  for (let i = 0; i < 3; i++) w.e.skip()          // three tracks never heard
  w.advance(E.COALESCE_MS); w.sound()
  const fourth = w.e.track().id
  assert.equal(w.e.back(), true)
  assert.equal(w.e.track().id, first)
  w.advance(E.COALESCE_MS); w.sound()
  assert.equal(w.e.skip(), true)
  assert.equal(w.e.track().id, fourth, "skip after back returns where you were")
})

test("back with nothing earlier is refused out loud and changes nothing", () => {
  const w = world()
  w.playThrough()
  const id = w.e.track().id
  assert.equal(w.e.back(), false)
  assert.deepEqual(w.events.filter(x => x.startsWith("refused")), ["refused:back"])
  assert.equal(w.e.status, "playing")
  assert.equal(w.e.track().id, id)
})

test("history is kept per mood", () => {
  const w = world()
  w.playThrough()
  const calmFirst = w.e.track().id
  w.e.skip(); w.advance(E.COALESCE_MS); w.sound()
  w.e.stepMood(1); w.advance(E.COALESCE_MS); w.sound()
  assert.equal(w.e.mood().id, "busy")
  assert.equal(w.e.back(), false, "the new mood has no history of its own yet")
  w.e.stepMood(-1); w.advance(E.COALESCE_MS); w.sound()
  assert.equal(w.e.mood().id, "calm")
  assert.equal(w.e.back(), true)
  w.e.back()
  assert.equal(w.e.track().id, calmFirst)
})

test("the end of a track advances by itself", () => {
  const w = world()
  const seq = w.playThrough()
  const first = w.e.track().id
  w.e.onPlayer({ type: "ended", seq, reason: "eof", error: "" })
  w.e.onPlayer({ type: "jump", seq, dir: 1 })       // the player reaching its marker: already handled
  assert.equal(w.e.status, "loading")
  w.advance(0)
  assert.notEqual(w.e.track().id, first)
  assert.equal(w.fetches().length, 2)
  w.sound()
  assert.equal(w.e.back(), true)
  assert.equal(w.e.track().id, first)
})

test("mood steps wrap around both ways, announce their direction and show the name briefly", () => {
  const w = world()
  assert.equal(w.e.stepMood(-1), true)
  assert.equal(w.e.mood().id, "deep")
  assert.equal(w.e.stepMood(1), true)
  assert.equal(w.e.mood().id, "calm")
  assert.deepEqual(w.events, ["moodChanged:-1:DEEP", "moodChanged:1:CALM"])
  assert.equal(w.e.nameShowing, true)
  assert.equal(w.e.nameText, "CALM")
  w.advance(E.NAME_MS - 1)
  assert.equal(w.e.nameShowing, true)
  w.advance(1)
  assert.equal(w.e.nameShowing, false)
  assert.deepEqual(w.saved, ["deep", "calm"])
  assert.equal(w.e.status, "stopped", "changing mood while stopped does not start the music")
  assert.deepEqual(w.log, [])
})

test("setting a mood by id, the same mood again, and an unknown one", () => {
  const w = world()
  assert.equal(w.e.setMood("deep"), true)
  assert.deepEqual(w.events, ["moodChanged:0:DEEP"])
  assert.equal(w.e.setMood("deep"), true)
  assert.equal(w.events.length, 1, "choosing the current mood is not a change")
  assert.equal(w.e.setMood("nope"), false)
  assert.equal(w.e.mood().id, "deep")
})

test("a mood change while playing loads the new mood once the stepping stops", () => {
  const w = world()
  w.playThrough()
  w.e.stepMood(1); w.advance(80); w.e.stepMood(1); w.advance(80)
  assert.equal(w.fetches().length, 1)
  w.advance(E.COALESCE_MS)
  assert.equal(w.fetches().length, 2)
  assert.ok(w.fetches()[1].startsWith("deep-"))
})

test("a mood change while paused drops the held track and stays silent", () => {
  const w = world()
  w.playThrough()
  w.e.pause(); w.e.onPlayer({ type: "pause", value: true })
  w.e.stepMood(1)
  assert.equal(w.e.status, "stopped")
  w.advance(E.COALESCE_MS * 4)
  assert.equal(w.fetches().length, 1, "nothing is fetched for a mood nobody asked to hear")
  w.e.play(); w.advance(0)
  assert.ok(w.fetches()[1].startsWith("busy-"))
})

test("offline: the state says so and retries back off instead of hammering", () => {
  const w = world()
  w.e.play(); w.advance(0); w.playerReady()
  const same = w.e.track().id
  w.e.onFetcher(w.fetch.seq, { ev: "error", kind: "offline", detail: "gaierror" })
  assert.equal(w.e.status, "offline")
  assert.deepEqual(w.events, ["failed:offline"])
  const gaps = []
  let last = w.now
  for (let i = 0; i < 7; i++) {
    const n = w.fetches().length
    while (w.fetches().length === n) w.advance(500)
    gaps.push(w.now - last); last = w.now
    assert.equal(w.e.track().id, same, "offline is not the track's fault: the same track is retried")
    w.e.onFetcher(w.fetch.seq, { ev: "error", kind: "offline", detail: "gaierror" })
  }
  assert.deepEqual(gaps, [4000, 12000, 30000, 90000, 300000, 300000, 300000])
  assert.equal(w.fetches().length, 8, "eight attempts in about seventeen minutes")
})

test("recovery: the next attempt that works plays, and the backoff starts over", () => {
  const w = world()
  w.e.play(); w.advance(0); w.playerReady()
  w.e.onFetcher(w.fetch.seq, { ev: "error", kind: "offline", detail: "x" })
  w.advance(4000)
  w.sound()
  assert.equal(w.e.status, "playing")
  assert.equal(w.e.failure, null)
  assert.equal(w.e.attempts, 0)
})

test("a click while offline retries now rather than waiting out the backoff", () => {
  const w = world()
  w.e.play(); w.advance(0); w.playerReady()
  w.e.onFetcher(w.fetch.seq, { ev: "error", kind: "offline", detail: "x" })
  w.e.onFetcher(w.fetch ? w.fetch.seq : -1, { ev: "error", kind: "offline", detail: "x" })
  w.advance(1000)
  w.e.toggle(); w.advance(0)
  assert.equal(w.e.status, "loading")
  assert.equal(w.fetches().length, 2)
})

test("a broken track is passed over, but a broken source is not walked end to end", () => {
  const w = world()
  w.e.play(); w.advance(0); w.playerReady()
  const seen = [w.e.track().id]
  for (let i = 0; i < 4; i++) {
    w.e.onFetcher(w.fetch.seq, { ev: "error", kind: "source", detail: "HTTP 404" })
    assert.equal(w.e.status, "failed")
    const n = w.fetches().length
    const t0 = w.now
    while (w.fetches().length === n) w.advance(500)
    seen.push(w.e.track().id)
    if (i < E.SOURCE_SKIPS) assert.equal(w.now - t0, E.SOURCE_RETRY_MS)
    else assert.ok(w.now - t0 >= E.BACKOFF_MS[0], "after two in a row it waits properly")
  }
  assert.equal(new Set(seen).size, seen.length, "each attempt was a different track")
})

test("a fetch that dies mid-track lets the music run dry, then says offline", () => {
  const w = world()
  const seq = w.playThrough()
  w.e.onFetcher(seq, { ev: "error", kind: "offline", detail: "the transfer ended early" })
  assert.equal(w.e.status, "playing", "what arrived is still playing")
  w.e.onPlayer({ type: "ended", seq, reason: "eof", error: "" })
  assert.equal(w.e.status, "offline")
})

test("no sound in time is a failure, not an endless loading state", () => {
  const w = world()
  w.e.play(); w.advance(0); w.playerReady()
  w.e.onFetcher(w.fetch.seq, { ev: "ready" })
  w.advance(E.LOAD_TIMEOUT_MS)
  assert.equal(w.e.status, "offline")
})

test("a player that is missing or dies is reported as failed", () => {
  const w = world()
  w.e.play(); w.advance(0)
  w.e.onPlayerExit({ expected: false, missing: true })
  assert.equal(w.e.status, "failed")
  assert.equal(w.e.failure.detail, "mpv is not installed")
  const v = world()
  v.playThrough()
  v.e.onPlayerExit({ expected: false, missing: false })
  assert.equal(v.e.status, "failed")
  assert.equal(v.e.failure.kind, "player")
  v.advance(E.BACKOFF_MS[0])
  assert.equal(v.log.filter(l => l === "startPlayer").length, 2, "it is started again after the wait")
})

test("pause while loading drops the load: nothing is held, so the state is stopped", () => {
  const w = world()
  w.e.play(); w.advance(0); w.playerReady()
  w.e.toggle()
  assert.equal(w.e.status, "stopped")
  assert.equal(w.fetch, null)
})

test("a long pause lets the player go and resumes from about the same place", () => {
  const w = world()
  w.playThrough()
  w.advance(30000)                                   // thirty seconds into a 100 s track
  w.e.pause(); w.e.onPlayer({ type: "pause", value: true })
  w.advance(E.RELEASE_MS)
  assert.ok(w.log.includes("stopPlayer"))
  w.e.onPlayerExit({ expected: true })
  assert.equal(w.e.status, "paused", "still paused: the position is kept")
  w.e.play(); w.advance(0)
  assert.equal(w.log.filter(l => l === "startPlayer").length, 2)
  w.playerReady()
  assert.ok(Math.abs(w.fetch.start - 0.3) < 0.01, `resumes at ${w.fetch.start}`)
  w.sound(); w.advance(5000)
  assert.ok(Math.abs(w.e.position() - 5) < 0.01, "the features follow the part that was fetched")
  assert.ok(Math.abs(w.e.trackPosition() - 35) < 0.5, "the listener is 35 s into the track")
})

test("stopped with a player still up lets it go after a minute", () => {
  const w = world()
  w.e.play(); w.advance(0); w.playerReady()
  w.e.toggle()
  assert.equal(w.playerUp, true)
  w.advance(E.IDLE_RELEASE_MS)
  assert.equal(w.playerUp, false)
})

test("stop lets everything go at once", () => {
  const w = world()
  w.playThrough()
  w.e.stop()
  assert.equal(w.e.status, "stopped")
  assert.equal(w.playerUp, false)
  assert.equal(w.fetch, null)
})

test("media keys: next skips, previous goes back, previous with nothing earlier restarts the track", () => {
  const w = world()
  let seq = w.playThrough()
  const first = w.e.track().id
  w.e.onPlayer({ type: "jump", seq, dir: 1 })
  assert.deepEqual(w.events, ["skipped:1"])
  w.advance(E.COALESCE_MS); seq = w.sound()
  w.e.onPlayer({ type: "jump", seq, dir: -1 })
  assert.equal(w.e.track().id, first)
  w.advance(E.COALESCE_MS); seq = w.sound()
  w.e.onPlayer({ type: "jump", seq, dir: -1 })
  assert.equal(w.events.at(-1), "refused:back")
  assert.equal(w.e.status, "loading")
  w.advance(0)
  assert.equal(w.fetches().at(-1), first)
})

test("a stop from outside is believed", () => {
  const w = world()
  w.playThrough()
  w.e.onPlayer({ type: "idle" })
  assert.equal(w.e.status, "stopped")
  assert.equal(w.e.wantPlay, false)
})

test("events from a load that was superseded are ignored", () => {
  const w = world()
  const old = w.playThrough()
  w.e.skip(); w.advance(E.COALESCE_MS)
  w.e.onPlayer({ type: "ended", seq: old, reason: "error", error: "late" })
  w.e.onFetcher(old, { ev: "error", kind: "offline", detail: "late" })
  w.e.onPlayer({ type: "started", seq: old })
  assert.equal(w.e.status, "loading")
  assert.equal(w.e.failure, null)
})

test("the position runs while playing, holds while paused and follows the player's reports", () => {
  const w = world()
  w.playThrough()
  w.advance(2000)
  assert.ok(Math.abs(w.e.position() - 2) < 0.001)
  w.e.onPlayer({ type: "position", value: 1.9 })
  w.advance(1000)
  assert.ok(Math.abs(w.e.position() - 2.9) < 0.001)
  w.e.pause(); w.e.onPlayer({ type: "pause", value: true })
  w.advance(5000)
  assert.ok(Math.abs(w.e.position() - 2.9) < 0.001)
})

test("skip from stopped plays; a mood with nothing in it fails honestly", () => {
  const w = world()
  w.e.skip(); w.advance(E.COALESCE_MS)
  assert.equal(w.e.status, "loading")
  const empty = world({ sizes: { none: 0, some: 2 } })
  assert.equal(empty.e.skip(), false)
  empty.e.play()
  assert.equal(empty.e.status, "failed")
})
