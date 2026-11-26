import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "core/Catalog.js" as Catalog
import "core/Engine.js" as Engine
import "core/Features.js" as Features
import "core/Mpv.js" as Mpv
import "core/Queue.js" as Queue

// The playback core: one instance for every bar on every screen.
//
// The decisions are in core/Engine.js. This file gives them hands: the player
// (an mpv process spoken to over its JSON socket), the fetcher (one short
// Python process per track), timers, the catalog and state files, and the
// `mood` IPC target. Nothing here draws anything.
//
// Nothing runs until something is played: no player, no fetcher, no network.
// The player is let go again after a long pause (Engine.RELEASE_MS).
Item {
  id: root

  property var shell: null
  property var manifest: null

  // ---- what a bar widget may read ------------------------------------------

  // False until the catalog has been read. `problem` says why it never will be.
  property bool ready: false
  property string problem: ""

  // stopped | loading | playing | paused | failed | offline. (Not called `state`:
  // every QML Item already has a property of that name.)
  property string playback: "stopped"
  // "" | offline | source | changed | player | catalog
  property string failureKind: ""
  property string failureDetail: ""

  // [{ id, label, count }] in stepping order, and where in it the mood is.
  property var moods: []
  property int moodIndex: 0
  readonly property string moodId: moods[moodIndex] ? moods[moodIndex].id : ""
  readonly property string moodLabel: moods[moodIndex] ? moods[moodIndex].label : ""

  // True for Engine.NAME_MS after a mood switch.
  property bool nameShowing: false
  property string nameText: ""
  property int nameDirection: 0

  // Goes up by one each time a new track is actually heard.
  property int trackSerial: 0
  property bool canBack: false
  // Whether the popup's first-open bar controls highlight has been dismissed.
  property bool guideDismissed: false

  // direction: +1 forward, -1 back. For moodChanged, 0 means chosen by name.
  signal skipped(int direction)
  signal moodChanged(int direction, string label)
  signal refused(string what)
  signal failed(string kind)
  signal popupRequested()

  // What the music is doing right now, each 0-1, measured from the plugin's
  // own audio. `available` is false whenever there is no measurement for this
  // moment: not playing, nobody asked, ffmpeg missing, analysis still behind.
  // A visual should go calm then, not guess.
  readonly property QtObject features: QtObject {
    property bool available: false
    property string unavailableBecause: "not playing"
    property real level: 0
    property real low: 0
    property real mid: 0
    property real high: 0
    // Strength of the latest onset; onsetCount goes up by one at each.
    property real onset: 0
    property int onsetCount: 0
  }

  // ---- what a bar widget may set -------------------------------------------

  // Appear to the desktop as a media player, so its media keys work.
  property bool mediaKeys: true
  // "null" plays in real time into nothing, for development: the widget's
  // `audio` setting, or MOOD_AUDIO=null in the shell's environment. Applies the
  // next time the player starts.
  property string audioSetting: "auto"
  readonly property string audio: audioSetting === "null" || Quickshell.env("MOOD_AUDIO") === "null" ? "null" : "auto"

  // Widgets that draw from `features` say so; tracks are only measured while
  // one does.
  property var featureClients: ({})
  readonly property bool featuresWanted: Object.keys(featureClients).length > 0
  function setFeatureClient(key, wanted) {
    var next = {}
    for (var k in featureClients) if (k !== key) next[k] = true
    if (wanted) next[key] = true
    featureClients = next
  }

  // One widget answers a request for the popup, whichever claims it first.
  property bool popupClaimed: true
  function claimPopup() {
    if (popupClaimed) return false
    popupClaimed = true
    return true
  }

  // ---- commands ------------------------------------------------------------

  function toggle() { return run("toggle") }
  function play() { return run("play") }
  function pause() { return run("pause") }
  function stop() { return run("stop") }
  function skip() { return run("skip") }
  function back() { return run("back") }
  function stepMood(delta) { return run("stepMood", Number(delta) || 0) }
  function setMood(id) { return run("setMood", String(id || "")) }
  function dismissGuide() {
    if (guideDismissed) return
    guideDismissed = true
    if (prepared) {
      saveTimer.stop()
      saveState()
    } else {
      saveTimer.restart()
    }
  }

  function run(name, arg) {
    if (!engine) return problem ? "unavailable" : "not ready"
    var result = engine[name](arg)
    return result === false ? "refused" : "ok"
  }

  function status() {
    var e = engine
    var t = e ? e.track() : null
    return JSON.stringify({
      state: root.playback,
      mood: { id: root.moodId, label: root.moodLabel, index: root.moodIndex, of: root.moods.length },
      failure: root.failureKind ? { kind: root.failureKind, detail: root.failureDetail,
                                    retryInSeconds: e ? Math.round(e.retryInMs() / 1000) : 0 } : null,
      canBack: root.canBack,
      track: t && root.playback !== "stopped" ? { id: t.id, title: t.title, creator: t.creator, license: t.license, page: t.page } : null,
      positionSeconds: e && (root.playback === "playing" || root.playback === "paused") ? Math.round(e.trackPosition()) : null,
      features: { wanted: root.featuresWanted, available: root.features.available, why: root.features.available ? "" : root.features.unavailableBecause },
      player: e ? e.player : "down",
      mediaKeys: root.mediaKeys ? (root.mprisScript !== "" ? "on" : "unavailable: mpv's MPRIS script was not found") : "off",
      audio: root.audio,
      data: { lastTrackBytes: e ? e.bytesLast : 0, sessionBytes: e ? e.bytesTotal : 0, firstByteMs: e ? e.firstByteMs : 0,
              lastTrackVerified: e ? e.verified : null },
      catalog: { generated: root.catalogGenerated, tracks: root.catalogTracks, moods: root.moods.length, problem: root.problem }
    })
  }

  // ---- internals -----------------------------------------------------------

  property var engine: null
  property var session: null
  property var store: Features.create()
  property int lastFeatureIndex: -1
  property var pendingEvents: []
  property bool syncQueued: false
  property string mprisScript: ""
  property string catalogGenerated: ""
  property int catalogTracks: 0
  property bool prepared: false
  property bool namesSettled: false
  property bool stateSettled: false
  property string savedMood: ""

  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mood"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/mood"
  readonly property string socketPath: runtimeDir + "/mpv.sock"
  readonly property string fetchScript: localPath(Qt.resolvedUrl("bin/mood_fetch.py"))

  function localPath(url) {
    return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
  }

  function fifoPath(seq) { return runtimeDir + "/" + seq + ".fifo" }

  function begin() {
    if (engine || problem || !prepared || !catalogFile.loaded || !namesSettled || !stateSettled) return
    var catalog = Catalog.build(catalogFile.text(), namesFile.loaded ? namesFile.text() : "{}")
    if (catalog.error) { fault(catalog.error); return }
    if (catalog.skipped > 0) console.warn("mood: " + catalog.skipped + " catalog entries were not usable and were left out")
    var list = []
    for (var i = 0; i < catalog.moods.length; i++)
      list.push({ id: catalog.moods[i].id, label: catalog.moods[i].label, count: catalog.moods[i].tracks.length })
    catalogGenerated = catalog.generated
    catalogTracks = Object.keys(catalog.tracks).length
    engine = Engine.create(effects(), catalog, { makeQueue: Queue.create }, { mood: savedMood })
    moods = list
    ready = true
    sync()
  }

  function fault(why) {
    problem = why
    playback = "failed"
    failureKind = "catalog"
    failureDetail = why
    console.warn("mood: " + why)
  }

  function effects() {
    return {
      now: function() { return Date.now() },
      timer: function(name, ms) {
        var t = timers[name]
        if (!t) return
        if (ms < 0) { t.stop(); return }
        t.interval = Math.max(1, ms)
        t.restart()
      },
      startPlayer: root.startPlayer,
      stopPlayer: root.stopPlayer,
      playerLoad: function(seq, title) {
        if (!session) return
        var commands = session.load(seq, root.fifoPath(seq), title)
        for (var i = 0; i < commands.length; i++) root.send(commands[i])
      },
      playerCommand: function(command) { if (session) root.send(session.command(command)) },
      playerAsk: function(property) { if (session) root.send(session.ask(property)) },
      startFetcher: root.startFetcher,
      stopFetcher: root.stopFetcher,
      featuresReset: function() {
        root.store.reset()
        root.lastFeatureIndex = -1
        root.calm(root.featuresWanted ? "waiting for the track" : "nothing is drawing from them")
      },
      save: function(moodId) { root.savedMood = moodId; saveTimer.restart() },
      emit: function(name, a, b) { root.pendingEvents.push([name, a, b]); root.queueSync() },
      changed: root.queueSync
    }
  }

  function queueSync() {
    if (syncQueued) return
    syncQueued = true
    Qt.callLater(sync)
  }

  // Copy the engine's state into properties, then deliver its events, so a
  // handler of `skipped` already sees the state the skip led to.
  function sync() {
    syncQueued = false
    var e = engine
    if (!e) return
    playback = e.status
    // The last failure is only news while it is the current state; during the
    // retry that follows, the state is "loading" and nothing is wrong yet.
    var failing = (e.status === "failed" || e.status === "offline") && !!e.failure
    failureKind = failing ? e.failure.kind : ""
    failureDetail = failing ? Catalog.plain(e.failure.detail, 160) : ""
    moodIndex = e.moodIndex
    nameShowing = e.nameShowing
    nameText = e.nameText
    nameDirection = e.nameDirection
    trackSerial = e.trackSerial
    canBack = e.canBack()
    var events = pendingEvents
    pendingEvents = []
    for (var i = 0; i < events.length; i++) {
      var ev = events[i]
      if (ev[0] === "skipped") skipped(ev[1])
      else if (ev[0] === "moodChanged") moodChanged(ev[1], ev[2])
      else if (ev[0] === "refused") refused(ev[1])
      else if (ev[0] === "failed") failed(ev[1])
    }
  }

  // ---- the player ----------------------------------------------------------

  function startPlayer() {
    if (player.running) { player.restartWanted = true; return }
    session = null
    player.expected = false
    player.everStarted = false
    player.exitCode = -1
    player.command = ["setpriv", "--pdeathsig", "TERM", "mpv"].concat(Mpv.launchArguments(socketPath, {
      silent: root.audio === "null",
      mprisScript: root.mediaKeys ? root.mprisScript : ""
    }))
    player.running = true
    connectTimer.tries = 0
    connectTimer.start()
  }

  function stopPlayer() {
    player.restartWanted = false
    if (!player.running) return
    player.expected = true
    if (socket.connected && session) send(session.command(["quit"]))
    connectTimer.stop()
    socket.connected = false
    session = null
    player.running = false
  }

  function send(message) {
    if (!socket.connected) return
    socket.write(JSON.stringify(message) + "\n")
    if (typeof socket.flush === "function") socket.flush()
  }

  function fromPlayer(line) {
    if (!session || !engine || line.length > 65536) return
    var message
    try { message = JSON.parse(line) } catch (e) { return }
    var events = session.feed(message)
    for (var i = 0; i < events.length; i++) engine.onPlayer(events[i])
  }

  Process {
    id: player
    property bool expected: false
    property bool everStarted: false
    property bool restartWanted: false
    property int exitCode: -1
    onStarted: everStarted = true
    onExited: function(code) { exitCode = code }
    onRunningChanged: if (!running) Qt.callLater(root.playerGone)
  }

  function playerGone() {
    if (player.running) return
    var expected = player.expected
    player.expected = false
    connectTimer.stop()
    socket.connected = false
    session = null
    if (player.restartWanted) {
      // The engine has already asked for a new one; this exit is old news.
      player.restartWanted = false
      startPlayer()
      return
    }
    // setpriv exits 127 when mpv is not there to run.
    var missing = !expected && (player.exitCode === 127 || !player.everStarted)
    if (engine) engine.onPlayerExit({ expected: expected, missing: missing })
  }

  Socket {
    id: socket
    path: root.socketPath
    parser: SplitParser { onRead: function(line) { root.fromPlayer(line) } }
    onConnectionStateChanged: {
      if (!connected || root.session || !player.running) return
      connectTimer.stop()
      root.session = Mpv.create()
      var hello = root.session.hello()
      for (var i = 0; i < hello.length; i++) root.send(hello[i])
      if (root.engine) root.engine.onPlayerReady()
    }
  }

  // mpv makes its socket a moment after it starts. Keep knocking until it
  // answers; the engine's own watchdog gives up if it never does.
  Timer {
    id: connectTimer
    property int tries: 0
    interval: 40
    repeat: true
    onTriggered: {
      tries++
      if (socket.connected || !player.running || tries > 500) { stop(); return }
      socket.connected = true
    }
  }

  // ---- the fetcher ---------------------------------------------------------

  property var fetcher: null

  function startFetcher(seq, track, startFraction) {
    stopFetcher()
    var command = ["python3", "-I", fetchScript, "--out", fifoPath(seq),
                   "--spec", JSON.stringify(Catalog.fetchSpec(track, startFraction))]
    if (featuresWanted) command.push("--analyze")
    fetcher = fetcherComponent.createObject(root, { seq: seq, command: command })
    fetcher.running = true
  }

  function stopFetcher() {
    var f = fetcher
    fetcher = null
    if (!f) return
    f.abandoned = true
    if (f.running) f.running = false
    else f.destroy()
  }

  function fromFetcher(seq, line) {
    if (!engine || seq !== engine.seq || line.length > 400000) return
    var message
    try { message = JSON.parse(line) } catch (e) { return }
    if (!message || typeof message.ev !== "string") return
    if (message.ev === "features") {
      if (!store.add(message.i, message.hop, message.frames)) calm("the measurement was not usable")
    } else if (message.ev === "nofeatures") {
      store.fail(Catalog.plain(message.why, 80))
      calm(store.broken)
    } else {
      engine.onFetcher(seq, message)
    }
  }

  function fetcherGone(f) {
    if (!f || f.running) return
    if (root.fetcher === f) root.fetcher = null
    if (!f.abandoned && engine) engine.onFetcherExit(f.seq, f.everStarted ? f.exitCode : -1)
    f.destroy()
  }

  Component {
    id: fetcherComponent
    Process {
      id: one
      property int seq: 0
      property int exitCode: 0
      property bool everStarted: false
      property bool abandoned: false
      stdout: SplitParser { onRead: function(line) { if (!one.abandoned) root.fromFetcher(one.seq, line) } }
      onStarted: everStarted = true
      onExited: function(code) { exitCode = code }
      onRunningChanged: if (!running) Qt.callLater(function() { root.fetcherGone(one) })
    }
  }

  // ---- features ------------------------------------------------------------

  function calm(why) {
    features.available = false
    features.unavailableBecause = why
    features.level = 0
    features.low = 0
    features.mid = 0
    features.high = 0
    features.onset = 0
  }

  Timer {
    interval: 40
    repeat: true
    running: root.playback === "playing" && root.featuresWanted
    onRunningChanged: if (!running) root.calm(root.playback === "playing" ? "nothing is drawing from them" : "not playing")
    onTriggered: {
      var t = root.engine.position()
      var now = root.store.at(t)
      if (!now) {
        if (root.features.available || root.features.unavailableBecause === "not playing")
          root.calm(root.store.broken || "no measurement for this moment")
        return
      }
      var index = root.store.indexAt(t)
      var hit = root.lastFeatureIndex < 0 ? 0 : root.store.onsetBetween(root.lastFeatureIndex, index)
      root.lastFeatureIndex = index
      root.features.level = now.level
      root.features.low = now.low
      root.features.mid = now.mid
      root.features.high = now.high
      if (hit > 0) {
        root.features.onset = hit
        root.features.onsetCount += 1
      }
      root.features.unavailableBecause = ""
      root.features.available = true
    }
  }

  // ---- timers the engine sets by name --------------------------------------

  readonly property var timers: ({ load: loadTimer, retry: retryTimer, watchdog: watchdogTimer,
                                   release: releaseTimer, sync: syncTimer, name: nameTimer })
  Timer { id: loadTimer; onTriggered: root.engine.onTimer("load") }
  Timer { id: retryTimer; onTriggered: root.engine.onTimer("retry") }
  Timer { id: watchdogTimer; onTriggered: root.engine.onTimer("watchdog") }
  Timer { id: releaseTimer; onTriggered: root.engine.onTimer("release") }
  Timer { id: syncTimer; onTriggered: root.engine.onTimer("sync") }
  Timer { id: nameTimer; onTriggered: root.engine.onTimer("name") }

  // ---- files ---------------------------------------------------------------

  FileView {
    id: catalogFile
    path: root.localPath(Qt.resolvedUrl("../catalog/catalog.json"))
    onLoaded: root.begin()
    onLoadFailed: root.fault("the catalog could not be read")
  }

  FileView {
    id: namesFile
    path: root.localPath(Qt.resolvedUrl("../catalog/categories.json"))
    onLoaded: { root.namesSettled = true; root.begin() }
    onLoadFailed: { root.namesSettled = true; root.begin() }
  }

  // Remembered between sessions outside the plugin's folder, in the user's
  // state directory: the last mood and whether the first-open bar controls
  // highlight has been dismissed.
  FileView {
    id: stateFile
    path: root.stateDir + "/state.json"
    printErrors: false
    onLoaded: {
      try {
        var saved = JSON.parse(text())
        if (saved && typeof saved.mood === "string" && saved.mood.length < 64) root.savedMood = saved.mood
        if (saved && saved.guideDismissed === true) root.guideDismissed = true
      } catch (e) {}
      root.stateSettled = true
      root.begin()
    }
    onLoadFailed: { root.stateSettled = true; root.begin() }
  }

  function saveState() {
    stateFile.setText(JSON.stringify({
      version: 1,
      mood: root.savedMood || root.moodId,
      guideDismissed: root.guideDismissed
    }) + "\n")
  }

  Timer {
    id: saveTimer
    interval: 800
    onTriggered: root.saveState()
  }

  // Make the two directories, and find mpv's MPRIS script if it is installed.
  Process {
    id: prepare
    running: true
    command: ["sh", "-c",
      'mkdir -p -m 700 -- "$1" "$2"; ' +
      'for f in /etc/mpv/scripts/mpris.so /usr/lib/mpv-mpris/mpris.so /usr/share/mpv/scripts/mpris.so; do ' +
      'if [ -e "$f" ]; then printf "%s\\n" "$f"; break; fi; done; exit 0',
      "mood", root.runtimeDir, root.stateDir]
    stdout: SplitParser { onRead: function(line) { if (/^\/[\w\/.-]+\.so$/.test(line)) root.mprisScript = line } }
    onRunningChanged: if (!running) { root.prepared = true; root.begin() }
  }

  Component.onDestruction: {
    stopFetcher()
    stopPlayer()
  }

  // ---- IPC: omarchy-shell mood <verb> --------------------------------------

  ShellIpc {
    target: "mood"

    function toggle(): string { return root.toggle() }
    function play(): string { return root.play() }
    function pause(): string { return root.pause() }
    function stop(): string { return root.stop() }
    function skip(): string { return root.skip() }
    function back(): string { return root.back() }
    // step +1 or step -1: the next or previous mood, wrapping around.
    function step(delta: string): string {
      var d = parseInt(delta, 10)
      if (!(d === 1 || d === -1)) return "expected 1 or -1"
      return root.stepMood(d)
    }
    // set <mood id>, as listed by `moods`.
    function set(id: string): string { return root.setMood(id) }
    function moods(): string { return JSON.stringify(root.moods) }
    function popup(): string {
      root.popupClaimed = false
      root.popupRequested()
      var answered = root.popupClaimed
      root.popupClaimed = true
      return answered ? "ok" : "no widget on the bar"
    }
    function status(): string { return root.status() }
  }
}
