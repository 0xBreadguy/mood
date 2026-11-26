.pragma library

// The playback core's decisions, with no I/O of its own.
//
// It is told what happened (a command, a player event, a fetcher line, a
// timer) and answers by calling the effects it was given: start the player,
// fetch a track, set a timer, tell the interface. Service.qml supplies the real
// effects; the tests supply recording ones and a hand-wound clock.
//
// State is one of:
//   stopped   nothing is loaded and nothing is wanted
//   loading   a track was asked for and no sound has come out yet
//   playing   the player says audio is running
//   paused    a track is held at a position and can resume from it
//   failed    the track, its source or the player went wrong
//   offline   the network could not be reached
// A state changes only on evidence: "playing" waits for the player to say so.
//
// Effects (fx):
//   now() -> ms                       timer(name, ms)  ms < 0 cancels
//   startPlayer() / stopPlayer()      playerLoad(seq, title)
//   playerCommand([..])               playerAsk(property)
//   startFetcher(seq, track, startFraction) / stopFetcher()
//   featuresReset()                   save(moodId)
//   emit(name, a, b)                  changed()

var COALESCE_MS = 260            // a run of skips or mood steps loads once, this long after the last
var LOAD_TIMEOUT_MS = 25000      // no sound this long after asking: give up on the attempt
var NAME_MS = 1500               // how long the mood's name may show after a switch
var SYNC_MS = 5000               // how often the playing position is checked against the player
var RELEASE_MS = 10 * 60000      // paused this long: let the player process go
var IDLE_RELEASE_MS = 60000      // stopped or failed with a player still up: let it go sooner
var SOURCE_RETRY_MS = 1500       // a broken track: move on to another after this
var SOURCE_SKIPS = 2             // broken tracks moved past in a row before waiting properly
var BACKOFF_MS = [4000, 12000, 30000, 90000, 300000]

