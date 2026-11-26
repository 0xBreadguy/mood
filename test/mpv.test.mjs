// What the player's replies and events mean, checked against a conversation
// recorded from mpv 0.41 in an Omabox desktop on 2026-11-21.
import assert from "node:assert/strict"
import { test } from "node:test"
import { load } from "./load.mjs"

const M = load("Mpv", ["create", "launchArguments", "SKIP_MARKER", "BACK_MARKER"])

function loaded(seq = 7) {
  const s = M.create()
  s.hello()
  const cmds = s.load(seq, "/run/user/1000/mood/7.fifo", "Late Night")
  const ids = cmds.map(c => c.request_id)
  // mpv answers each loadfile with the playlist entry it made.
  s.feed({ request_id: ids[0], error: "success" })
  s.feed({ data: { playlist_entry_id: 1 }, request_id: ids[1], error: "success" })
  s.feed({ data: { playlist_entry_id: 2 }, request_id: ids[2], error: "success" })
  s.feed({ data: { playlist_entry_id: 3 }, request_id: ids[3], error: "success" })
  return { s, cmds }
}
const types = events => events.map(e => e.type + (e.dir ? e.dir : "") + (e.reason ? ":" + e.reason : ""))

test("a load is the track between two markers, titled with the mood and never the track", () => {
  const { cmds } = loaded()
  assert.deepEqual(cmds.map(c => c.command), [
    ["set_property", "force-media-title", "Late Night"],
    ["loadfile", "/run/user/1000/mood/7.fifo", "replace"],
    ["loadfile", M.SKIP_MARKER, "append"],
    ["loadfile", M.BACK_MARKER, "insert-at", 0],
    ["set_property", "pause", false]
  ])
  assert.equal(new Set(cmds.map(c => c.request_id)).size, cmds.length)
})

test("sound starting is reported once the track's own entry restarts playback", () => {
  const { s } = loaded()
  assert.deepEqual(s.feed({ event: "start-file", playlist_entry_id: 1 }), [])
  assert.deepEqual(s.feed({ event: "file-loaded" }), [])
  assert.deepEqual(s.feed({ event: "playback-restart" }), [{ type: "started", seq: 7 }])
})

test("the end of the track, then the player reaching its marker", () => {
  const { s } = loaded()
  s.feed({ event: "start-file", playlist_entry_id: 1 })
  assert.deepEqual(types(s.feed({ event: "end-file", reason: "eof", playlist_entry_id: 1 })), ["ended:eof"])
  assert.deepEqual(types(s.feed({ event: "start-file", playlist_entry_id: 2 })), ["jump1"])
  assert.deepEqual(s.feed({ event: "end-file", reason: "error", playlist_entry_id: 2, file_error: "no audio or video data played" }), [],
    "a marker failing to play is not a track failing")
})

test("the media keys, as recorded: next lands on the skip marker, previous on the back marker", () => {
  const next = loaded().s
  next.feed({ event: "start-file", playlist_entry_id: 1 })
  const a = [
    { event: "end-file", reason: "stop", playlist_entry_id: 1 },
    { event: "start-file", playlist_entry_id: 2 },
    { event: "end-file", reason: "error", playlist_entry_id: 2, file_error: "no audio or video data played" },
    { event: "idle" },
    { event: "property-change", id: 2, name: "idle-active", data: true }
  ].flatMap(m => next.feed(m))
  assert.deepEqual(types(a), ["ended:stop", "jump1", "idle"])

  const prev = loaded().s
  prev.feed({ event: "start-file", playlist_entry_id: 1 })
  const b = [
    { event: "end-file", reason: "stop", playlist_entry_id: 1 },
    { event: "start-file", playlist_entry_id: 3 },
    { event: "end-file", reason: "error", playlist_entry_id: 3, file_error: "no audio or video data played" },
    { event: "start-file", playlist_entry_id: 1 }
  ].flatMap(m => prev.feed(m))
  assert.deepEqual(types(b), ["ended:stop", "jump-1"])
})

test("pause, duration and position", () => {
  const { s } = loaded()
  assert.deepEqual(s.feed({ event: "property-change", id: 1, name: "pause", data: true }), [{ type: "pause", value: true }])
  assert.deepEqual(s.feed({ event: "property-change", id: 3, name: "duration", data: 131.9 }), [{ type: "duration", value: 131.9 }])
  assert.deepEqual(s.feed({ event: "property-change", id: 3, name: "duration" }), [], "no value yet")
  const ask = s.ask("time-pos")
  assert.deepEqual(s.feed({ request_id: ask.request_id, error: "success", data: 12.5 }), [{ type: "position", value: 12.5 }])
  assert.deepEqual(s.feed({ request_id: ask.request_id, error: "success", data: 99 }), [], "an answer is used once")
  const early = s.ask("time-pos")
  assert.deepEqual(s.feed({ request_id: early.request_id, error: "property unavailable" }), [])
})

test("a stream the player refuses is an ended track; junk is ignored", () => {
  const s = M.create()
  const cmds = s.load(3, "/x.fifo", "m")
  assert.deepEqual(types(s.feed({ request_id: cmds[1].request_id, error: "invalid parameter" })), ["ended:error"])
  for (const junk of [null, 5, "x", {}, { event: "nonsense" }, { request_id: 9999, error: "success" }])
    assert.deepEqual(s.feed(junk), [])
})

test("events for an older load carry that load's number, so the engine can ignore them", () => {
  const { s } = loaded(7)
  const cmds = s.load(8, "/8.fifo", "m")
  s.feed({ data: { playlist_entry_id: 4 }, request_id: cmds[1].request_id, error: "success" })
  assert.deepEqual(s.feed({ event: "end-file", reason: "stop", playlist_entry_id: 1 }), [], "the old entries are forgotten")
  assert.deepEqual(s.feed({ event: "start-file", playlist_entry_id: 4 }), [])
  assert.deepEqual(s.feed({ event: "playback-restart" }), [{ type: "started", seq: 8 }])
})

test("mpv is started audio-only, without the user's configuration, and silent when asked", () => {
  const args = M.launchArguments("/run/user/1000/mood/mpv.sock", { silent: true, mprisScript: "/etc/mpv/scripts/mpris.so" })
  for (const want of ["--no-config", "--vid=no", "--idle=yes", "--ytdl=no", "--load-scripts=no", "--ao=null",
    "--input-ipc-server=/run/user/1000/mood/mpv.sock", "--script=/etc/mpv/scripts/mpris.so"])
    assert.ok(args.includes(want), want)
  const plain = M.launchArguments("/s", {})
  assert.ok(!plain.some(a => a.startsWith("--ao=") || a.startsWith("--script=")))
})
