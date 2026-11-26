# Playback: how it works, why this way, and what it weighs

Measured on 2026-11-21 on one machine (Omarchy 4.5.0, Quickshell 0.3.2,
mpv 0.41, ffmpeg 9.0, Python 3.14), inside Omabox boxes, on one connection.
Nobody heard any of it; see [what wasn't checked](#what-wasnt-checked).

## The shape

```text
bar item ── Service.qml ── core/Engine.js   decides: state, queue, retries
                │
                ├── mpv            one process while playing or paused, spoken
                │                  to over its JSON socket
                └── mood_fetch.py  one short process per track: fetches the
                    │              bytes into a named pipe mpv reads
                    └── ffmpeg     once per track, a second or two: measures
                                   loudness, three bands and onsets
```

Nothing runs until something is played: no player, no fetcher, no network
request, no timer. A track's bytes pass through memory and are never written
to disk. The only file the plugin writes is `~/.local/state/mood/state.json`,
which holds the last mood and first-open guide state.

## Why mpv

A default Omarchy install already ships everything used here: `mpv`,
`mpv-mpris`, `ffmpeg`, `python`, `socat`, `qt6-multimedia` and PipeWire are all
in Omarchy's own package lists. So the choice added no dependency whichever
way it went, and was made on what each could do and what it weighed. All three
were run in a box playing the same 2.8 MB track.

| Candidate | Private memory while playing | Verdict |
| --- | --- | --- |
| **mpv**, audio only, its scripts and interface off | 41 MB (21 MB idle) | Chosen. |
| `ffmpeg` decoding into `pw-cat` | 31 MB | Lighter by a quarter, but pause is stopping the process (the stream starves rather than corks), and there is no position, seek or end-of-track signal to build honest state on. |
| The shell's own Qt Multimedia (`MediaPlayer` in QML) | 88 MB more, inside the shell | Heaviest, never given back, a decoder crash would take the bar with it, and QML can't read the decoded audio. |

mpv as first tried, with its defaults, held 63 MB; turning off its built-in
scripts and video output brought that to 41 MB. Total resident memory, shared
libraries included, is 68 to 82 MB, in line with the 68 to 88 MB in
[the source notes](music-sources.md).

What mpv gives that the lighter pipeline doesn't: a real pause that corks the
stream so the audio device can rest, the playing position (the features follow
it), a truthful "audio has started" and "the track ended", and, through the
MPRIS script Omarchy installs beside it, the media keys.

## Why a separate fetcher

A track is either a direct link or a byte range inside a published ZIP. The
ZIP's bytes are deflated, so something has to unpack them before a player can
read them; mpv cannot. `plugin/bin/mood_fetch.py` does both kinds the same
way, in the standard library: one request, bytes handed on as they arrive,
unpacked on the fly for the ZIP, checked against the checksum the catalog
recorded. It exits a second or two after it starts, once mpv has read the
track ahead.

Doing direct links through it too, rather than letting mpv fetch them, means
one place decides what "offline" is and what "the source changed" is, and one
place counts the bytes.

A changed source is noticed before anything is played: the ZIP's total size
and the entry's own header are checked on the first bytes, and a direct link's
length against the catalog.

## Features

The same bytes go once through `ffmpeg`, off to the side and at low priority:
mono, 22 kHz, split into three bands, one RMS reading per 40 ms. That takes one
to three seconds of one core per track and is finished before the first few
seconds have played. The result is a small table by position in the track; the
plugin looks up "now" in it 25 times a second while playing.

Because the table is by position, the visual stays in step through pauses, and
the range can be scaled to the whole track rather than guessed as it goes.
Because it is made from the plugin's own bytes, nothing else playing on the
machine can move it.

Tracks are only measured while a surface says it is drawing from the features,
and never with animations off. When there is no measurement for the current
moment the interface says so (`features.available`), with the reason.

mpv's own audio filters were tried first: they delivered readings at about
13 a second in uneven bursts, ahead of the sound by the output buffer, and put
a filter graph in the path of the audio. The one-pass analysis does none of
that.

## Media keys

Omarchy routes the media keys to whichever MPRIS player is active. mpv
registers as one through `mpv-mpris`, so play/pause works as it stands. Next
and previous arrive as "move along the playlist", so each track is loaded as
the middle of three entries, with markers either side; landing on a marker is
how the plugin learns a key was pressed, and it then loads the real next or
previous track.

The desktop is told the mood's name as the title, not the track's. The
artist tag passes through where a file has one. With this on, Omarchy's own
media widget, if it is on the bar, shows mood as a player. It is the
`mediaKeys` setting and can be turned off.

The keys reach mood only while its player exists: playing, or paused for less
than ten minutes. They never start it from nothing.

Two presses of play/pause within a fraction of a second can lose the second.
The desktop's media service acts on the status it last heard, and it hears of
a pause a moment after the plugin does, so the second press goes out as
"pause" again. Sent the instant the plugin reported paused, 10 of 24 second
presses were lost; with 700 ms between them, none of 12. Clicking the bar item
doesn't go that way and has no such gap.

## What it weighs

| | |
| --- | --- |
| Install | Nothing added to the system. The files the plugin runs from are about 450 KB, roughly half of that the catalog. A checkout of the whole repository is about 1.5 MB. |
| Stopped | No processes. About 2.5 MB inside the shell (the catalog in memory). 0.0% CPU. |
| Playing | mpv: 41 MB private, 39 to 52 MB proportional, 68 to 82 MB resident; 0.5% of one core. The shell: 0.0% with a still bar item, 2.4% with the plain surface following the music. See [surfaces](surfaces.md#what-it-costs-to-animate) for why that number is the surface's to keep down. |
| Per track | The fetcher for one to three seconds: 32 MB peak, 0.1 to 0.3 s of CPU. With features wanted, `ffmpeg` beside it: 52 MB peak, 1.0 to 3.5 s of CPU. Then both are gone. |
| Paused | mpv stays, at 0.0% CPU, for ten minutes; then it is let go and paused costs what stopped does. Resuming after that fetches the rest of the track again and carries on from about the same place. |
| Data | The track, once per play: 1.7 to 9.7 MB, median 3.2 MB for Open Lo-Fi and 4.1 MB for the Internet Archive genres. About 75 MB an hour. Nothing is cached, so a track heard twice is fetched twice. |
| To first sound | Open Lo-Fi: first bytes in 0.2 to 0.4 s, sound in 0.5 s from cold. Internet Archive: first bytes in 0.7 to 0.8 s, sound in 1.1 s. A skip adds 0.26 s of deliberate wait (below). |

## Behaviour worth knowing

- **States change on evidence.** `playing` waits for mpv to report audio.
  `loading` is "asked for, nothing heard yet". `paused` means a position is
  held; pausing while loading, or changing mood while paused, leaves nothing
  held, so the state is `stopped`.
- **Skips coalesce.** A skip or a mood step silences the current track at
  once, and the next one is fetched 260 ms after the last step. Six quick
  skips are one request.
- **Back goes to what was heard.** History is per mood and holds tracks whose
  audio actually started, up to 50. Tracks skipped past in a run never
  started, so they leave no trail. Back starts the track over (resuming would
  mean keeping its bytes). Skip after back returns to where you were. With
  nothing earlier, back is refused and says so.
- **Entering a mood** plays its current track if it was never heard, else the
  next one.
- **Failures back off.** Offline retries the same track after 4 s, 12 s, 30 s,
  90 s and then every 5 minutes. A broken track is passed over, twice in a row
  at most, before the same waiting applies, so a dead source isn't walked end
  to end. A click retries at once.
- **A fetch that dies mid-track** lets what arrived play out, then reports
  offline.
- **Nothing starts by itself.** The last mood is remembered; playback never is.
- **If the shell dies,** mpv is told to exit with it (`setpriv --pdeathsig`).

## What wasn't checked

- The music itself, and anything at real speed. No one has listened.
- A real trackpad, a real mouse wheel and real media keys. The wheel events
  were synthetic; the keys were driven through the shell's own media service,
  one step short of the keyboard.
- A real network drop mid-track on a live interface. Offline was checked two
  ways: a box with no internet at all, and refusing the fetcher's connections
  in a connected box and then allowing them again. The mid-track case is
  covered by unit tests only.
- Long sessions, sleep and resume, Bluetooth or device changes, more than one
  monitor, a vertical bar, and any machine other than the test machine.
- Whether GitHub and the Internet Archive are content to be used this way over
  time. One box of a few dozen plays is not a reliability test.