function create(fx, catalog, deps, options) {
  var o = options || {}
  var e = {
    status: "stopped", wantPlay: false, moodIndex: 0,
    seq: 0, loadedSeq: -1, playingSeq: -1, player: "down", playerPaused: false,
    failure: null, attempts: 0, sourceFails: 0, skipOnRetry: false, retryAt: 0,
    released: false, resumeFraction: 0, startFraction: 0, fetchFailure: null,
    posBase: 0, posWall: 0, posRunning: false, duration: 0,
    trackSerial: 0, nameShowing: false, nameText: "", nameDirection: 0,
    bytesLast: 0, bytesTotal: 0, verified: null, firstByteMs: 0
  }
  var queues = {}

  for (var i = 0; i < catalog.moods.length; i++)
    if (catalog.moods[i].id === o.mood) e.moodIndex = i

  function mood() { return catalog.moods[e.moodIndex] || null }
  function queue() {
    var m = mood()
    if (!m) return null
    if (!queues[m.id]) queues[m.id] = deps.makeQueue(m.tracks)
    return queues[m.id]
  }
  function track() {
    var q = queue()
    var id = q ? q.current() : null
    return id === null ? null : (catalog.tracks[id] || null)
  }

  function position() {
    return e.posRunning ? e.posBase + (fx.now() - e.posWall) / 1000 : e.posBase
  }

  // The whole track's length in seconds, from the catalog or, failing that,
  // from what the player says of the part it was given. 0 when unknown.
  function wholeSeconds() {
    var t = track()
    if (t && t.seconds > 0) return t.seconds
    return e.duration > 0 && e.startFraction < 1 ? e.duration / (1 - e.startFraction) : 0
  }

  // How far through the whole track playback is, 0-1, for resuming later.
  function fractionNow() {
    var whole = wholeSeconds()
    if (!(whole > 0)) return 0
    return Math.max(0, Math.min(0.97, e.startFraction + position() / whole))
  }

  // Seconds into the track, as a listener would count them. position() counts
  // from where the player's stream began, which after a long pause is part way in.
  function trackPosition() {
    return e.startFraction * wholeSeconds() + position()
  }

  function clearTimers() {
    fx.timer("load", -1); fx.timer("retry", -1); fx.timer("watchdog", -1)
    fx.timer("release", -1); fx.timer("sync", -1)
  }

  // Drop whatever is loading or loaded, without deciding what comes next.
  function drop() {
    e.seq++
    clearTimers()
    fx.stopFetcher()
    if (e.player === "ready" && e.loadedSeq >= 0) fx.playerCommand(["stop"])
    e.loadedSeq = -1
    e.posRunning = false
    e.released = false
    e.retryAt = 0
    e.fetchFailure = null
    fx.featuresReset()
  }

  function rest(status) {
    e.status = status
    if (e.player !== "down") fx.timer("release", status === "paused" ? RELEASE_MS : IDLE_RELEASE_MS)
  }

  function startLoad(delay, fraction) {
    drop()
    if (!track()) { fail("source", "nothing to play in this mood"); return }
    e.status = "loading"
    e.startFraction = fraction > 0 ? fraction : 0
    fx.timer("load", Math.max(0, delay))
  }

  function beginFetch() {
    var t = track()
    if (!t) { fail("source", "nothing to play in this mood"); return }
    fx.startFetcher(e.seq, t, e.startFraction)
    fx.timer("watchdog", LOAD_TIMEOUT_MS)
  }

  function fail(kind, detail) {
    var known = kind === "offline" || kind === "player" || kind === "changed" ? kind : "source"
    drop()
    e.failure = { kind: known, detail: String(detail || "").slice(0, 160) }
    e.status = known === "offline" ? "offline" : "failed"
    fx.emit("failed", known)
    if (!e.wantPlay) { rest(e.status); return }
    var broken = known === "source" || known === "changed"
    var delay
    if (broken && e.sourceFails < SOURCE_SKIPS) {
      // One bad track shouldn't stop the music: try another, but only a couple
      // of times before backing off, or a dead source would be walked end to end.
      e.sourceFails++
      delay = SOURCE_RETRY_MS
    } else {
      delay = BACKOFF_MS[Math.min(e.attempts, BACKOFF_MS.length - 1)]
      e.attempts++
    }
    e.skipOnRetry = broken
    e.retryAt = fx.now() + delay
    fx.timer("retry", delay)
  }

  function setPaused(paused) {
    if (paused) {
      e.posBase = position()
      e.posRunning = false
      e.status = "paused"
      fx.timer("sync", -1)
      fx.timer("release", RELEASE_MS)
    } else {
      e.posWall = fx.now()
      e.posRunning = true
      e.status = "playing"
      fx.timer("release", -1)
      fx.timer("sync", SYNC_MS)
      fx.playerAsk("time-pos")
    }
  }

  // ---- commands ------------------------------------------------------------

  e.play = function() {
    e.wantPlay = true
    if (e.status === "playing" || e.status === "loading") return
    if (e.status === "paused" && !e.released && e.loadedSeq === e.seq && e.player === "ready") {
      fx.playerCommand(["set_property", "pause", false])
      return
    }
    var fraction = e.status === "paused" && e.released ? e.resumeFraction : 0
    var q = queue()
    if (q && q.current() === null) q.next()
    startLoad(0, fraction)
    fx.changed()
  }

  e.pause = function() {
    e.wantPlay = false
    if (e.status === "playing") {
      fx.playerCommand(["set_property", "pause", true])
    } else if (e.status === "loading" || e.status === "failed" || e.status === "offline") {
      drop()
      e.failure = null
      rest("stopped")
    }
    fx.changed()
  }

  e.toggle = function() {
    if (e.status === "playing" || e.status === "loading") e.pause()
    else e.play()
  }

  e.stop = function() {
    e.wantPlay = false
    drop()
    e.failure = null
    e.status = "stopped"
    if (e.player !== "down") { e.player = "down"; fx.stopPlayer() }
    fx.changed()
  }

  e.skip = function() {
    var q = queue()
    if (!q || q.size() === 0) { fx.emit("refused", "skip"); return false }
    q.next()
    e.wantPlay = true
    fx.emit("skipped", 1)
    startLoad(COALESCE_MS, 0)
    fx.changed()
    return true
  }

  e.back = function() {
    var q = queue()
    if (!q || q.back() === null) {
      fx.emit("refused", "back")
      return false
    }
    e.wantPlay = true
    fx.emit("skipped", -1)
    startLoad(COALESCE_MS, 0)
    fx.changed()
    return true
  }

  function setMoodIndex(index, direction) {
    if (index === e.moodIndex || !catalog.moods[index]) return false
    e.moodIndex = index
    var m = mood()
    fx.save(m.id)
    e.nameText = m.label
    e.nameDirection = direction
    e.nameShowing = true
    fx.timer("name", NAME_MS)
    fx.emit("moodChanged", direction, m.label)
    queue().enter()
    if (e.wantPlay) {
      startLoad(COALESCE_MS, 0)
    } else {
      // A held track belonged to the mood that was left.
      drop()
      e.failure = null
      rest("stopped")
    }
    fx.changed()
    return true
  }

  // Step to the next or previous mood. The list wraps around.
  e.stepMood = function(delta) {
    var n = catalog.moods.length
    if (n < 2 || !delta) return false
    var d = delta > 0 ? 1 : -1
    return setMoodIndex(((e.moodIndex + d) % n + n) % n, d)
  }

  e.setMood = function(id) {
    for (var k = 0; k < catalog.moods.length; k++)
      if (catalog.moods[k].id === id) return k === e.moodIndex ? true : setMoodIndex(k, 0)
    return false
  }

  // ---- what happened -------------------------------------------------------

  e.onTimer = function(name) {
    if (name === "load") {
      if (e.status !== "loading") return
      if (e.player === "down") {
        e.player = "starting"
        fx.startPlayer()
        fx.timer("watchdog", LOAD_TIMEOUT_MS)
      } else if (e.player === "ready") {
        beginFetch()
      }
    } else if (name === "retry") {
      if ((e.status !== "failed" && e.status !== "offline") || !e.wantPlay) return
      if (e.skipOnRetry) queue().next()
      startLoad(0, 0)
    } else if (name === "watchdog") {
      if (e.status === "loading") fail(e.player === "ready" ? "offline" : "player",
                                       e.player === "ready" ? "no sound arrived in time" : "the player did not start")
    } else if (name === "sync") {
      if (e.status === "playing") { fx.playerAsk("time-pos"); fx.timer("sync", SYNC_MS) }
    } else if (name === "release") {
      if (e.player !== "ready" || e.status === "playing" || e.status === "loading") return
      if (e.status === "paused" && e.loadedSeq === e.seq) {
        e.resumeFraction = fractionNow()
        e.released = true
      }
      e.loadedSeq = -1
      e.player = "down"
      fx.stopPlayer()
    } else if (name === "name") {
      e.nameShowing = false
    }
    fx.changed()
  }

  e.onPlayerReady = function() {
    e.player = "ready"
    if (e.status === "loading") beginFetch()
    else fx.timer("release", IDLE_RELEASE_MS)
    fx.changed()
  }

  // info: { expected: bool, missing: bool }
  e.onPlayerExit = function(info) {
    var wasUp = e.player !== "down"
    e.player = "down"
    if (info && info.expected) { e.loadedSeq = -1; fx.changed(); return }
    if (e.status === "paused" && wasUp) {
      e.resumeFraction = fractionNow()
      e.released = true
      e.loadedSeq = -1
    } else if (e.status === "loading" || e.status === "playing") {
      e.loadedSeq = -1
      fail("player", info && info.missing ? "mpv is not installed" : "the player stopped")
    }
    fx.changed()
  }

  // A JSON line from the fetcher for load `seq`.
  e.onFetcher = function(seq, msg) {
    if (seq !== e.seq || !msg) return
    if (msg.ev === "ready") {
      if (e.status === "loading" && e.player === "ready") {
        e.loadedSeq = seq
        fx.playerLoad(seq, mood() ? mood().label : "mood")
      }
    } else if (msg.ev === "first") {
      e.firstByteMs = Number(msg.ms) || 0
    } else if (msg.ev === "done") {
      var wire = Number(msg.wire) || 0
      e.bytesLast = wire
      e.bytesTotal += wire
      e.verified = msg.verified === true ? true : (msg.verified === false ? false : null)
    } else if (msg.ev === "error") {
      e.fetchFailure = { kind: String(msg.kind || "source"), detail: String(msg.detail || "") }
      // Before any sound, that is the failure. After, the track plays out what
      // arrived and the failure is dealt with when it runs dry.
      if (e.status === "loading") fail(e.fetchFailure.kind, e.fetchFailure.detail)
    }
    fx.changed()
  }

  // The fetcher process ended. code < 0 means it could not be started at all.
  e.onFetcherExit = function(seq, code) {
    if (seq !== e.seq || code === 0 || e.fetchFailure) return
    e.fetchFailure = code < 0 ? { kind: "player", detail: "python3 is not installed" }
      : { kind: code === 2 ? "offline" : "source", detail: "the fetcher stopped (" + code + ")" }
    if (e.status === "loading") fail(e.fetchFailure.kind, e.fetchFailure.detail)
    fx.changed()
  }

  // An event from Mpv.feed().
  e.onPlayer = function(ev) {
    if (!ev) return
    if (ev.type === "pause") {
      e.playerPaused = ev.value
      if (e.loadedSeq === e.seq && e.playingSeq === e.seq && (e.status === "playing" || e.status === "paused")
          && (e.status === "paused") !== ev.value) {
        e.wantPlay = !ev.value
        setPaused(ev.value)
      }
    } else if (ev.type === "started") {
      if (ev.seq !== e.seq || e.loadedSeq !== ev.seq) return
      fx.timer("watchdog", -1)
      if (e.playingSeq !== ev.seq) {
        e.playingSeq = ev.seq
        e.trackSerial++
        queue().markHeard()
        e.attempts = 0
        e.sourceFails = 0
        e.failure = null
        e.posBase = 0
      }
      if (!e.wantPlay && !e.playerPaused) fx.playerCommand(["set_property", "pause", true])
      setPaused(!e.wantPlay || e.playerPaused)
    } else if (ev.type === "ended") {
      if (ev.seq !== e.seq) return
      if (ev.reason === "eof" && e.playingSeq === ev.seq) {
        if (e.fetchFailure) { fail(e.fetchFailure.kind, e.fetchFailure.detail) }
        else { queue().next(); startLoad(0, 0) }
      } else if (ev.reason === "error" || ev.reason === "eof") {
        var f = e.fetchFailure || { kind: "source", detail: ev.error || "the track would not play" }
        fail(f.kind, f.detail)
      }
    } else if (ev.type === "jump") {
      // A media key, by way of the player's playlist markers.
      if (ev.seq !== e.seq || e.loadedSeq !== ev.seq) return
      if (ev.dir > 0) { e.skip(); return }
      if (!e.back()) {
        // Nothing earlier, and the player has already left the track.
        var resume = e.wantPlay
        startLoad(0, 0)
        e.wantPlay = resume
      }
    } else if (ev.type === "idle") {
      // Stopped from outside (the desktop's "stop"), not by this engine.
      if ((e.status === "playing" || e.status === "paused") && e.loadedSeq === e.seq) {
        e.wantPlay = false
        drop()
        rest("stopped")
      }
    } else if (ev.type === "position") {
      if (e.loadedSeq === e.seq && ev.value >= 0) { e.posBase = ev.value; e.posWall = fx.now() }
      return
    } else if (ev.type === "duration") {
      if (ev.value > 0) e.duration = ev.value
      return
    }
    fx.changed()
  }

  // ---- what the interface may know ----------------------------------------

  e.position = position
  e.trackPosition = trackPosition
  e.track = track
  e.mood = mood
  e.canBack = function() { var q = queue(); return !!q && q.canBack() }
  e.retryInMs = function() { return e.retryAt > 0 ? Math.max(0, e.retryAt - fx.now()) : 0 }

  return e
}
