.pragma library

// Reads catalog/catalog.json and catalog/categories.json into what the plugin
// uses: the moods in stepping order, each with its tracks, and the request to
// hand the fetcher for a track. Both files are text from disk, so everything
// is bounded and checked here rather than trusted.

var MAX_MOODS = 64
var MAX_TRACKS = 8000
var MAX_NAME = 24

// One line of plain text. Markup brackets and control characters are replaced,
// so a title can never be read as rich text wherever it ends up.
function plain(value, limit) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[\u0000-\u001f\u007f‪-‮⁦-⁩]/g, " ")
  s = s.replace(/</g, "‹").replace(/>/g, "›")
  s = s.replace(/\s+/g, " ").trim()
  return s.slice(0, limit > 0 ? limit : 120)
}

function isHttps(url) { return typeof url === "string" && /^https:\/\/[^\s"'<>\\]+$/.test(url) }
function isCrc(v) { return typeof v === "string" && /^[0-9a-f]{8}$/.test(v) }
function isCount(v, max) { return typeof v === "number" && isFinite(v) && v >= 0 && v <= max && Math.floor(v) === v }

function location(loc, archives) {
  if (!loc || !isCrc(loc.crc32)) return null
  if (loc.kind === "url") return isHttps(loc.url) ? { kind: "url", url: loc.url, crc32: loc.crc32 } : null
  if (loc.kind !== "zip") return null
  var a = archives[String(loc.archive)]
  if (!a) return null
  if (!isCount(loc.header, a.size) || !isCount(loc.offset, a.size) || !isCount(loc.length, a.size)) return null
  if (loc.header >= loc.offset || loc.offset - loc.header > 4096 || loc.offset + loc.length > a.size) return null
  if (loc.method !== 0 && loc.method !== 8) return null
  if (typeof loc.name !== "string" || loc.name.length === 0 || loc.name.length > 512) return null
  return { kind: "zip", url: a.url, archive_size: a.size, name: loc.name, header: loc.header,
           offset: loc.offset, length: loc.length, method: loc.method, crc32: loc.crc32 }
}

// { moods: [{ id, label, sourceLabel, tracks: [...] }], tracks: {id: track},
//   generated, skipped, error }. `error` is set when nothing usable was read.
function build(catalogText, categoriesText) {
  var out = { moods: [], tracks: {}, generated: "", skipped: 0, error: "" }
  var catalog, names
  try { catalog = JSON.parse(catalogText) } catch (e) { out.error = "the catalog is not valid JSON"; return out }
  try { names = JSON.parse(categoriesText) } catch (e2) { names = {} }
  if (!catalog || catalog.version !== 1 || !Array.isArray(catalog.tracks) || !Array.isArray(catalog.categories)) {
    out.error = "the catalog is not a version this plugin reads"
    return out
  }
  out.generated = plain(catalog.generated, 32)

  var archives = {}
  var list = Array.isArray(catalog.archives) ? catalog.archives : []
  for (var a = 0; a < list.length && a < 16; a++) {
    var arc = list[a]
    if (arc && isHttps(arc.url) && isCount(arc.size, 1e12)) archives[String(arc.id)] = { url: arc.url, size: arc.size }
  }

  var byId = {}, order = []
  for (var c = 0; c < catalog.categories.length && order.length < MAX_MOODS; c++) {
    var cat = catalog.categories[c]
    if (!cat || typeof cat.id !== "string" || !/^[a-z0-9][a-z0-9-]{0,40}$/.test(cat.id) || byId[cat.id]) continue
    var given = names && names.names ? names.names[cat.id] : ""
    byId[cat.id] = { id: cat.id, label: plain(given || cat.label || cat.id, MAX_NAME),
                     sourceLabel: plain(cat.label, 80), tracks: [] }
    order.push(cat.id)
  }
  // The stepping order comes from categories.json where it names a category;
  // any it leaves out keep the catalog's order after those.
  var wanted = names && Array.isArray(names.order) ? names.order : []
  var sorted = [], used = {}
  for (var w = 0; w < wanted.length; w++) {
    var id = String(wanted[w])
    if (byId[id] && !used[id]) { sorted.push(id); used[id] = true }
  }
  for (var o = 0; o < order.length; o++) if (!used[order[o]]) sorted.push(order[o])

  var count = 0
  for (var t = 0; t < catalog.tracks.length && count < MAX_TRACKS; t++) {
    var raw = catalog.tracks[t]
    var mood = raw ? byId[String(raw.category)] : null
    var loc = raw ? location(raw.location, archives) : null
    if (!mood || !loc || typeof raw.id !== "string" || raw.id.length > 200 || out.tracks[raw.id]
        || !isCount(raw.size, 64 * 1024 * 1024) || raw.size === 0) {
      out.skipped++
      continue
    }
    var seconds = typeof raw.seconds === "number" && raw.seconds > 0 && raw.seconds < 3600 ? raw.seconds : 0
    var track = { id: raw.id, mood: mood.id, title: plain(raw.title), creator: plain(raw.creator),
                  page: isHttps(raw.page) ? raw.page : "", license: plain(raw.license, 40),
                  size: raw.size, seconds: seconds, location: loc }
    out.tracks[track.id] = track
    mood.tracks.push(track.id)
    count++
  }
  for (var m = 0; m < sorted.length; m++) if (byId[sorted[m]].tracks.length > 0) out.moods.push(byId[sorted[m]])
  if (out.moods.length === 0) out.error = "the catalog has no playable tracks"
  return out
}

// What mood_fetch.py is asked for: the location plus the size and where to start.
function fetchSpec(track, startFraction) {
  var spec = {}
  for (var key in track.location) spec[key] = track.location[key]
  spec.size = track.size
  spec.start = startFraction > 0 && startFraction < 0.98 ? startFraction : 0
  return spec
}
