import QtQuick

// Everything a surface is given, and nothing else. A surface's Bar.qml and
// Popup.qml each receive one of these as their `mood` property and draw from
// it. They never reach the service, the settings or the input handling; those
// belong to the plugin. docs/surfaces.md walks through this file.
//
// Read these; don't write them. The plugin keeps them current.
QtObject {
  // ---- playback ------------------------------------------------------------

  // One of: stopped, loading, playing, paused, failed, offline. Each must look
  // different, also with motion off and without relying on colour alone.
  //   stopped  nothing is loaded
  //   loading  asked for, no sound yet (not a quiet passage: that is `playing`)
  //   playing  audio is running
  //   paused   held at a position
  //   failed   a track, its source or the player went wrong; it retries
  //   offline  the network can't be reached; it retries, less and less often
  property string state: "stopped"
  // Why, when failed or offline: offline, source, changed, player, catalog.
  property string failure: ""

  // ---- moods ---------------------------------------------------------------

  // The categories, in stepping order: [{ id, label, count }]. There are
  // thirteen today; there may be more, and labels run to 24 characters.
  property var moods: []
  // Which of them is current. Stepping wraps around.
  property int moodIndex: 0
  property string moodLabel: ""

  // ---- moments -------------------------------------------------------------

  // The name-after-switch moment: true for about a second and a half after the
  // mood changes, by any route. No word rests on the bar outside it.
  // nameDirection is +1 or -1 for a step and 0 when the mood was picked by name.
  property bool nameShowing: false
  property string nameText: ""
  property int nameDirection: 0

  // Goes up by one each time a new track is actually heard.
  property int trackSerial: 0

  // A track was skipped (+1) or gone back to (-1) by the user.
  signal skipped(int direction)
  // The mood changed: +1, -1, or 0 when picked by name.
  signal moodChanged(int direction, string label)
  // Something was asked for that can't be done. what: "back" (nothing earlier)
  // or "skip". Show it; a refusal must not be silent.
  signal refused(string what)
  // Playback failed. kind is the same word `failure` then holds.
  signal failed(string kind)

  // ---- sound ---------------------------------------------------------------

  // What the music is doing now, each 0-1 and scaled to the current track's
  // own range: level, low, mid, high. `onset` is the strength of the latest
  // onset and `onsetCount` goes up by one at each. Updated 25 times a second
  // while playing.
  //
  // When `available` is false there is no measurement for this moment
  // (`unavailableBecause` says why). Go calm; never fake a response.
  property QtObject features: null

  // ---- look ----------------------------------------------------------------

  // The highlight colour: the theme's accent unless the user set their own.
  property color highlight: "#cacccc"
  // Theme colours for the bar item ...
  property color foreground: "#cacccc"
  property color background: "#101315"
  property color muted: "#707880"
  // The bar's alert colour. It is the theme's choice and may be subtle, so
  // don't let a state depend on it alone.
  property color urgent: "#a55555"
  // ... and for the popup card.
  property color popupForeground: "#cacccc"
  property color popupBackground: "#101315"

  // Which of the surface's own animation variants is chosen (an id from the
  // `variants` its Bar.qml declares).
  property string variant: ""
  // The shell's reduced-motion setting (`omarchy toggle animations`). When
  // true, nothing may move: show each state as a still form.
  property bool reducedMotion: false

  // ---- the bar -------------------------------------------------------------

  // The bar's thickness, whether it runs vertically, and its font.
  property int barSize: 26
  property bool vertical: false
  property string fontFamily: "monospace"
  property int fontSize: 12
  // Which edge of the item stays put if it changes width: "start" (left, or
  // top on a vertical bar), "end" or "center". Lay out against it and the mark
  // won't slide when the item grows.
  property string fixedEdge: "center"
  // The pointer is over the bar item / a button is held on it.
  property bool hovered: false
  property bool pressed: false

  // ---- the popup -----------------------------------------------------------

  // What the popup holds and what is focused in it (PopupModel.qml). A
  // surface's Popup.qml draws these entries and wraps each interactive one in
  // a PopupEntry, which does the pointer, the focus and the accessible name.
  property QtObject popup: null
}
