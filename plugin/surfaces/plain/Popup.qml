import QtQuick
import qs.Commons
import qs.Ui
import "../.."

// The plain surface's popup: mood.popup, drawn as a plain list.
//
// A dismissible first-open bar controls card leads it until dismissed, then
// the same legend sits inside collapsed Manual controls. Everything
// interactive is a PopupEntry, which supplies the pointer, the shared keyboard
// focus and the accessible name; this file only chooses how each entry looks.
// Declare the width you want as implicitWidth.
Item {
  id: surface

  required property var mood
  readonly property var popup: mood.popup

  implicitWidth: Style.space(300)
  implicitHeight: stack.implicitHeight

  readonly property color ink: mood.popupForeground
  readonly property int rowHeight: Style.spacing.popupRowHeight
  readonly property string family: Style.font.family

  component Label: Text {
    textFormat: Text.PlainText
    color: surface.ink
    font.family: surface.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
    elide: Text.ElideRight
  }

  // The focus mark: the shell's own hover fill, plus an edge in the highlight
  // colour so it reads without relying on a faint tint.
  component Focus: Rectangle {
    property bool on: false
    anchors.fill: parent
    visible: on
    radius: Style.cornerRadius
    color: Style.hoverFill
    Rectangle {
      width: 2
      height: parent.height - 8
      anchors.verticalCenter: parent.verticalCenter
      color: surface.mood.highlight
    }
  }

  component NotesList: Column {
    id: notesList
    spacing: 2
    Repeater {
      model: surface.popup.notes
      Item {
        id: noteRow
        required property var modelData
        width: notesList.width
        implicitHeight: Math.max(inLabel.implicitHeight, actCol.implicitHeight)
        Accessible.role: Accessible.StaticText
        Accessible.name: modelData.text

        Label {
          id: inLabel
          width: Style.space(82)
          text: noteRow.modelData.input
          opacity: 0.85
          font.pixelSize: Style.font.bodySmall
        }
        Column {
          id: actCol
          x: Style.space(82) + Style.spacing.sm
          width: Math.max(0, parent.width - x)
          spacing: 1
          Label {
            width: parent.width
            text: noteRow.modelData.action
            opacity: 0.65
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
          }
          Label {
            visible: !!noteRow.modelData.detail
            width: parent.width
            text: noteRow.modelData.detail || ""
            opacity: 0.5
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
          }
        }
      }
    }
  }

  Column {
  id: stack
  width: parent.width
  spacing: Style.spacing.sm

  // ---- first-open guide (dismissible) --------------------------------------

  Loader {
    id: plainGuide
    active: surface.popup.guide.visible
    visible: active
    width: parent.width
    sourceComponent: Rectangle {
      width: plainGuide.width
      implicitHeight: plainGuideCol.implicitHeight + Style.spacing.md * 2
      radius: Style.cornerRadius
      color: Style.normalFill
      border.width: 1
      border.color: surface.mood.highlight

      Column {
        id: plainGuideCol
        x: Style.spacing.md
        y: Style.spacing.md
        width: parent.width - Style.spacing.md * 2
        spacing: Style.spacing.sm

        Item {
          width: parent.width
          implicitHeight: Math.max(plainGuideTitle.implicitHeight, plainDismiss.implicitHeight)
          Label {
            id: plainGuideTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: surface.popup.guide.title
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            Accessible.role: Accessible.StaticText
            Accessible.name: surface.popup.guide.title
          }
          PopupEntry {
            id: plainDismiss
            mood: surface.mood
            entryId: surface.popup.guide.id
            name: surface.popup.guide.dismissName
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: plainDismissText.implicitWidth + Style.spacing.md * 2
            implicitHeight: Style.space(20)
            height: implicitHeight
            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: plainDismiss.pressed ? Style.pressedFill : (plainDismiss.focused ? Style.hoverFill : "transparent")
              border.width: 1
              border.color: plainDismiss.focused ? surface.mood.highlight : Style.normalBorderColor
            }
            Label {
              id: plainDismissText
              anchors.centerIn: parent
              text: surface.popup.guide.dismissLabel
              font.pixelSize: Style.font.caption
            }
          }
        }

        NotesList { width: parent.width }
      }
    }
  }

  PanelSeparator { visible: surface.popup.guide.visible; width: parent.width }

  // ---- moods ---------------------------------------------------------------

  Column {
    width: parent.width
    Repeater {
      model: surface.popup.moods
      PopupEntry {
        id: row
        required property var modelData
        mood: surface.mood
        entryId: modelData.id
        name: modelData.name
        kind: "option"
        checked: modelData.current
        width: parent.width
        height: surface.rowHeight

        Focus { on: row.focused }
        // The current mood: a filled mark, and the name at full strength.
        Rectangle {
          x: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          width: 6; height: 6; radius: 3
          color: row.modelData.current ? surface.mood.highlight : "transparent"
          border.width: row.modelData.current ? 0 : 1
          border.color: Qt.rgba(surface.ink.r, surface.ink.g, surface.ink.b, 0.35)
        }
        Label {
          x: Style.spacing.lg + 6 + Style.spacing.lg
          width: parent.width - x - count.implicitWidth - Style.spacing.lg * 2
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.label
          font.bold: row.modelData.current
        }
        Label {
          id: count
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: I18n.formatNumber(row.modelData.count)
          opacity: 0.5
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  PanelSeparator { width: parent.width }

  // ---- manual controls, collapsed ------------------------------------------

  PopupEntry {
    id: manualHeader
    mood: surface.mood
    entryId: surface.popup.manual.id
    name: surface.popup.manual.name
    kind: "disclosure"
    expanded: surface.popup.manual.expanded
    width: parent.width
    height: surface.rowHeight
    Focus { on: manualHeader.focused }
    Label {
      x: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      text: (surface.popup.manual.expanded ? "▾ " : (I18n.rightToLeft ? "◂ " : "▸ ")) + surface.popup.manual.label
      opacity: 0.8
    }
  }

  Row {
    visible: surface.popup.controls.length > 0
    x: Style.spacing.lg
    spacing: Style.spacing.md
    Repeater {
      model: surface.popup.controls
      PopupEntry {
        id: control
        required property var modelData
        mood: surface.mood
        entryId: modelData.id
        name: modelData.name
        enabled: modelData.enabled
        width: controlLabel.implicitWidth + Style.spacing.controlPaddingX * 2
        height: surface.rowHeight
        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: control.pressed ? Style.pressedFill : (control.focused ? Style.hoverFill : Style.normalFill)
          border.width: 1
          border.color: control.focused ? surface.mood.highlight : Style.normalBorderColor
        }
        Label {
          id: controlLabel
          anchors.centerIn: parent
          text: control.modelData.label
          opacity: control.modelData.enabled ? 1 : 0.4
        }
      }
    }
  }

  Loader {
    id: plainManualNotes
    active: surface.popup.controls.length > 0 && !surface.popup.guide.visible
    visible: active
    width: parent.width
    sourceComponent: Item {
      width: plainManualNotes.width
      implicitHeight: plainManualNotesCol.implicitHeight + Style.spacing.xs
      Column {
        id: plainManualNotesCol
        x: Style.spacing.lg
        y: Style.spacing.xs
        width: parent.width - Style.spacing.lg * 2
        spacing: 2
        Label {
          text: surface.popup.guide.title
          opacity: 0.55
          font.pixelSize: Style.font.caption
          Accessible.role: Accessible.StaticText
          Accessible.name: surface.popup.guide.title
        }
        NotesList { width: parent.width }
      }
    }
  }

  // ---- settings, collapsed -------------------------------------------------

  PopupEntry {
    id: settingsHeader
    mood: surface.mood
    entryId: surface.popup.settings.id
    name: surface.popup.settings.name
    kind: "disclosure"
    expanded: surface.popup.settings.expanded
    width: parent.width
    height: surface.rowHeight
    Focus { on: settingsHeader.focused }
    Label {
      x: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      text: (surface.popup.settings.expanded ? "▾ " : (I18n.rightToLeft ? "◂ " : "▸ ")) + surface.popup.settings.label
      opacity: 0.8
    }
  }

  Column {
    visible: surface.popup.options.length > 0
    width: parent.width
    spacing: Style.spacing.xs
    Repeater {
      model: surface.popup.options
      PopupEntry {
        id: option
        required property var modelData
        mood: surface.mood
        entryId: modelData.id
        name: modelData.label
        clickable: false
        width: parent.width
        height: body.implicitHeight + Style.spacing.md * 2

        Focus { on: option.focused }
        Column {
          id: body
          x: Style.spacing.lg
          y: Style.spacing.md
          width: parent.width - Style.spacing.lg * 2
          spacing: Style.spacing.sm

          Label { text: option.modelData.label; opacity: 0.7; font.pixelSize: Style.font.bodySmall }

          Flow {
            width: parent.width
            spacing: Style.spacing.sm
            Repeater {
              model: option.modelData.choices
              PopupEntry {
                id: choice
                required property var modelData
                mood: surface.mood
                entryId: option.modelData.id
                choiceId: modelData.id
                name: option.modelData.label + ": " + modelData.label
                checked: option.modelData.value === modelData.id
                width: choiceLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                height: Style.space(22)
                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: choice.checked ? Style.selectedFill : (choice.hovered ? Style.hoverFill : "transparent")
                  border.width: 1
                  border.color: choice.checked ? surface.mood.highlight : Style.normalBorderColor
                }
                Label {
                  id: choiceLabel
                  anchors.centerIn: parent
                  text: choice.modelData.label
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          // The custom highlight: a swatch (click to pick from screen) and a field for a colour.
          Loader {
            active: option.modelData.id === "set:highlight" && option.modelData.value === "custom"
            visible: active
            sourceComponent: Row {
              spacing: Style.spacing.md
              PopupEntry {
                id: swatch
                mood: surface.mood
                entryId: "set:highlight:pick"
                name: surface.popup.pickColorLabel
                width: Style.space(22); height: width
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                  visible: swatch.focused
                  anchors.fill: parent
                  anchors.margins: -2
                  radius: Style.cornerRadius + 1
                  color: "transparent"
                  border.width: 1
                  border.color: surface.mood.highlight
                }
                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: surface.mood.highlight
                  border.width: 1
                  border.color: swatch.hovered || swatch.focused ? surface.ink : Style.normalBorderColor
                }
                PanelToolTip {
                  visible: swatch.hovered
                  text: surface.popup.pickColorLabel
                }
              }
              TextField {
                id: field
                width: Style.space(120)
                verticalPadding: Style.spacing.sm
                text: surface.popup.customColor
                placeholderText: surface.popup.colorHint
                maximumLength: 7
                Accessible.name: surface.popup.colorHint
                property bool refused: false
                accent: refused ? surface.mood.urgent : surface.mood.highlight
                onTextEdited: refused = false
                onAccepted: refused = !surface.popup.setColor(text)
                Keys.onEscapePressed: { text = surface.popup.customColor; refused = false; surface.popup.cancelEdit() }
                onActiveFocusChanged: if (activeFocus) surface.popup.editing = true
                Component.onCompleted: if (surface.popup.editing) { forceActiveFocus(); selectAll() }
                Connections {
                  target: surface.popup
                  function onEditingChanged() {
                    if (surface.popup.editing && field.visible) { field.forceActiveFocus(); field.selectAll() }
                  }
                  function onCustomColorChanged() {
                    if (!surface.popup.editing) { field.text = surface.popup.customColor; field.refused = false }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
}
