// Reading the catalog files into moods and fetch requests, without trusting them.
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import { load } from "./load.mjs"

const C = load("Catalog", ["build", "fetchSpec", "plain"])
const read = name => readFileSync(new URL(`../catalog/${name}`, import.meta.url), "utf8")

const zip = (over = {}) => ({ kind: "zip", archive: "a", name: "x.mp3", header: 100, offset: 140, length: 500, method: 8, crc32: "0123abcd", ...over })
const track = (over = {}) => ({ id: "s:one", category: "calm", title: "One", creator: "Someone", page: "https://example.org/one",
  license: "CC0-1.0", location: { kind: "url", url: "https://example.org/one.mp3", crc32: "0123abcd" }, size: 1000, seconds: 60, ...over })
const doc = (tracks, extra = {}) => JSON.stringify({ version: 1, generated: "2026-11-21",
  archives: [{ id: "a", url: "https://example.org/a.zip", size: 10000 }],
  categories: [{ id: "calm", source: "s", label: "Calm & Quiet Rooms" }, { id: "busy", source: "s", label: "Busy" }],
  tracks, ...extra })

test("the catalog in the repo reads cleanly: thirteen moods, 451 tracks, both location kinds", () => {
  const c = C.build(read("catalog.json"), read("categories.json"))
  assert.equal(c.error, "")
  assert.equal(c.skipped, 0)
  assert.equal(c.moods.length, 13)
  assert.equal(Object.keys(c.tracks).length, 451)
  assert.deepEqual(c.moods.map(m => m.id), JSON.parse(read("categories.json")).order)
  for (const m of c.moods) {
    assert.ok(m.label.length > 0 && m.label.length <= 24, m.label)
    assert.ok(m.tracks.length > 0)
  }
  const kinds = new Set(Object.values(c.tracks).map(t => t.location.kind))
  assert.deepEqual([...kinds].sort(), ["url", "zip"])
  const openLofi = Object.values(c.tracks).filter(t => t.location.kind === "zip")
  assert.equal(openLofi.length, 166)
  assert.ok(openLofi.every(t => t.location.url.startsWith("https://github.com/btahir/open-lofi/releases/download/")))
})

test("display names come from categories.json, in its order; the collection's label is the fallback", () => {
  const c = C.build(doc([track(), track({ id: "s:two", category: "busy" })]),
    JSON.stringify({ order: ["busy", "calm"], names: { calm: "Calm" } }))
  assert.deepEqual(c.moods.map(m => [m.id, m.label]), [["busy", "Busy"], ["calm", "Calm"]])
  assert.equal(c.moods[1].sourceLabel, "Calm & Quiet Rooms")
  const noNames = C.build(doc([track()]), "not json")
  assert.equal(noNames.moods[0].label, "Calm & Quiet Rooms")
})

test("markup-shaped and control text is neutralized before it can reach a label or tooltip", () => {
  const evil = '<img src="https://example.invalid/t">‮\x1b[31mevil\n'
  const c = C.build(doc([track({ title: evil, creator: "<b>x</b>" })]), JSON.stringify({ names: { calm: "<i>Calm</i>" } }))
  const t = c.tracks["s:one"]
  assert.ok(!/[<>]/.test(t.title + t.creator + c.moods[0].label))
  assert.ok(!/[\u0000-\u001f‮]/.test(t.title))
  assert.ok(C.plain("x".repeat(500)).length <= 120)
})

test("tracks with locations that could not be the plugin's own are dropped, not played", () => {
  const bad = [
    track({ id: "a", location: { kind: "url", url: "http://example.org/a.mp3", crc32: "0123abcd" } }),
    track({ id: "b", location: { kind: "url", url: "file:///etc/passwd", crc32: "0123abcd" } }),
    track({ id: "c", location: { kind: "url", url: "https://example.org/a b.mp3", crc32: "0123abcd" } }),
    track({ id: "d", location: zip({ archive: "missing" }) }),
    track({ id: "e", location: zip({ offset: 9900, length: 500 }) }),
    track({ id: "f", location: zip({ header: 200, offset: 140 }) }),
    track({ id: "g", location: zip({ method: 99 }) }),
    track({ id: "h", location: zip({ crc32: "nope" }) }),
    track({ id: "i", size: 0 }),
    track({ id: "j", category: "unknown" }),
    track({ id: "k", location: { kind: "exec", url: "https://example.org/x" } }),
    track({ id: "ok" }), track({ id: "ok" }),
  ]
  const c = C.build(doc(bad), "{}")
  assert.deepEqual(Object.keys(c.tracks), ["ok"])
  assert.equal(c.skipped, bad.length - 1)
})

test("an unusable catalog says so instead of yielding an empty player", () => {
  assert.notEqual(C.build("{", "{}").error, "")
  assert.notEqual(C.build(JSON.stringify({ version: 2 }), "{}").error, "")
  assert.notEqual(C.build(doc([]), "{}").error, "")
})

test("the fetch request carries the location, the size and where to start", () => {
  const c = C.build(doc([track(), track({ id: "s:z", location: zip() })]), "{}")
  assert.deepEqual(C.fetchSpec(c.tracks["s:one"], 0),
    { kind: "url", url: "https://example.org/one.mp3", crc32: "0123abcd", size: 1000, start: 0 })
  const z = C.fetchSpec(c.tracks["s:z"], 0.25)
  assert.equal(z.url, "https://example.org/a.zip")
  assert.equal(z.archive_size, 10000)
  assert.equal(z.start, 0.25)
  assert.equal(C.fetchSpec(c.tracks["s:z"], 5).start, 0, "an absurd start is ignored")
})
