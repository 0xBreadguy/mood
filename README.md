**mood** — music beneath your work.

```text
█▄ ▄█ ▄▀▀▄ ▄▀▀▄ █▀▀▄
█ ▀ █ █  █ █  █ █  █
▀   ▀  ▀▀   ▀▀  ▀▀▀
```

# mood

[![Version 0.1.0](https://img.shields.io/badge/version-0.1.0-555555)](manifest.json)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Platform: Omarchy](https://img.shields.io/badge/platform-Omarchy-5c6b73)
![Built with: QML & Python](https://img.shields.io/badge/built%20with-QML%20%26%20Python-4b6f92)
[![Catalog: 13 moods · 451 CC0 tracks](https://img.shields.io/badge/catalog-13%20moods%20%C2%B7%20451%20CC0%20tracks-2ea44f)](catalog/categories.json)
![Stage: experimental](https://img.shields.io/badge/stage-experimental-777777)

A quiet music plugin for [Omarchy](https://omarchy.org). Pick a mood, press
play, and get back to what you're doing. One small comb in your bar shows the
mood and whether music is playing — and it's also the control. No song titles,
album art, or queue clutter.

It streams 451 CC0 tracks one at a time on demand from
[Open Lo-Fi](https://github.com/btahir/open-lofi) and
[Alec Penn Radio](https://archive.org/search?query=creator%3A%22Alec+Penn+Radio%22).
Nothing gets downloaded in bulk, nothing is saved to disk, and nothing plays
until you ask.

> Experimental, checked on Omarchy 4.5.0. A full listening pass across all 451
> tracks is still ahead.

![The mood bar item rolling through its states, gestures, and mood switches at real speed (4× enlarged)](docs/states.gif)

Right-click the bar item for all 13 moods, manual controls, and settings —
including picking a custom highlight color straight off your screen:

![The mood popup: first-open bar controls, manual controls, and custom highlight settings](docs/popup.png)

Three motion styles follow the plugin's own audio (never system sound):
**Resonance**, **Impulse**, or **Steady** (`0%` shell CPU):

![Resonance, Impulse, and Steady animations playing over the same track (4× enlarged)](docs/variants.gif)

## Install

Uses `mpv`, `python`, `ffmpeg`, and `hyprpicker` — all already in a default
Omarchy install.

```sh
omarchy plugin add https://github.com/0xBreadguy/mood --enable
```

Update or remove it anytime:

```sh
omarchy plugin update 0xbreadguy.mood && omarchy restart shell
```

```sh
omarchy plugin remove 0xbreadguy.mood    # stops playback and removes the widget
rm -r ~/.local/state/mood                # clears saved last mood and guide state
```

Cloning or pulling this repo installs nothing by itself.

## Controls

| | |
| --- | --- |
| Click | Play or pause |
| Scroll down / up | Skip, or go back to the track you last heard |
| Scroll sideways | Next or previous mood (or hold right-click + scroll) |
| Right-click | Open the mood popup and settings |
| Media keys | Play/pause, skip, and back |

Swap vertical and sideways scroll in Settings, or drive the plugin from a
script or keybind (`omarchy-shell mood toggle | skip | back | step 1 | set late-night | popup | status`).

## Go deeper

- [Playback & sources](docs/playback.md) — on-demand CC0 streaming, audio
  analysis, and resource costs.
- [Surfaces](docs/surfaces.md) — how the bar visual works and how to build a
  look of your own.
- [Contributing](CONTRIBUTING.md) — local dev symlink, catalog updates, and
  tests (`node --test test/`, `python3 -m unittest discover -s test`,
  `tools/box-check.sh`).

Omarchy only. [MIT](LICENSE) for the plugin code; streamed tracks keep their
upstream CC0 licenses, and no music files are bundled here. The name is the
premise — it's written lowercase.
