import QtQuick
import "core/Color.js" as ColorUtil

// What the popup holds, what is focused in it, and what each thing does.
//
// A surface's Popup.qml draws these lists and nothing here draws anything, so
// two surfaces can lay the same popup out in different ways while the keys,
// the focus order, the names read to a screen reader and the actions stay the
// same. It reaches a surface as `mood.popup`.
//
//   guide      first-open bar controls highlight state and dismiss action
//   notes      the bar's gestures as compact input/action pairs
//   moods      the moods to choose from; the current one is marked
//   manual     a collapsed section: back, play or pause, skip (plus notes once dismissed)
//   settings   a collapsed section: highlight, animation, scroll axis, surface
//
// Every interactive thing has an `id`. One of them is focused (`focusId`); the
// arrow keys move it and the pointer moves it too, like the shell's own panels.
QtObject {
  id: model

  // The bar widget: its service, settings and strings. Surfaces don't use it.
  property var widget: null

  readonly property var service: widget ? widget.service : null
  readonly property var strings: widget ? widget.strings : null
  function t(key) { return strings ? strings.t(key) : key }

  // ---- what a surface draws -------------------------------------------------

  readonly property string title: t("popup.title")

  // First-open highlight state for the bar controls legend. Shown at the top
  // until explicitly dismissed or a bar scroll gesture is used; afterward the
  // same legend lives inside the collapsed Manual controls section.
  readonly property bool guideVisible: !!service && !service.guideDismissed
  readonly property var guide: ({
    id: "guide:dismiss",
    visible: guideVisible,
    title: t("guide.title"),
    dismissLabel: t("guide.dismiss"),
    dismissName: t("guide.dismiss.name")
  })

  function makeNote(id, input, action, detail) {
    var text = input + ": " + action + (detail ? ", " + detail : "")
    return { id: id, input: input, action: action, detail: detail, text: text }
  }

  // [{ id, input, action, detail, text }]
  readonly property var notes: {
    var axis = widget ? widget.moodScroll : "sideways"
    var out = [
      makeNote("note.click", t("note.click.input"), t("note.click.action"), ""),
      makeNote("note.scroll", t("note.scroll.input"), t("note.scroll." + axis + ".action"), ""),
      makeNote("note.mood", t("note.sideways.input"), t("note.sideways." + axis + ".action"), t("note.sideways.detail"))
    ]
    if (widget && widget.mediaKeys)
      out.push(makeNote("note.keys", t("note.keys.input"), t("note.keys.action"), ""))
    return out
  }

  // [{ id, moodId, label, count, current, name }]. `name` is what a screen
  // reader should say for the entry.
  readonly property var moods: {
    var list = service ? service.moods : []
    var index = service ? service.moodIndex : -1
    var out = []
    for (var i = 0; i < list.length; i++) {
      var current = i === index
      out.push({ id: "mood:" + list[i].id, moodId: list[i].id, label: list[i].label, count: list[i].count,
                 current: current, name: current ? t("mood.current").arg(list[i].label) : list[i].label })
    }
    return out
  }

  // The two collapsed sections: { id, label, expanded, name }.
  property bool manualOpen: false
  property bool settingsOpen: false
  readonly property var manual: ({ id: "manual", label: t("manual.title"), expanded: manualOpen,
                                   name: t(manualOpen ? "disclosure.open" : "disclosure.closed").arg(t("manual.title")) })
  readonly property var settings: ({ id: "settings", label: t("settings.title"), expanded: settingsOpen,
                                     name: t(settingsOpen ? "disclosure.open" : "disclosure.closed").arg(t("settings.title")) })

  // The manual controls, empty while their section is collapsed:
  // [{ id: "back" | "toggle" | "skip", label, enabled, name }]
  readonly property var controls: {
    if (!manualOpen) return []
    var state = service ? service.playback : "stopped"
    var going = state === "playing" || state === "loading"
    var canBack = service ? service.canBack : false
    return [
      { id: "back", label: t("manual.back"), enabled: canBack, name: t(canBack ? "manual.back" : "manual.back.none") },
      { id: "toggle", label: t(going ? "manual.pause" : "manual.play"), enabled: true, name: t(going ? "manual.pause" : "manual.play") },
      { id: "skip", label: t("manual.skip"), enabled: true, name: t("manual.skip") }
    ]
  }

  // The settings, empty while their section is collapsed:
  // [{ id, label, value, choices: [{ id, label }], color }]
  // `color` is only on the highlight row: the custom colour as #rrggbb.
  readonly property var options: {
    if (!settingsOpen || !widget) return []
    var out = []
    out.push({ id: "set:highlight", label: t("settings.highlight"),
               value: widget.customHighlight ? "custom" : "theme", color: customColor,
               choices: [{ id: "theme", label: t("settings.highlight.theme") },
                         { id: "custom", label: t("settings.highlight.custom") }] })
    var variants = []
    for (var i = 0; i < widget.variants.length; i++)
      variants.push({ id: String(widget.variants[i].id), label: clean(widget.variants[i].name || widget.variants[i].id) })
    if (variants.length > 1)
      out.push({ id: "set:animation", label: t("settings.animation"), value: widget.variant, choices: variants })
    out.push({ id: "set:moodScroll", label: t("settings.moodScroll"), value: widget.moodScroll,
               choices: [{ id: "sideways", label: t("settings.moodScroll.sideways") },
                         { id: "vertical", label: t("settings.moodScroll.vertical") }] })
    var surfaces = []
    for (var s = 0; s < widget.surfaces.length; s++)
      surfaces.push({ id: widget.surfaces[s].id, label: widget.surfaces[s].name })
    if (surfaces.length > 1)
      out.push({ id: "set:surface", label: t("settings.surface"), value: widget.surfaceId, choices: surfaces })
    out.push({ id: "set:mediaKeys", label: t("settings.mediaKeys"), value: widget.mediaKeys ? "on" : "off",
               choices: [{ id: "on", label: t("settings.on") }, { id: "off", label: t("settings.off") }] })
    return out
  }

  // The custom highlight last typed, kept while "Theme" is chosen so switching
  // back to "Custom" restores it.
  property string customColor: "#7aa2f7"
  readonly property string colorHint: t("settings.highlight.hint")
  readonly property string pickColorLabel: t("settings.highlight.pick")
  readonly property bool pickingColor: widget ? widget.pickingColor : false
  // True while a text field in the popup has the keys. A surface's field takes
  // focus when this turns true and calls setColor() or cancelEdit() to end it.
  property bool editing: false

  // The focused entry's id, and every focusable id in order.
  property string focusId: ""
  readonly property var order: {
    var ids = []
    if (guideVisible) ids.push("guide:dismiss")
    for (var i = 0; i < moods.length; i++) ids.push(moods[i].id)
    ids.push("manual")
    for (var c = 0; c < controls.length; c++) ids.push(controls[c].id)
    ids.push("settings")
    for (var o = 0; o < options.length; o++) {
      ids.push(options[o].id)
      if (options[o].id === "set:highlight" && options[o].value === "custom")
        ids.push("set:highlight:pick")
    }
    return ids
  }

  // A surface calls this (through PopupEntry) so the focused entry stays in view.
  signal reveal(Item item)
  // The keys go back to the popup after a text field is done with them.
  signal focusBack()

  // ---- what a surface may call (PopupEntry does it for you) -----------------

  function point(id) { if (!editing && order.indexOf(id) !== -1) focusId = id }

  function activate(id) {
    if (!service || !widget) return
    focusId = id
    if (id === "guide:dismiss") {
      service.dismissGuide()
    } else if (id.indexOf("mood:") === 0) {
      service.setMood(id.slice(5))
      widget.close()
    } else if (id === "manual") {
      manualOpen = !manualOpen
    } else if (id === "settings") {
      settingsOpen = !settingsOpen
    } else if (id === "back") {
      service.back()
    } else if (id === "toggle") {
      service.toggle()
    } else if (id === "skip") {
      service.skip()
    } else if (id === "set:highlight:pick") {
      pickColor()
    } else if (id === "set:highlight" && option(id) && option(id).value === "custom") {
      editing = true
    } else if (id.indexOf("set:") === 0) {
      adjustOption(id, 1)
    }
  }

  function choose(id, choiceId) {
    if (!widget) return
    focusId = id
    if (id === "set:highlight") {
      if (choiceId === "custom") { widget.setSetting("highlight", customColor); editing = true }
      else { widget.setSetting("highlight", "theme"); cancelEdit() }
    } else if (id === "set:animation") {
      widget.setSetting("animation", String(choiceId))
    } else if (id === "set:moodScroll") {
      widget.setSetting("moodScroll", choiceId === "vertical" ? "vertical" : "sideways")
    } else if (id === "set:surface") {
      widget.setSetting("surface", String(choiceId))
    } else if (id === "set:mediaKeys") {
      widget.setSetting("mediaKeys", choiceId === "on")
    }
  }

  // Accepts #rgb or #rrggbb, with or without the #. Returns whether it was one.
  function setColor(text) {
    var s = ColorUtil.normalizeHex(text)
    if (s === "") return false
    customColor = s
    if (widget) widget.setSetting("highlight", s)
    cancelEdit()
    return true
  }

  function pickColor() {
    if (!widget) return
    cancelEdit()
    widget.pickHighlightColor()
  }

  function applyPickedColor(hex) {
    var s = ColorUtil.normalizeHex(hex)
    if (s === "") return false
    customColor = s
    if (widget) widget.setSetting("highlight", s)
    cancelEdit()
    return true
  }

  function restoreHighlightSettings() {
    editing = false
    manualOpen = false
    settingsOpen = true
    if (widget && widget.customHighlight) customColor = widget.highlightSetting.toLowerCase()
    focusId = order.indexOf("set:highlight:pick") !== -1 ? "set:highlight:pick" : "set:highlight"
  }

  function cancelEdit() {
    if (!editing) return
    editing = false
    focusBack()
  }

  // ---- keys (MoodPopup.qml calls these) ------------------------------------

  // Up and down, and Tab.
  function move(delta) {
    var ids = order
    if (ids.length === 0) return
    var i = ids.indexOf(focusId)
    i = i === -1 ? 0 : ((i + delta) % ids.length + ids.length) % ids.length
    focusId = ids[i]
  }

  // Left and right: change a setting, or walk along the manual controls.
  function adjust(delta) {
    if (focusId.indexOf("set:") === 0) { adjustOption(focusId, delta); return }
    var row = ["back", "toggle", "skip"]
    var i = row.indexOf(focusId)
    if (i === -1 || !manualOpen) return
    focusId = row[Math.max(0, Math.min(row.length - 1, i + delta))]
  }

  function option(id) {
    for (var i = 0; i < options.length; i++) if (options[i].id === id) return options[i]
    return null
  }

  function adjustOption(id, delta) {
    var o = option(id)
    if (!o || o.choices.length === 0) return
    var i = 0
    for (var k = 0; k < o.choices.length; k++) if (o.choices[k].id === o.value) i = k
    i = ((i + delta) % o.choices.length + o.choices.length) % o.choices.length
    choose(id, o.choices[i].id)
    if (id === "set:highlight") cancelEdit()
  }

  function currentMoodId() {
    for (var i = 0; i < moods.length; i++) if (moods[i].current) return moods[i].id
    return moods.length > 0 ? moods[0].id : ""
  }

  // Called as the popup opens: sections closed, focus on the current mood.
  function reset() {
    editing = false
    manualOpen = false
    settingsOpen = false
    if (widget && widget.customHighlight) customColor = widget.highlightSetting.toLowerCase()
    focusId = currentMoodId()
  }

  function clean(text) { return String(text).replace(/[<>\u0000-\u001f]/g, "").slice(0, 32) }

  // A section that closes under the focus hands it to its own header (or back
  // to the current mood when the first-open guide is dismissed).
  onOrderChanged: if (focusId !== "" && order.indexOf(focusId) === -1) {
    if (focusId === "set:highlight:pick" && order.indexOf("set:highlight") !== -1) focusId = "set:highlight"
    else if (focusId === "guide:dismiss") focusId = currentMoodId()
    else focusId = focusId.indexOf("set:") === 0 ? "settings" : "manual"
  }
}
