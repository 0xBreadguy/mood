import QtQuick

// One interactive thing in the popup. A surface wraps its drawing of an entry
// in this and gets the mechanics for free: the pointer and the keyboard share
// one focus, a click does what Enter does, and a screen reader hears a role and
// a name. The surface only decides what it looks like.
//
//   PopupEntry {
//     mood: surface.mood
//     entryId: modelData.id          // from mood.popup.moods, .controls, ...
//     name: modelData.name           // what a screen reader says
//     width: parent.width; height: 28
//     Rectangle { anchors.fill: parent; visible: parent.focused }
//     Text { text: modelData.label }
//   }
//
// For one choice inside a setting, also give `choiceId` and `checked`: the
// click then picks that choice.
Item {
  id: entry

  required property var mood
  required property string entryId
  property string name: ""
  property string choiceId: ""
  property bool checked: false
  // "button", "option" (a mood), "disclosure" or "choice".
  property string kind: choiceId !== "" ? "choice" : "button"
  property bool expanded: false
  // False for a row that only gathers other entries (a setting and its
  // choices): the pointer still moves the focus to it, but a click on its
  // empty space does nothing.
  property bool clickable: true

  // For the surface to draw from.
  readonly property bool focused: !!mood && !!mood.popup && mood.popup.focusId === entryId
  readonly property bool hovered: pointer.containsMouse
  readonly property bool pressed: pointer.pressed

  function activate() {
    if (!mood || !mood.popup || !enabled) return
    if (choiceId !== "") mood.popup.choose(entryId, choiceId)
    else mood.popup.activate(entryId)
  }

  onFocusedChanged: if (focused && mood && mood.popup) mood.popup.reveal(entry)

  Accessible.role: kind === "choice" ? Accessible.RadioButton
    : (kind === "option" ? Accessible.ListItem : Accessible.Button)
  Accessible.name: name
  Accessible.focusable: true
  Accessible.focused: focused && choiceId === ""
  Accessible.checkable: kind === "choice"
  Accessible.checked: checked
  Accessible.selected: kind === "option" && checked
  Accessible.onPressAction: activate()

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: entry.enabled && entry.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: if (entry.mood && entry.mood.popup) entry.mood.popup.point(entry.entryId)
    onClicked: if (entry.clickable) entry.activate()
  }
}
