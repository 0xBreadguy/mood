# Surfaces

A surface is the look of the plugin: how the bar item draws, and how the popup
presents itself. The two are replaced together, as a unit. Everything else is
the plugin's and stays the same under every surface: playing music, what each
click, scroll and key does, the tooltip, focus in the popup, the names a screen
reader hears, the settings and the IPC.

A setting picks the surface, so two surfaces can be compared on the same bar,
and a surface that fails to load falls back to `plain`.

```text
plugin/
  BarWidget.qml      input on the bar item, settings, hosts the surface
  MoodPopup.qml      the popup's frame and keys
  PopupModel.qml     what the popup holds and what is focused
  PopupEntry.qml     wraps one interactive thing in the popup
  Mood.qml           everything a surface is given        <- read this
  surfaces/
    index.json       the looks offered in the popup
    plain/
      Bar.qml        the bar item's drawing               <- copy this
      Popup.qml      the popup's drawing                  <- and this
```

## Add one

1. Copy `plugin/surfaces/plain/` to `plugin/surfaces/<id>/`. The id is
   lowercase letters, digits and hyphens.
2. Add a line to `plugin/surfaces/index.json`:
   `{ "id": "<id>", "name": "<Name>" }`.
3. Pick it: `omarchy bar set 0xbreadguy.mood surface <id>`, or Settings >
   Surface in the popup once two are listed.

`tine` is the plugin's look and the only one listed. `plain` isn't listed,
because it's the fallback and not a design; it can still be picked by id.

Nothing else needs touching. If you find yourself editing a file outside your
folder to get a look you want, the seam is missing something: say so instead.

## What a surface is given

Both files get one property, `mood`, an instance of
[`plugin/Mood.qml`](../plugin/Mood.qml). That file is the contract and is
commented line by line. In short:

| | |
| --- | --- |
| `state` | `stopped`, `loading`, `playing`, `paused`, `failed` or `offline`. `failure` says why for the last two. |
| `moods`, `moodIndex`, `moodLabel` | The categories in stepping order (`{ id, label, count }`), and which is current. Thirteen today, labels up to 24 characters, and stepping wraps. |
| `nameShowing`, `nameText`, `nameDirection` | The name-after-switch moment: true for about 1.5 s after any mood change. Direction is +1, -1, or 0 when picked by name. |
| `skipped(direction)`, `moodChanged(direction, label)`, `refused(what)`, `failed(kind)` | Events. A refusal (`back` with nothing earlier) must be shown, not swallowed. |
| `trackSerial` | Goes up by one each time a new track is actually heard. |
| `features` | `level`, `low`, `mid`, `high`, `onset` (each 0 to 1), `onsetCount`, and `available`. |
| `highlight`, `foreground`, `background`, `muted`, `urgent`, `popupForeground`, `popupBackground` | Resolved colours. `highlight` is the theme's accent unless the user set their own. |
| `variant` | Which of your own animation variants is chosen. |
| `reducedMotion` | The shell's setting (`omarchy toggle animations`). |
| `barSize`, `vertical`, `fontFamily`, `fontSize`, `fixedEdge`, `hovered`, `pressed` | The bar and the pointer. |
| `popup` | The popup's contents and focus. See below. |

A surface never gets the track's title, artist or art, a queue, the settings
store or the service. The main surface shows the mood and the playback state
and nothing else; that is a product decision, not an omission.

### What a surface declares

On the root item of `Bar.qml`:

```qml
required property var mood

// Your animation variants. The first is the default. The chosen id comes back
// as mood.variant, and Settings > Animation lists them when there are two.
readonly property var variants: [{ id: "follow", name: "Follow the music" },
                                 { id: "steady", name: "Steady" }]

// Whether you are drawing from mood.features right now. Tracks are only
// measured while some surface says so.
readonly property bool usesFeatures: mood.variant === "follow"

// Your size. On a horizontal bar the height is the bar's.
implicitWidth: ...
implicitHeight: mood.vertical ? ... : mood.barSize
```

The width may change (the plain surface grows to hold the name), but a
changing width moves the bar's other items. Lay out against `mood.fixedEdge`
so your own mark stays still when it does.

On the root item of `Popup.qml`: `required property var mood`, an
`implicitWidth` (220 to 520 logical pixels are honoured) and an
`implicitHeight`. The shell's panel supplies the card, its border, its
position under the bar item and its open and close motion.

## Rules that come with the seam

- **States must read without motion and without colour.** Six states, six
  still forms. `loading` is not a quiet passage (that is `playing` with low
  levels), and `paused` is not `stopped`.
- **Never fake the music.** When `mood.features.available` is false there is no
  measurement for this moment: the track hasn't been measured yet, it isn't
  playing, or `ffmpeg` is missing (`unavailableBecause` says which). Go calm.
  Features follow the plugin's own audio by position in the track, 25 times a
  second, scaled to that track's range. They are never taken from the system
  mixer, so a call or a notification can't move your visual.
- **Reduced motion means nothing moves.** `Style.duration(ms)` already returns
  0 then; anything on a timer of your own must check `mood.reducedMotion`. The
  plugin stops measuring tracks while it is on.
- **No word rests on the bar.** The mood's name may show only while
  `mood.nameShowing` is true.
- **Input is not yours.** The plugin lays a hit area over your bar drawing. Do
  not add a `MouseArea`, `WheelHandler` or key handling to the bar item. Use
  `mood.hovered` and `mood.pressed` for feedback.
