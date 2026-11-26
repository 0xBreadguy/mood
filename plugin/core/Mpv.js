.pragma library

// The player's side of the conversation: which commands to send mpv over its
// JSON socket, and what its replies and events mean for the engine.
//
// Every track is loaded as the middle of a three-entry playlist:
//
//     [ back marker, the track, skip marker ]
//
// The markers are entries that cannot play. mpv ships with an MPRIS script on
// Omarchy, and the desktop's media keys reach it as "next" and "previous",
// which mpv answers by moving along its playlist. Landing on a marker is how
// the plugin learns a media key was pressed; it then loads the real next or
// previous track itself. The end of a track is reported by mpv directly.
//
// feed(message) returns engine events:
//   { type: "started", seq }                    audio for that load is playing
//   { type: "ended", seq, reason, error }       reason: "eof" | "error" | ...
//   { type: "jump", seq, dir }                  a media key: +1 next, -1 previous
//   { type: "pause", value }
//   { type: "idle" }
//   { type: "position", value } / { type: "duration", value }

var SKIP_MARKER = "null://mood-skip"
var BACK_MARKER = "null://mood-back"

function create() {
  var s = { nextId: 1, waiting: {}, entries: {}, current: null }

  function request(command, note) {
    var id = s.nextId++
    if (note) s.waiting[id] = note
    return { command: command, request_id: id }
  }

  // What to send once, when the socket connects.
  s.hello = function() {
    return [
      request(["observe_property", 1, "pause"]),
      request(["observe_property", 2, "idle-active"]),
      request(["observe_property", 3, "duration"])
    ]
  }

  // Load `path` as load number `seq`. `title` is what the desktop is told is
  // playing: the mood's name, never the track's.
  s.load = function(seq, path, title) {
    s.entries = {}
    s.current = null
    return [
      request(["set_property", "force-media-title", String(title || "mood")]),
      request(["loadfile", String(path), "replace"], { role: "track", seq: seq }),
      request(["loadfile", SKIP_MARKER, "append"], { role: "skip", seq: seq }),
      request(["loadfile", BACK_MARKER, "insert-at", 0], { role: "back", seq: seq }),
      request(["set_property", "pause", false])
    ]
  }

  s.command = function(command) { return request(command) }
  s.ask = function(property) { return request(["get_property", String(property)], { role: "ask", property: String(property) }) }

  s.feed = function(msg) {
    var out = []
    if (!msg || typeof msg !== "object") return out

    if (msg.request_id !== undefined && msg.event === undefined) {
      var note = s.waiting[msg.request_id]
      delete s.waiting[msg.request_id]
      if (!note) return out
      if (note.role === "ask") {
        if (msg.error === "success" && typeof msg.data === "number" && note.property === "time-pos")
          out.push({ type: "position", value: msg.data })
      } else if (msg.error === "success" && msg.data && typeof msg.data.playlist_entry_id === "number") {
        s.entries[msg.data.playlist_entry_id] = note
      } else if (note.role === "track") {
        out.push({ type: "ended", seq: note.seq, reason: "error", error: "the player refused the stream" })
      }
      return out
    }

    var entry = msg.playlist_entry_id !== undefined ? s.entries[msg.playlist_entry_id] : null
    switch (msg.event) {
    case "start-file":
      s.current = entry || null
      if (entry && entry.role === "skip") out.push({ type: "jump", seq: entry.seq, dir: 1 })
      else if (entry && entry.role === "back") out.push({ type: "jump", seq: entry.seq, dir: -1 })
      break
    case "playback-restart":
      if (s.current && s.current.role === "track") out.push({ type: "started", seq: s.current.seq })
      break
    case "end-file":
      if (entry && entry.role === "track")
        out.push({ type: "ended", seq: entry.seq, reason: String(msg.reason || ""), error: String(msg.file_error || "") })
      break
    case "property-change":
      if (msg.name === "pause" && typeof msg.data === "boolean") out.push({ type: "pause", value: msg.data })
      else if (msg.name === "idle-active" && msg.data === true) out.push({ type: "idle" })
      else if (msg.name === "duration" && typeof msg.data === "number") out.push({ type: "duration", value: msg.data })
      break
    }
    return out
  }

  return s
}

// The arguments mpv is started with: audio only, none of its own interface,
// and nothing read from the user's mpv configuration.
function launchArguments(socketPath, options) {
  var o = options || {}
  var args = [
    "--no-config", "--no-terminal", "--idle=yes", "--vid=no", "--vo=null", "--audio-display=no", "--sub=no",
    "--load-scripts=no", "--ytdl=no", "--osc=no", "--load-stats-overlay=no", "--load-console=no",
    "--load-auto-profiles=no", "--load-select=no", "--load-positioning=no", "--load-commands=no",
    "--load-context-menu=no", "--input-default-bindings=no", "--input-builtin-bindings=no",
    "--audio-client-name=mood", "--force-media-title=mood", "--volume=100",
    "--cache=yes", "--demuxer-max-bytes=32MiB", "--demuxer-max-back-bytes=1MiB",
    "--input-ipc-server=" + socketPath
  ]
  if (o.silent) args.push("--ao=null")
  if (o.mprisScript) args.push("--script=" + o.mprisScript)
  return args
}
