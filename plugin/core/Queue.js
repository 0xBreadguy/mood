.pragma library

// One mood's private queue: a shuffled bag of its tracks, the track that is
// current, the tracks actually heard before it, and the tracks stepped back
// over. Nothing here plays anything; the engine asks it what comes next.
//
//   next()   the next track: back over what `back` stepped past, else the bag
//   back()   the previous track that was heard, or null when there is none
//   enter()  called when the mood is chosen: keep an unheard current track,
//            else move on, so coming back to a mood doesn't replay its intro
//
// A track joins the history only once it was heard (markHeard), so skipping
// quickly through five tracks leaves no trail to walk back through.

var HISTORY_LIMIT = 50

function shuffled(ids, rng) {
  var out = ids.slice()
  for (var i = out.length - 1; i > 0; i--) {
    var j = Math.floor(rng() * (i + 1))
    var t = out[i]; out[i] = out[j]; out[j] = t
  }
  return out
}

function create(ids, rng) {
  var random = typeof rng === "function" ? rng : Math.random
  var all = (ids || []).slice()
  var q = { bag: [], history: [], forward: [], now: null, heard: false }

  function refill(avoid) {
    q.bag = shuffled(all, random)
    // The bag is drawn from its end. A new bag must not open with the track
    // that just played.
    if (q.bag.length > 1 && q.bag[q.bag.length - 1] === avoid) {
      var last = q.bag.length - 1
      var swap = Math.floor(random() * last)
      var t = q.bag[last]; q.bag[last] = q.bag[swap]; q.bag[swap] = t
    }
  }

  function remember() {
    if (q.now === null || !q.heard) return
    q.history.push(q.now)
    if (q.history.length > HISTORY_LIMIT) q.history.shift()
  }

  q.size = function() { return all.length }
  q.current = function() { return q.now }
  q.canBack = function() { return q.history.length > 0 }
  q.markHeard = function() { if (q.now !== null) q.heard = true }

  q.next = function() {
    if (all.length === 0) return null
    remember()
    if (q.forward.length > 0) {
      q.now = q.forward.pop()
    } else {
      if (q.bag.length === 0) refill(q.now)
      q.now = q.bag.pop()
    }
    q.heard = false
    return q.now
  }

  q.back = function() {
    if (q.history.length === 0) return null
    if (q.now !== null) q.forward.push(q.now)
    q.now = q.history.pop()
    q.heard = false
    return q.now
  }

  q.enter = function() {
    if (q.now === null || q.heard) return q.next()
    return q.now
  }

  return q
}