- **All text is plain.** Set `textFormat: Text.PlainText` on every `Text`.
- **Take colours from `mood`,** so the highlight setting and the theme apply.
  `Style` from `qs.Commons` is fine for spacing, type sizes, `duration()` and
  `easeOut`. Follow the shell's motion rules: ease out, under 300 ms, exits
  shorter than entrances.

## The popup

`mood.popup` ([`plugin/PopupModel.qml`](../plugin/PopupModel.qml)) holds what
to draw:

| | |
| --- | --- |
| `guide` | `{ id, visible, title, dismissLabel, dismissName }`: first-open bar controls highlight state and dismiss action (`entryId: "guide:dismiss"`). |
| `notes` | `[{ id, input, action, detail, text }]`: the bar's gestures as scannable input/action pairs. Shown in the top highlight while `guide.visible` is true, and tucked inside collapsed Manual controls afterward. |
| `moods` | `[{ id, label, count, current, name }]` |
| `manual`, `settings` | The two collapsed sections: `{ id, label, expanded, name }` |
| `controls` | Back, play or pause, skip: `[{ id, label, enabled, name }]`. Empty while collapsed. |
| `options` | The settings: `[{ id, label, value, choices: [{ id, label }], color }]`. Empty while collapsed. |
| `focusId` | Which entry has the focus. |
| `customColor`, `colorHint`, `pickColorLabel`, `pickingColor`, `editing`, `setColor(text)`, `pickColor()`, `cancelEdit()` | For the custom highlight's swatch (`entryId: "set:highlight:pick"`) and text field. |

Wrap every interactive thing in a
[`PopupEntry`](../plugin/PopupEntry.qml) (`import "../.."`). It gives the
entry the pointer, the shared keyboard focus, the action and its accessible
role and name. You draw inside it, using its `focused`, `hovered` and
`pressed`:

```qml
Repeater {
  model: surface.mood.popup.moods
  PopupEntry {
    required property var modelData
    mood: surface.mood
    entryId: modelData.id
    name: modelData.name
    kind: "option"
    checked: modelData.current
    width: parent.width; height: 28
    // ... your drawing of one mood, focused or not, current or not
  }
}
```

A choice inside a setting is a `PopupEntry` with `choiceId` set as well. Give
non-interactive text an `Accessible.role: Accessible.StaticText` and a name.

The keys are the plugin's and are the same in every surface: Up, Down and Tab
move the focus (it wraps), Left and Right change a setting or walk along the
manual controls, Enter and Space activate, Escape closes. Choosing a mood
closes the popup.

**Draw every list.** A surface that leaves out `options` has no settings in
its popup. They stay reachable from the command line, but that is a worse
popup, not a simpler one.

## What it costs to animate

The bar is one surface as wide as the screen, and any change on it redraws all
of it. Measured in Omabox on 2026-11-21, with a track playing:

| Bar item | Shell CPU, % of one core |
| --- | --- |
| Not animating (the plain surface's `steady` variant) | 0.0 |
| A disc stepping between four sizes with the level | 2.4 |
| The same disc eased continuously at 60 frames a second | 27.3 |

So the frame rate of your bar drawing is most of what this plugin costs while
it plays. Prefer changes that happen a few times a second to motion that never
rests, stop every timer when its state ends, and measure:

```sh
omabox cpu 20          # while a track plays; read the quickshell row
```

The popup is open briefly and can afford more.

## Run it in Omabox, with sound off

Never load a work-in-progress surface into the real desktop. A box is a hidden
desktop of its own; `--audio` gives it a speaker nobody hears.

```sh
omabox up --stock --audio --plugin "$PWD"     # from the repository root
omabox run -- omarchy-shell mood play
omabox run -- omarchy-shell mood status
omabox shot -g "1700,0 220x30" --zoom 4       # look at the bar item
omabox restart-shell                          # after every edit
omabox audio 3                                # did the box make sound?
omabox down
```

`--stock` is Omarchy's default look; leave it out to see the surface on your
own theme. Without `--audio` a box has no sound device at all and the player
fails to start; to play silently in such a box, export `MOOD_AUDIO=null` for
the shell. Drive it with `omabox click`, `omabox scroll X Y DY [DX]
--source wheel|finger`, `omabox keys`, and read the popup with
`omabox tree --layer omarchy-keyboard-panel`.

`tools/box-check.sh` does all of that for the default look, Tine: it starts a box,
plays real tracks, checks 81 behaviours and keeps captures. Run it before and
after your change; the checks are about behaviour, so they should still pass
under your surface: `MOOD_SURFACE=<id> tools/box-check.sh`.

States you can't summon by hand have stand-ins in that script: a `python3`
that refuses the fetcher its connections (`offline`) or stalls it (`loading`),
and an `mpv` that won't start (`failed`).

## IPC, for driving a surface

```sh
omarchy-shell mood toggle | play | pause | stop | skip | back
omarchy-shell mood step 1          # or -1: next or previous mood, wrapping
omarchy-shell mood set late-night  # ids from: omarchy-shell mood moods
omarchy-shell mood popup
omarchy-shell mood status          # JSON, including the track and its license
```

## Known limits

Automated Omabox checks run without audible playback, and physical trackpad
deltas, vertical bars, and multi-monitor setups have limited coverage.
