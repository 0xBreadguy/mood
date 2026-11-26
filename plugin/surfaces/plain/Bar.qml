import QtQuick
import qs.Commons

// The plain surface's bar item: the reference and the fallback.
//
// It is deliberately not a design. Each playback state is one still shape that
// can be told from the others without colour or motion, the mood is a position
// on a short line, and the mood's name appears beside it for the moment after
// a switch. Copy this folder to start a surface of your own (docs/surfaces.md).
//
//   stopped   an empty ring
//   loading   three dots
//   playing   a filled disc (it follows the loudness in the "follow" variant)
//   paused    a ring with a dot held in it
//   failed    a cross          offline   a ring with a stroke through it
Item {
  id: surface

  // Everything this surface knows comes from here (plugin/Mood.qml).
  required property var mood

  // The animation variants this surface offers; the first is the default. The
  // chosen one comes back as mood.variant.
  readonly property var variants: [
    { id: "follow", name: "Follow the music" },
    { id: "steady", name: "Steady" }
  ]
  // Whether it draws from mood.features right now. The plugin only measures
  // tracks while some surface says so.
  readonly property bool usesFeatures: mood.variant === "follow"

  readonly property real slot: Style.bar.iconSlot
  readonly property real mark: Math.max(8, Style.bar.iconSize)
  readonly property bool showName: mood.nameShowing && !mood.vertical && mood.nameText !== ""
  // The shapes carry the state, not a colour: the bar's alert colour is the
  // theme's choice and can be quieter than its text.
  readonly property color ink: mood.foreground
  // Quiet states recede, as Omarchy's own quiet widgets do.
  readonly property real rest: mood.state === "stopped" ? 0.45 : (mood.state === "offline" ? 0.7 : 1)

  // The width: one icon slot, growing to hold the name for its moment.
  implicitWidth: mood.vertical ? mood.barSize : slot + nameRoom
  implicitHeight: mood.vertical ? slot : mood.barSize
  property real nameRoom: showName ? label.implicitWidth + Style.space(8) : 0
  Behavior on nameRoom {
    NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
  }

  // How much the disc gives to the music: nothing unless there is a real
  // measurement for this moment.
  readonly property bool live: usesFeatures && !mood.reducedMotion && mood.state === "playing"
    && !!mood.features && mood.features.available
  //
  // The level is held to a few steps on purpose. The bar is one surface the
  // width of the screen, and every frame anything on it changes redraws all of
  // it: a disc eased at 60 frames a second cost a quarter of a core in testing.
  // A 12 px disc has only four sizes a pixel apart anyway, so it steps between
  // those, which redraws a few times a second instead.
  readonly property int steps: 4
  readonly property real swell: live ? 0.7 + 0.3 * Math.round(mood.features.level * steps) / steps : 1

  // The name opens on the side that is free to grow, so the mark stays where
  // it was.
  readonly property bool nameBefore: mood.fixedEdge === "end"

  Item {
    id: glyph
    x: surface.nameBefore ? surface.width - width : 0
    width: surface.slot
    height: surface.mood.vertical ? surface.slot : surface.height
    opacity: surface.rest
    scale: surface.mood.pressed ? 0.9 : 1
    Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
    Behavior on scale {
      NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    // A skip nudges the mark the way it went; a refusal shakes it once.
    property real nudge: 0
    transform: Translate { x: glyph.nudge }
    SequentialAnimation {
      id: nudgeRun
      property real to: 0
      NumberAnimation { target: glyph; property: "nudge"; to: nudgeRun.to; duration: Style.duration(70); easing.type: Easing.OutCubic }
      NumberAnimation { target: glyph; property: "nudge"; to: 0; duration: Style.duration(160); easing.type: Easing.OutCubic }
    }
    SequentialAnimation {
      id: shakeRun
      NumberAnimation { target: glyph; property: "nudge"; to: -2; duration: Style.duration(50) }
      NumberAnimation { target: glyph; property: "nudge"; to: 2; duration: Style.duration(70) }
      NumberAnimation { target: glyph; property: "nudge"; to: 0; duration: Style.duration(60) }
    }

    Item {
      id: box
      width: surface.mark
      height: surface.mark
      x: Math.round((parent.width - width) / 2)
      y: Math.round((parent.height - height) / 2) - 1

      // The ring: stopped, paused and offline.
      Rectangle {
        anchors.fill: parent
        visible: surface.mood.state === "stopped" || surface.mood.state === "paused" || surface.mood.state === "offline"
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Math.round(Style.space(1.5)))
        border.color: surface.refusing ? surface.mood.urgent : surface.ink
      }
      // Paused: the position being held.
      Rectangle {
        visible: surface.mood.state === "paused"
        width: Math.max(2, Math.round(parent.width / 3)); height: width; radius: width / 2
        anchors.centerIn: parent
        color: surface.mood.highlight
      }
      // Offline: a stroke through the ring.
      Rectangle {
        visible: surface.mood.state === "offline"
        width: parent.width + 2; height: Math.max(1, Math.round(Style.space(1.5)))
        anchors.centerIn: parent
        rotation: -45
        color: surface.ink
      }
      // Playing: the disc.
      Rectangle {
        visible: surface.mood.state === "playing"
        anchors.centerIn: parent
        width: parent.width; height: width; radius: width / 2
        color: surface.refusing ? surface.mood.urgent : surface.mood.highlight
        scale: surface.swell
      }
      // Failed: a cross.
      Repeater {
        model: surface.mood.state === "failed" ? [45, -45] : []
        Rectangle {
          required property int modelData
          width: box.width + 1; height: Math.max(1, Math.round(Style.space(1.5)))
          anchors.centerIn: parent
          rotation: modelData
          color: surface.ink
        }
      }
      // Loading: three dots, lit in turn; all lit, and still, with motion off.
      Row {
        visible: surface.mood.state === "loading"
        anchors.centerIn: parent
        spacing: 2
        Repeater {
          model: 3
          Rectangle {
            required property int index
            width: Math.max(2, Math.round(surface.mark / 5)); height: width; radius: width / 2
            color: surface.ink
            opacity: surface.mood.reducedMotion || waiting.step === index ? 1 : 0.35
          }
        }
      }
    }

    // The mood, as a place on a short line: where in the list it is.
    Item {
      id: line
      visible: surface.mood.moods.length > 1
      width: Math.round(surface.slot * 0.6)
      height: 2
      x: Math.round((parent.width - width) / 2)
      y: box.y + box.height + 3
      Rectangle { width: parent.width; height: 1; y: 1; color: surface.ink; opacity: 0.3 }
      Rectangle {
        width: 3; height: 2
        color: surface.mood.highlight
        x: surface.mood.moods.length > 1
          ? Math.round((line.width - width) * surface.mood.moodIndex / (surface.mood.moods.length - 1)) : 0
        Behavior on x { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
      }
    }
  }

  // The name, for its moment only.
  Text {
    id: label
    textFormat: Text.PlainText
    text: surface.mood.nameText
    visible: opacity > 0
    opacity: surface.showName ? 1 : 0
    x: surface.nameBefore ? surface.width - surface.slot - implicitWidth : surface.slot
    anchors.verticalCenter: parent.verticalCenter
    color: surface.mood.foreground
    font.family: surface.mood.fontFamily
    font.pixelSize: surface.mood.fontSize
    renderType: Text.NativeRendering
    Behavior on opacity { NumberAnimation { duration: Style.duration(surface.showName ? 180 : 120); easing.type: Easing.OutCubic } }
  }
  clip: nameRoom > 0 && nameRoom < label.implicitWidth + Style.space(8)

  // Constant motion only while there is something to wait for, and never with
  // motion off (the three dots then show whole).
  Timer {
    id: waiting
    property int step: 0
    interval: 260
    repeat: true
    running: surface.mood.state === "loading" && !surface.mood.reducedMotion && surface.visible
    onTriggered: step = (step + 1) % 3
  }

  // A refusal is shown even with motion off: the mark takes the alert colour
  // for a moment.
  property bool refusing: false
  Timer { id: refusal; interval: 450; onTriggered: surface.refusing = false }

  Connections {
    target: surface.mood
    function onSkipped(direction) {
      if (surface.mood.reducedMotion) return
      nudgeRun.to = direction > 0 ? 3 : -3
      nudgeRun.restart()
    }
    function onRefused(what) {
      surface.refusing = true
      refusal.restart()
      if (!surface.mood.reducedMotion) shakeRun.restart()
    }
  }
}
