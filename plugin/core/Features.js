.pragma library

// What the music is doing, by position in the track.
//
// The fetcher measures the track once (mood_fetch.py) and sends rows of five
// bytes, one row per `hop` seconds: loudness, a low, a middle and a high band
// (each a level in dB squeezed into 0-255) and an onset strength that is zero
// except where something starts. This keeps them and answers "what is it
// doing at second t?" with numbers from 0 to 1, scaled to this track's own
// range so a quiet master and a loud one move a visual the same amount.
//
// Rows arrive in batches while the track is already playing, so the range is
// re-measured as each batch lands and settles within the first seconds.

var MAX_FRAMES = 60 * 60 * 25   // an hour of music; anything longer is refused
var MAX_BATCH = 4000
var CHANNELS = 4

function create() {
  var s = { hop: 0.04, rows: [], hist: [], floor: [0, 0, 0, 0], top: [255, 255, 255, 255], broken: "" }

  function clearHist() {
    s.hist = []
    for (var c = 0; c < CHANNELS; c++) {
      var h = []
      for (var i = 0; i < 256; i++) h.push(0)
      s.hist.push(h)
    }
  }

  function percentile(h, total, p) {
    var want = total * p, seen = 0
    for (var i = 0; i < 256; i++) {
      seen += h[i]
      if (seen >= want) return i
    }
    return 255
  }

  // The loud end is the 95th percentile, so one peak doesn't flatten the rest.
  // The quiet end is the 10th, held within about 30 dB (90 steps) of the loud
  // end and at least 6 dB below it.
  function remeasure() {
    for (var c = 0; c < CHANNELS; c++) {
      var h = s.hist[c], total = 0
      // Digital silence says nothing about the track's range.
      for (var i = 8; i < 256; i++) total += h[i]
      if (total < 10) { s.floor[c] = 0; s.top[c] = 255; continue }
      var quiet = h.slice(); for (var z = 0; z < 8; z++) quiet[z] = 0
      var top = percentile(quiet, total, 0.95)
      var floor = Math.max(percentile(quiet, total, 0.10), top - 90)
      s.top[c] = top
      s.floor[c] = Math.min(floor, top - 18)
    }
  }

  s.reset = function() {
    s.rows = []; s.broken = ""; s.hop = 0.04
    s.floor = [0, 0, 0, 0]; s.top = [255, 255, 255, 255]
    clearHist()
  }

  // Add a batch that starts at row `index`. Returns false, and stops trusting
  // the track's features, when the batch isn't what the fetcher would send.
  s.add = function(index, hop, frames) {
    if (s.broken) return false
    if (!Array.isArray(frames) || frames.length === 0 || frames.length > MAX_BATCH
        || index !== s.rows.length || !(hop >= 0.01 && hop <= 0.2)
        || s.rows.length + frames.length > MAX_FRAMES) {
      s.broken = "unexpected feature data"
      return false
    }
    s.hop = hop
    for (var i = 0; i < frames.length; i++) {
      var f = frames[i], row = []
      if (!Array.isArray(f) || f.length < 5) { s.broken = "unexpected feature data"; return false }
      for (var c = 0; c < 5; c++) {
        var v = Math.round(Number(f[c]))
        row.push(v >= 0 && v <= 255 ? v : 0)
      }
      for (var k = 0; k < CHANNELS; k++) s.hist[k][row[k]]++
      s.rows.push(row)
    }
    remeasure()
    return true
  }

  s.fail = function(why) { s.broken = String(why || "unavailable") }
  s.seconds = function() { return s.rows.length * s.hop }
  s.indexAt = function(t) { return Math.floor(t / s.hop) }
  s.covers = function(t) { var i = s.indexAt(t); return !s.broken && i >= 0 && i < s.rows.length }

  function scale(c, v) {
    var span = s.top[c] - s.floor[c]
    if (span <= 0) return 0
    return Math.max(0, Math.min(1, (v - s.floor[c]) / span))
  }

  // { level, low, mid, high } at second t, each 0-1, or null when the track
  // has no measurement there (so a visual can go calm rather than guess).
  s.at = function(t) {
    if (!s.covers(t)) return null
    var r = s.rows[s.indexAt(t)]
    return { level: scale(0, r[0]), low: scale(1, r[1]), mid: scale(2, r[2]), high: scale(3, r[3]) }
  }

  // The strongest onset in rows (from, to], 0-1; 0 when there was none.
  s.onsetBetween = function(from, to) {
    var best = 0
    var a = Math.max(0, from + 1), b = Math.min(s.rows.length - 1, to)
    // A jump (a seek, a resume) is not a run of onsets.
    if (b - a > 25) a = b
    for (var i = a; i <= b; i++) if (s.rows[i][4] > best) best = s.rows[i][4]
    return best / 255
  }

  s.reset()
  return s
}
