import QtQuick
import qs.Commons
import qs.Ui
import "../.."

// Tine — the popup surface.
//
// Rotates the bar's 13-tine quarter-marked comb into a vertical vernier spine
// beside the mood list, with a dismissible first-open bar controls highlight
// at the top and collapsed Manual controls (a single hairline segmented strip,
// plus the bar controls legend once dismissed) and collapsed Settings (quiet
// borderless typographic tabs with highlight underlines).
Item {
  id: surface

  required property var mood
  readonly property var popup: mood.popup

  implicitWidth: Style.space(324)
  implicitHeight: stack.implicitHeight

  // ---- contrast-aware colour helpers ---------------------------------------

  function srgbLin(c) { return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
  function relLum(c) { return 0.2126 * srgbLin(c.r) + 0.7152 * srgbLin(c.g) + 0.0722 * srgbLin(c.b) }
  function contrastRatio(a, b) {
    var la = relLum(a), lb = relLum(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }
  function mixColor(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  function ensureContrast(c, fg, bg, minRatio) {
    if (contrastRatio(c, bg) >= minRatio) return c
    var steps = [0.28, 0.46, 0.62, 0.76]
    for (var i = 0; i < steps.length; i++) {
      var m = mixColor(c, fg, steps[i])
      if (contrastRatio(m, bg) >= minRatio) return m
    }
    return mixColor(c, fg, 0.82)
  }

  readonly property color ink: mood.popupForeground
  readonly property color bg: mood.popupBackground
  readonly property color accent: ensureContrast(mood.highlight, ink, bg, 3.1)
  readonly property color faultColor: ensureContrast(mood.urgent, ink, bg, 3.2)
  readonly property string family: Style.font.family
  readonly property int moodRowHeight: Style.space(25)
  readonly property int sectionRowHeight: Style.space(26)

  readonly property int moodCount: surface.popup.moods ? surface.popup.moods.length : 0
  readonly property int landmarkStep: moodCount >= 9 ? Math.max(3, Math.round((moodCount - 1) / 3)) : 0
  function isLandmark(i) {
    if (i === 0 || i === moodCount - 1) return true
    if (landmarkStep <= 0) return false
    return (i % landmarkStep === 0) && ((moodCount - 1 - i) >= 2)
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: surface.ink
    font.family: surface.family
    font.pixelSize: Style.font.body
    renderType: Text.NativeRendering
    elide: Text.ElideRight
  }

  // Visible keyboard focus indicator: subtle fill + crisp 2 px leading bar in
  // the contrast-guarded highlight colour + whisper inner outline.
  component FocusPlate: Rectangle {
    property bool focused: false
    property bool hovered: false
    anchors.fill: parent
    radius: Style.cornerRadius
    color: focused ? Style.hoverFill : (hovered ? Util.alpha(surface.ink, 0.04) : "transparent")
    border.width: focused ? 1 : 0
    border.color: Util.alpha(surface.accent, 0.30)
    Rectangle {
      visible: parent.focused
      width: 2
      height: Math.max(8, parent.height - 6)
      x: 0
      anchors.verticalCenter: parent.verticalCenter
      color: surface.accent
    }
  }

  // Compact two-column bar gesture legend: brighter input on the left, quieter
  // action (and optional secondary detail) on the right.
  component GestureLegend: Column {
    id: legend
    property real inputOpacity: 0.90
    property real actionOpacity: 0.68
    property real detailOpacity: 0.50
    property int inputColumnWidth: Style.space(86)
    spacing: Style.spacing.xs

    Repeater {
      model: surface.popup.notes
      Item {
        id: noteRow
        required property var modelData
        width: legend.width
        implicitHeight: Math.max(inputText.implicitHeight, actionCol.implicitHeight)
        Accessible.role: Accessible.StaticText
        Accessible.name: modelData.text

        Label {
          id: inputText
          x: 0
          y: 0
          width: legend.inputColumnWidth
          text: noteRow.modelData.input
          font.pixelSize: Style.font.bodySmall
          opacity: legend.inputOpacity
          elide: Text.ElideRight
        }

        Column {
          id: actionCol
          x: legend.inputColumnWidth + Style.spacing.md
          y: 0
          width: Math.max(0, parent.width - x)
          spacing: 1

          Label {
            width: parent.width
            text: noteRow.modelData.action
            font.pixelSize: Style.font.bodySmall
            opacity: legend.actionOpacity
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
          }

          Label {
            visible: !!noteRow.modelData.detail
            width: parent.width
            text: noteRow.modelData.detail || ""
            font.pixelSize: Style.font.caption
            opacity: legend.detailOpacity
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
    spacing: Style.spacing.md

    // ---- 1. first-open bar controls highlight (dismissible) ----------------

    Loader {
      id: guideLoader
      active: surface.popup.guide.visible
      visible: active
      width: parent.width
      sourceComponent: Rectangle {
        width: guideLoader.width
        implicitHeight: guideBody.implicitHeight + Style.spacing.md * 2
        radius: Style.cornerRadius
        color: Util.alpha(surface.accent, 0.08)
        border.width: 1
        border.color: Util.alpha(surface.accent, 0.24)

        // Crisp 2 px leading accent bar echoing Tine's active tine and focus mark
        Rectangle {
          x: 0
          y: Style.spacing.sm
          width: 2
          height: Math.max(8, parent.height - Style.spacing.sm * 2)
          color: surface.accent
        }

        Column {
          id: guideBody
          x: Style.space(12)
          y: Style.spacing.md
          width: parent.width - Style.space(22)
          spacing: Style.spacing.sm

          Item {
            width: parent.width
            implicitHeight: Math.max(guideHeading.implicitHeight, dismissBtn.implicitHeight)

            Label {
              id: guideHeading
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: surface.popup.guide.title
              color: surface.accent
              font.pixelSize: Style.font.caption
              font.bold: true
              Accessible.role: Accessible.StaticText
              Accessible.name: surface.popup.guide.title
            }

            PopupEntry {
              id: dismissBtn
              mood: surface.mood
              entryId: surface.popup.guide.id
              name: surface.popup.guide.dismissName
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: dismissLabel.implicitWidth + Style.spacing.md * 2
              implicitHeight: Style.space(20)
              height: implicitHeight

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: dismissBtn.pressed ? Style.pressedFill
                  : (dismissBtn.focused ? Style.hoverFill
                    : (dismissBtn.hovered ? Util.alpha(surface.ink, 0.08) : Util.alpha(surface.ink, 0.04)))
                border.width: 1
                border.color: dismissBtn.focused ? surface.accent
                  : (dismissBtn.hovered ? Util.alpha(surface.ink, 0.34) : Util.alpha(surface.ink, 0.16))
              }

              Label {
                id: dismissLabel
                anchors.centerIn: parent
                text: surface.popup.guide.dismissLabel
                font.pixelSize: Style.font.caption
                font.bold: dismissBtn.focused
                opacity: dismissBtn.focused || dismissBtn.hovered ? 1.0 : 0.80
              }
            }
          }

          GestureLegend {
            width: parent.width
            inputOpacity: 0.92
            actionOpacity: 0.72
            detailOpacity: 0.54
          }
        }
      }
    }

    PanelSeparator {
      visible: surface.popup.guide.visible
      width: parent.width
      foreground: surface.ink
      strength: 0.11
    }

    // ---- 2. the thirteen moods paired with the rotated vernier spine -------

    Column {
      width: parent.width
      spacing: 0
      Repeater {
        model: surface.popup.moods
        PopupEntry {
          id: row
          required property var modelData
          required property int index
          mood: surface.mood
          entryId: modelData.id
          name: modelData.name
          kind: "option"
          checked: modelData.current
          width: parent.width
          height: surface.moodRowHeight

          readonly property bool landmark: surface.isLandmark(index)

          FocusPlate { focused: row.focused; hovered: row.hovered }

          // Vertical vernier spine mirroring the bar's 13-tine rail
          Item {
            x: Style.space(10)
            width: Style.space(12)
            height: parent.height

            // Continuous spine hairline (clipped cleanly at top & bottom ends)
            Rectangle {
              x: 2
              y: row.index === 0 ? Math.floor(parent.height / 2) : 0
              width: 1
              height: row.index === 0
                ? Math.ceil(parent.height / 2)
                : (row.index === surface.moodCount - 1 ? Math.floor(parent.height / 2) + 1 : parent.height)
              color: surface.ink
              opacity: 0.18
            }

            // Quiet landmark / regular tine notch
            Rectangle {
              visible: !row.modelData.current
              x: 3
              anchors.verticalCenter: parent.verticalCenter
              width: row.landmark ? 5 : 3
              height: 1
              color: surface.ink
              opacity: row.landmark ? 0.50 : 0.26
            }

            // Current mood bloom on the spine
            Rectangle {
              visible: row.modelData.current
              x: 1
              width: 2
              height: 11
              anchors.verticalCenter: parent.verticalCenter
              color: surface.accent
            }
            Rectangle {
              visible: row.modelData.current
              x: 3
              width: 7
              height: 2
              anchors.verticalCenter: parent.verticalCenter
              color: surface.accent
            }
          }

          Label {
            x: Style.space(28)
            width: parent.width - x - countLabel.implicitWidth - Style.spacing.xl
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.label
            font.bold: row.modelData.current
            opacity: row.modelData.current ? 1.0 : (row.focused || row.hovered ? 0.94 : 0.76)
          }

          Label {
            id: countLabel
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.formatNumber(row.modelData.count)
            font.pixelSize: Style.font.caption
            opacity: row.modelData.current || row.focused ? 0.65 : 0.36
          }
        }
      }
    }

    PanelSeparator { width: parent.width; foreground: surface.ink; strength: 0.11 }

    // ---- 3. manual controls, collapsed -------------------------------------

    Column {
      width: parent.width
      spacing: Style.spacing.xs

      PopupEntry {
        id: manualHeader
        mood: surface.mood
        entryId: surface.popup.manual.id
        name: surface.popup.manual.name
        kind: "disclosure"
        expanded: surface.popup.manual.expanded
        width: parent.width
        height: surface.sectionRowHeight

        FocusPlate { focused: manualHeader.focused; hovered: manualHeader.hovered }

        // Architectural hairline + / - indicator
        Item {
          x: Style.space(10)
          width: 8; height: 8
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            width: 7; height: 1
            anchors.centerIn: parent
            color: manualHeader.expanded ? surface.accent : surface.ink
            opacity: manualHeader.expanded || manualHeader.focused ? 0.9 : 0.55
          }
          Rectangle {
            visible: !manualHeader.expanded
            width: 1; height: 7
            anchors.centerIn: parent
            color: surface.ink
            opacity: manualHeader.focused ? 0.9 : 0.55
          }
        }

        Label {
          x: Style.space(26)
          anchors.verticalCenter: parent.verticalCenter
          text: surface.popup.manual.label
          font.pixelSize: Style.font.bodySmall
          opacity: manualHeader.expanded || manualHeader.focused || manualHeader.hovered ? 0.95 : 0.68
        }
      }

      // Single quiet hairline segmented control strip (Back | Play/Pause | Skip)
      Rectangle {
        visible: surface.popup.controls.length > 0
        x: Style.spacing.sm
        width: parent.width - Style.spacing.sm * 2
        height: Style.space(28)
        radius: Style.cornerRadius
        color: Util.alpha(surface.ink, 0.03)
        border.width: 1
        border.color: Util.alpha(surface.ink, 0.14)

        Row {
          anchors.fill: parent
          Repeater {
            model: surface.popup.controls
            PopupEntry {
              id: control
              required property var modelData
              required property int index
              mood: surface.mood
              entryId: modelData.id
              name: modelData.name
              enabled: modelData.enabled
              width: Math.floor(parent.width / Math.max(1, surface.popup.controls.length))
              height: parent.height

              // Segment hover / focus fill
              Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(0, Style.cornerRadius - 1)
                color: control.pressed ? Style.pressedFill : (control.focused ? Style.hoverFill : (control.hovered && control.enabled ? Util.alpha(surface.ink, 0.04) : "transparent"))
              }

              // Hairline divider between segments
              Rectangle {
                visible: control.index > 0
                x: 0
                y: 5
                width: 1
                height: parent.height - 10
                color: Util.alpha(surface.ink, 0.14)
              }

              // Crisp bottom focus underline
              Rectangle {
                visible: control.focused
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.spacing.lg
                anchors.rightMargin: Style.spacing.lg
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                height: 2
                color: surface.accent
              }

              Label {
                anchors.centerIn: parent
                text: control.modelData.label
                font.pixelSize: Style.font.bodySmall
                opacity: control.modelData.enabled ? (control.focused ? 1.0 : 0.88) : 0.32
              }
            }
          }
        }
      }

      // Once the first-open highlight has been dismissed, keep the bar
      // controls legend quietly tucked inside Manual controls for recall.
      Loader {
        id: manualLegendLoader
        active: surface.popup.controls.length > 0 && !surface.popup.guide.visible
        visible: active
        width: parent.width
        sourceComponent: Item {
          width: manualLegendLoader.width
          implicitHeight: manualLegendCol.implicitHeight + Style.spacing.sm + Style.spacing.xs

          Column {
            id: manualLegendCol
            x: Style.space(12)
            y: Style.spacing.sm
            width: parent.width - Style.space(22)
            spacing: Style.spacing.xs

            Label {
              text: surface.popup.guide.title
              font.pixelSize: Style.font.caption
              opacity: 0.48
              Accessible.role: Accessible.StaticText
              Accessible.name: surface.popup.guide.title
            }

            GestureLegend {
              width: parent.width
              inputOpacity: 0.78
              actionOpacity: 0.58
              detailOpacity: 0.44
            }
          }
        }
      }
    }

    // ---- 4. settings, collapsed (quiet borderless typographic tabs) --------

    Column {
      width: parent.width
      spacing: Style.spacing.xs

      PopupEntry {
        id: settingsHeader
        mood: surface.mood
        entryId: surface.popup.settings.id
        name: surface.popup.settings.name
        kind: "disclosure"
        expanded: surface.popup.settings.expanded
        width: parent.width
        height: surface.sectionRowHeight

        FocusPlate { focused: settingsHeader.focused; hovered: settingsHeader.hovered }

        Item {
          x: Style.space(10)
          width: 8; height: 8
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            width: 7; height: 1
            anchors.centerIn: parent
            color: settingsHeader.expanded ? surface.accent : surface.ink
            opacity: settingsHeader.expanded || settingsHeader.focused ? 0.9 : 0.55
          }
          Rectangle {
            visible: !settingsHeader.expanded
            width: 1; height: 7
            anchors.centerIn: parent
            color: surface.ink
            opacity: settingsHeader.focused ? 0.9 : 0.55
          }
        }

        Label {
          x: Style.space(26)
          anchors.verticalCenter: parent.verticalCenter
          text: surface.popup.settings.label
          font.pixelSize: Style.font.bodySmall
          opacity: settingsHeader.expanded || settingsHeader.focused || settingsHeader.hovered ? 0.95 : 0.68
        }
      }

      Column {
        visible: surface.popup.options.length > 0
        width: parent.width
        spacing: Style.spacing.xxs
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
            height: optBody.implicitHeight + Style.spacing.sm * 2

            FocusPlate { focused: option.focused; hovered: false }

            Column {
              id: optBody
              x: Style.space(12)
              y: Style.spacing.sm
              width: parent.width - Style.space(20)
              spacing: 2

              Label {
                text: option.modelData.label
                font.pixelSize: Style.font.caption
                opacity: option.focused ? 0.85 : 0.52
              }

              Flow {
                x: -Style.space(4)
                width: parent.width + Style.space(4)
                spacing: Style.space(10)
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
                    width: choiceText.implicitWidth + Style.space(8)
                    height: Style.space(20)

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: choice.pressed ? Style.pressedFill : (choice.hovered ? Style.hoverFill : "transparent")
                    }

                    Label {
                      id: choiceText
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.verticalCenterOffset: -1
                      text: choice.modelData.label
                      font.pixelSize: Style.font.bodySmall
                      font.bold: choice.checked
                      opacity: choice.checked ? 1.0 : (choice.hovered ? 0.84 : 0.50)
                    }

                    // Quiet 2 px highlight underline beneath the selected choice
                    Rectangle {
                      visible: choice.checked
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.leftMargin: Style.space(4)
                      anchors.rightMargin: Style.space(4)
                      anchors.bottom: parent.bottom
                      height: 2
                      color: surface.accent
                    }
                  }
                }
              }

              // Custom highlight colour swatch + hex field (only instantiated on
              // the highlight row when Custom is active so other settings rows
              // never carry hidden PopupEntry/ToolTip instances).
              Loader {
                active: option.modelData.id === "set:highlight" && option.modelData.value === "custom"
                visible: active
                sourceComponent: Row {
                  topPadding: Style.spacing.sm
                  spacing: Style.spacing.md

                  // Swatch displays the exact user-chosen highlight colour inside
                  // a subtle foreground hairline so even pale colours stay framed.
                  // Clicking (or pressing Enter when focused) samples a pixel from
                  // the screen and adopts its colour.
                  PopupEntry {
                    id: colorSwatch
                    mood: surface.mood
                    entryId: "set:highlight:pick"
                    name: surface.popup.pickColorLabel
                    width: Style.space(22); height: width
                    anchors.verticalCenter: parent.verticalCenter

                    readonly property color reticleInk: surface.relLum(surface.mood.highlight) > 0.35
                      ? Qt.rgba(0.06, 0.07, 0.09, 0.85) : Qt.rgba(0.96, 0.97, 0.98, 0.90)

                    // Outer keyboard focus ring kept outside the swatch fill so
                    // it remains visible even when the swatch matches accent.
                    Rectangle {
                      visible: colorSwatch.focused
                      anchors.fill: parent
                      anchors.margins: -2
                      radius: Style.cornerRadius + 1
                      color: "transparent"
                      border.width: 1
                      border.color: surface.accent
                    }

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.cornerRadius
                      color: surface.mood.highlight
                      border.width: 1
                      border.color: colorSwatch.hovered || colorSwatch.focused
                        ? Util.alpha(surface.ink, 0.78) : Util.alpha(surface.ink, 0.34)
                      scale: colorSwatch.pressed ? 0.92 : 1.0
                      Behavior on scale {
                        NumberAnimation {
                          duration: Style.duration(120)
                          easing.type: Easing.Bezier
                          easing.bezierCurve: Style.easeOut
                        }
                      }

                      // Quiet crosshair reticle appears on hover/focus so the
                      // swatch stays clean at rest and reads as a picker in use.
                      Item {
                        anchors.centerIn: parent
                        width: 8; height: 8
                        opacity: colorSwatch.hovered || colorSwatch.focused ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
                        Rectangle {
                          width: 8; height: 1
                          anchors.centerIn: parent
                          color: colorSwatch.reticleInk
                        }
                        Rectangle {
                          width: 1; height: 8
                          anchors.centerIn: parent
                          color: colorSwatch.reticleInk
                        }
                      }
                    }

                    PanelToolTip {
                      visible: colorSwatch.hovered
                      text: surface.popup.pickColorLabel
                    }
                  }

                  TextField {
                    id: colorField
                    width: Style.space(122)
                    verticalPadding: Style.spacing.xs
                    text: surface.popup.customColor
                    placeholderText: surface.popup.colorHint
                    maximumLength: 7
                    Accessible.name: surface.popup.colorHint
                    property bool refused: false
                    foreground: surface.ink
                    accent: refused ? surface.faultColor : surface.accent
                    onTextEdited: refused = false
                    onAccepted: refused = !surface.popup.setColor(text)
                    Keys.onEscapePressed: {
                      text = surface.popup.customColor
                      refused = false
                      surface.popup.cancelEdit()
                    }
                    onActiveFocusChanged: if (activeFocus) surface.popup.editing = true
                    Component.onCompleted: if (surface.popup.editing) {
                      forceActiveFocus()
                      selectAll()
                    }
                    Connections {
                      target: surface.popup
                      function onEditingChanged() {
                        if (surface.popup.editing && colorField.visible) {
                          colorField.forceActiveFocus()
                          colorField.selectAll()
                        }
                      }
                      function onCustomColorChanged() {
                        if (!surface.popup.editing) {
                          colorField.text = surface.popup.customColor
                          colorField.refused = false
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
  }
}
