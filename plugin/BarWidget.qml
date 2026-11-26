import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "core/Color.js" as ColorUtil
import "core/Latch.js" as Latch

// The bar item: the plugin's one presence on the bar.
//
// This file owns the mechanics and none of the look. It reads the settings,
// handles every input on the bar item (click, right-click, both scroll axes,
// the tooltip), hosts the popup, and hands the chosen surface a `mood` object
// (Mood.qml) to draw from. What the item looks like is the surface's business:
// surfaces/<id>/Bar.qml. docs/surfaces.md describes the seam.
//
//   click          play or pause
//   right-click    the moods popup
//   scroll         down skips, up goes back        } swapped by the
//   sideways       next or previous mood           } moodScroll setting
//   right-button held + scroll   the sideways action, for mice with one wheel
//
// Shift+scroll was the first idea for that. It cannot work here: the bar never
// has keyboard focus, so Hyprland never tells it which modifiers are held.
BarWidget {
  id: root
  moduleName: "0xbreadguy.mood"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("0xbreadguy.mood") : null

  // ---- settings (this widget's entry in shell.json) -------------------------

  readonly property string surfaceSetting: String(setting("surface", "tine"))
  readonly property string highlightSetting: String(setting("highlight", "theme"))
  readonly property string animationSetting: String(setting("animation", ""))
  readonly property string moodScroll: setting("moodScroll", "sideways") === "vertical" ? "vertical" : "sideways"
  readonly property bool mediaKeys: setting("mediaKeys", true) !== false
  // Not in the popup: "null" plays into nothing, for working on the plugin.
  readonly property string audioSetting: setting("audio", "auto") === "null" ? "null" : "auto"

  readonly property bool customHighlight: /^#[0-9a-fA-F]{6}$/.test(highlightSetting)
  readonly property color highlight: customHighlight ? highlightSetting : Commons.Color.accent

  // Applied here first so the change shows on the click itself; the shell.json
  // write comes back through the bar as the same value.
  function setSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    if (entry[key] === value) return
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  onMediaKeysChanged: if (service) service.mediaKeys = mediaKeys
  onAudioSettingChanged: if (service) service.audioSetting = audioSetting
  onServiceChanged: {
    if (!service) return
    service.mediaKeys = mediaKeys
    service.audioSetting = audioSetting
    syncFeatureClient()
  }

  // ---- surfaces ------------------------------------------------------------

  // [{ id, name }] from surfaces/index.json.
  property var surfaces: [{ id: "tine", name: "Tine" }]
  property string surfaceId: ""
  property string surfaceProblem: ""
  readonly property Item surface: barLoader.item
  // What the surface declares about itself.
  readonly property var variants: surface && Array.isArray(surface.variants) ? surface.variants : []
  readonly property string variant: {
    for (var i = 0; i < variants.length; i++) if (variants[i].id === animationSetting) return animationSetting
    return variants.length > 0 ? String(variants[0].id) : ""
  }
  readonly property bool wantsFeatures: !!surface && surface.usesFeatures === true && !Style.reduceMotion && root.visible

  function surfaceUrl(id, file) { return Qt.resolvedUrl("surfaces/" + id + "/" + file) }

  function loadSurface() {
    var id = /^[a-z0-9][a-z0-9-]{0,31}$/.test(surfaceSetting) ? surfaceSetting : "plain"
    if (id === surfaceId && barLoader.status === Loader.Ready) return
    surfaceProblem = ""
    surfaceId = id
    barLoader.setSource(surfaceUrl(id, "Bar.qml"), { mood: mood })
  }

  // A surface that won't load must not take the bar item with it.
  function surfaceFailed() {
    if (surfaceId === "plain") return
    surfaceProblem = "the \"" + surfaceId + "\" surface could not be loaded; showing plain"
    console.warn("mood: " + surfaceProblem)
    surfaceId = "plain"
    barLoader.setSource(surfaceUrl("plain", "Bar.qml"), { mood: mood })
  }

  onSurfaceSettingChanged: loadSurface()
  Component.onCompleted: loadSurface()

  FileView {
    path: decodeURIComponent(String(Qt.resolvedUrl("surfaces/index.json")).replace(/^file:\/\//, ""))
    onLoaded: {
      try {
        var listed = JSON.parse(text()).surfaces
        var out = []
        for (var i = 0; i < listed.length && out.length < 32; i++) {
          var s = listed[i]
          if (s && /^[a-z0-9][a-z0-9-]{0,31}$/.test(String(s.id)))
            out.push({ id: String(s.id), name: String(s.name || s.id).replace(/[<>\u0000-\u001f]/g, "").slice(0, 32) })
        }
        if (out.length > 0) root.surfaces = out
      } catch (e) {}
    }
  }

  readonly property string featureKey: "widget-" + Math.random().toString(36).slice(2)
  function syncFeatureClient() { if (service) service.setFeatureClient(featureKey, wantsFeatures) }
  onWantsFeaturesChanged: syncFeatureClient()
  Component.onDestruction: {
    pickerDelay.stop()
    reopenAfterPick = false
    if (picker.running) picker.running = false
    if (service) service.setFeatureClient(featureKey, false)
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(hit)
  }

  // ---- what the surface is given -------------------------------------------

  Commons.Translations { id: translations; directory: Qt.resolvedUrl("i18n") }
  readonly property var strings: translations

  Mood {
    id: mood
    state: root.service ? root.service.playback : "failed"
    failure: root.service ? root.service.failureKind : "player"
    moods: root.service ? root.service.moods : []
    moodIndex: root.service ? root.service.moodIndex : 0
    moodLabel: root.service ? root.service.moodLabel : ""
    nameShowing: root.service ? root.service.nameShowing : false
    nameText: root.service ? root.service.nameText : ""
    nameDirection: root.service ? root.service.nameDirection : 0
    trackSerial: root.service ? root.service.trackSerial : 0
    features: root.service ? root.service.features : null
    highlight: root.highlight
    foreground: root.bar ? root.bar.barForeground : Commons.Color.bar.text
    background: root.bar ? root.bar.background : Commons.Color.bar.background
    muted: Commons.Color.muted
    urgent: root.bar ? root.bar.urgent : Commons.Color.urgent
    popupForeground: Commons.Color.popups.text
    popupBackground: Commons.Color.popups.background
    variant: root.variant
    reducedMotion: Style.reduceMotion
    barSize: root.barSize
    vertical: root.vertical
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    fontSize: Style.font.body
    fixedEdge: root.fixedEdge
    hovered: area.containsMouse
    pressed: ((area.pressedButtons | hit.heldButtons) & (Qt.LeftButton | Qt.RightButton)) !== 0
    popup: popupModel
  }

  Connections {
    target: root.service
    function onSkipped(direction) { mood.skipped(direction) }
    function onMoodChanged(direction, label) { mood.moodChanged(direction, label) }
    function onRefused(what) { mood.refused(what) }
    function onFailed(kind) { mood.failed(kind) }
    function onPopupRequested() { if (root.visible && root.service.claimPopup()) root.togglePanel() }
  }

  PopupModel {
    id: popupModel
    widget: root
  }

  // ---- the item itself -----------------------------------------------------

  implicitWidth: surface ? Math.max(Style.space(12), surface.implicitWidth) : Style.bar.iconSlot
  implicitHeight: surface ? Math.max(Style.space(12), surface.implicitHeight) : Style.bar.iconSlot

  Loader {
    id: barLoader
    anchors.fill: parent
    onStatusChanged: if (status === Loader.Error) Qt.callLater(root.surfaceFailed)
    onLoaded: root.syncFeatureClient()
  }

  // ---- input ---------------------------------------------------------------

  readonly property var latch: Latch.create()

  function press(button) {
    if (button === Qt.RightButton) { togglePanel(); return }
    if (button !== Qt.LeftButton || !service) return
    service.toggle()
  }

  // True once a scroll has been made with the right button held, so letting
  // the button go doesn't also open the popup.
  property bool chorded: false

  function wheel(event) {
    event.accepted = true
    if (!service) return
    // A trackpad says when the fingers lift; that ends the gesture. Anything a
    // platform sends as momentum after it never counts.
    if (event.phase === Qt.ScrollMomentum) return
    if (event.phase === Qt.ScrollEnd) { latch.end(); return }
    // One wheel, two jobs: Shift turns it sideways where the platform reports
    // modifiers to the bar (Hyprland does not: the bar never has the keyboard),
    // and so does holding the right button, which always works.
    var held = (area.pressedButtons & Qt.RightButton) !== 0
    var sideways = held || (event.modifiers & Qt.ShiftModifier) !== 0
    var u = Latch.units(event.pixelDelta.x, event.pixelDelta.y, event.angleDelta.x, event.angleDelta.y,
                        event.phase, sideways, latch.threshold)
    var step = latch.wheel(u.x, u.y, Date.now())
    if (!step) return
    if (held) chorded = true
    // Using a scroll gesture on the bar shows the user already knows their way
    // around, so retire the popup's first-open highlight automatically.
    service.dismissGuide()
    // One step, on one axis: a track, or a mood, never both.
    var moodAxis = moodScroll === "vertical" ? "y" : "x"
    if (step.axis === moodAxis) service.stepMood(step.dir)
    else if (step.dir > 0) service.skip()
    else service.back()
  }

  readonly property string stateWord: translations.t("state." + mood.state)
  readonly property string tooltip: {
    var lines = [translations.t("tooltip.line").arg(mood.moodLabel || "mood").arg(stateWord)]
    if (mood.state === "failed" || mood.state === "offline") {
      var why = translations.t("failure." + (mood.failure || "source"))
      if (why) lines.push(why)
    }
    if (root.surfaceProblem) lines.push(root.surfaceProblem)
    lines.push(translations.t("tooltip.click"))
    lines.push(translations.t("tooltip.scroll." + moodScroll))
    return lines.join("\n")
  }
  // The bar copies a tooltip's text when the pointer arrives; hand it the new
  // text while it is showing, so a state change doesn't leave it stale.
  onTooltipChanged: if (hit.tooltipHovered && bar) bar.showTooltip(hit, tooltip)

  property var registeredBar: null
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(hit)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(hit)
  }
  onBarChanged: syncClickRegistration()

  // The click target, shaped like Omarchy's WidgetButton so the bar treats it
  // as one: the bar's own drag handler takes left presses and forwards a
  // click as triggerPress(); a panel open elsewhere forwards clicks the same way.
  Item {
    id: hit
    anchors.fill: parent

    property bool interactive: true
    property bool pressable: true
    property bool concealed: false
    property int heldButtons: Qt.NoButton
    readonly property bool tooltipHovered: area.containsMouse
    readonly property string tooltipText: root.tooltip

    function triggerPress(button) {
      if (root.bar) root.bar.hideTooltip(hit)
      root.press(button)
    }

    Accessible.role: Accessible.Button
    Accessible.name: translations.t("a11y.item").arg(mood.moodLabel || "mood").arg(root.stateWord)
    Accessible.description: translations.t("tooltip.click") + ". " + translations.t("tooltip.scroll." + root.moodScroll)
    Accessible.onPressAction: root.press(Qt.LeftButton)

    MouseArea {
      id: area
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(hit, hit.tooltipText)
      onExited: if (root.bar) root.bar.hideTooltip(hit)
      onPressed: function(mouse) { if (mouse.button === Qt.RightButton) root.chorded = false }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton && root.chorded) { root.chorded = false; return }
        hit.triggerPress(mouse.button)
      }
      // A second click soon after the first reaches the bar as a double-click,
      // which the bar keeps for its own use and would swallow. Here it is just
      // the second click: pause, then play again, must work at any speed.
      onDoubleClicked: function(mouse) {
        mouse.accepted = true
        hit.triggerPress(mouse.button)
      }
      onWheel: function(event) { root.wheel(event) }
    }
  }

  // ---- screen highlight color picker ---------------------------------------

  property bool pickingColor: false
  property bool reopenAfterPick: false

  function pickHighlightColor() {
    if (picker.running || pickerDelay.running || !visible) return
    pickingColor = true
    reopenAfterPick = panelOpen
    picker.pickedHex = ""
    picker.exitCode = -1
    var wasOpen = panelOpen
    if (panelOpen) close()
    // Wait for KeyboardPanel's fade-out and surface unmap so hyprpicker does
    // not freeze the popup onto the desktop before the user clicks a pixel.
    pickerDelay.interval = wasOpen ? Style.duration(120) + 60 : 1
    pickerDelay.restart()
  }

  function pickerFinished() {
    if (picker.running) return
    var hex = picker.exitCode === 0 ? picker.pickedHex : ""
    picker.pickedHex = ""
    picker.exitCode = -1
    var reopen = reopenAfterPick
    reopenAfterPick = false
    pickingColor = false
    if (hex !== "") popupModel.applyPickedColor(hex)
    if (reopen && visible && !panelOpen && popupLoader.status === Loader.Ready) {
      popupModel.restoreHighlightSettings()
      panelOpen = true
    }
  }

  Timer {
    id: pickerDelay
    onTriggered: {
      if (root.panelOpen || !root.visible) {
        root.pickingColor = false
        root.reopenAfterPick = false
        return
      }
      picker.command = ["setpriv", "--pdeathsig", "TERM", "hyprpicker", "-f", "hex", "-b", "-l", "-r"]
      picker.running = true
    }
  }

  Process {
    id: picker
    property string pickedHex: ""
    property int exitCode: -1
    stdout: SplitParser {
      onRead: function(line) {
        if (picker.pickedHex !== "" || line.length > 256) return
        var hex = ColorUtil.parsePicked(line)
        if (hex !== "") picker.pickedHex = hex
      }
    }
    onExited: function(code) { exitCode = code }
    onRunningChanged: if (!running) Qt.callLater(root.pickerFinished)
  }

  // ---- the popup -----------------------------------------------------------

  // Shape contract for the shell's summon/hide/toggle routing: open, close
  // and opened on the bar-widget root.
  property bool panelOpen: false
  readonly property bool opened: panelOpen
  readonly property Item anchor: hit
  readonly property QtObject context: mood
  readonly property QtObject model: popupModel

  function open() { if (popupLoader.status === Loader.Ready) { popupModel.reset(); panelOpen = true } }
  function close() { panelOpen = false }
  function togglePanel() { if (panelOpen) close(); else open() }
  onVisibleChanged: if (!visible) close()

  // Loaded with the widget, as stock panels are, so a failure shows in the
  // shell's log at once; its contents are built only when it first opens.
  Loader {
    id: popupLoader
    Component.onCompleted: setSource(Qt.resolvedUrl("MoodPopup.qml"), { widget: root })
  }
}
