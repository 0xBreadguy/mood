import QtQuick
import qs.Commons

// Tine — a wordless 13-tine acoustic comb for mood on the Omarchy bar.
//
// Each catalog mood is a physical tine on a quarter-marked vernier rail
// (landmarks at 0, 4, 8, 12 for 13 moods). Playback state reshapes the comb
// itself so all six states read without motion or colour:
//
//   stopped   flat comb with a single slender resting needle at the mood
//   loading   detached floating beads in a sine arc above a quiet rail
//   playing   solid unbroken multi-tine acoustic crest centred on the mood
//   paused    cleaved suspended aperture (4 px hollow centre cut) at the mood
//   offline   comb parted around a central chasm with a single diagonal break
//   failed    flattened rail with crossed fault blades
//
// Three animation variants:
//   resonance (default)  EMA-smoothed level/low/mid/high quantized at ~7 Hz
//   impulse              poised stillness; strikes and ripples on onsets only
//   steady               static playing crest; stops audio measurement
//
// With the music, the whole comb moves: what the crest does travels out along
// the tines beyond it, one tine a tick and lower with distance, so the item
// is alive across its width wherever the mood stands. Steady, reduced motion
// and a track that can't be measured keep the comb beyond the crest at rest.
//
// When the mood changes, its tine opens into its name and closes back onto
// the tine. The resting width never changes; only a name longer than the comb
// borrows room, for its moment — an in-place reveal centred on the active
// tine rather than sliding out to the side.
Item {
  id: surface

  required property var mood
  // The name's window never draws past the item while its room closes.
  clip: true

  readonly property var variants: [
    { id: "resonance", name: "Resonance" },
    { id: "impulse",   name: "Impulse" },
    { id: "steady",    name: "Steady" }
  ]
  readonly property bool usesFeatures: mood.variant !== "steady"

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

  readonly property color ink: mood.foreground
  readonly property color bg: mood.background
  readonly property bool highlightLowContrast: contrastRatio(mood.highlight, bg) < 2.8
  readonly property color accent: ensureContrast(mood.highlight, ink, bg, 3.1)
  readonly property color faultColor: ensureContrast(mood.urgent, ink, bg, 3.2)
  readonly property color shoulderNear: mixColor(ink, accent, 0.62)
  readonly property color shoulderFar: mixColor(ink, accent, 0.28)

  // ---- comb geometry -------------------------------------------------------

  readonly property int moodCount: mood.moods ? mood.moods.length : 0
  readonly property int tineCount: moodCount === 0 ? 13 : (moodCount <= 17 ? moodCount : 15)
  readonly property int activeIndex: {
    if (moodCount <= 1) return 0
    if (moodCount <= 17) return Math.max(0, Math.min(tineCount - 1, mood.moodIndex))
    return Math.round(mood.moodIndex * (tineCount - 1) / (moodCount - 1))
  }
  readonly property int landmarkStep: tineCount >= 9 ? Math.max(3, Math.round((tineCount - 1) / 3)) : 0
  function isLandmark(i) {
    if (i === 0 || i === tineCount - 1) return true
    if (landmarkStep <= 0) return false
    return (i % landmarkStep === 0) && ((tineCount - 1 - i) >= 2)
  }

  readonly property int pitch: Math.max(3, Style.space(tineCount <= 13 ? 4 : 3))
  readonly property int thin: Math.max(1, Math.round(Style.spaceReal(1)))
  readonly property int thick: Math.max(2, Math.round(Style.spaceReal(2)))
  readonly property int combSpan: (tineCount - 1) * pitch + thin
  readonly property int sidePad: Style.space(8)
  readonly property int combBox: combSpan + sidePad * 2
  // Even vertical aperture centred cleanly inside the 26 px bar.
  readonly property int maxH: Math.max(10, Math.min(16, Math.floor((mood.barSize * 0.56) / 2) * 2))

  // ---- the name moment -----------------------------------------------------

  // Positions here are in the resting frame: 0 .. combBox, the comb at rest.
  readonly property string edge: mood.fixedEdge === "start" ? "start" : (mood.fixedEdge === "center" ? "center" : "end")
  // The centre of tine i.
  function tineX(i) { return sidePad + i * pitch + thin / 2 }

  readonly property bool naming: mood.nameShowing && !mood.vertical && mood.nameText !== ""
  // Kept after the moment ends, so the name is still there while it closes.
  property string shownName: ""
  onNamingChanged: {
    if (naming) {
      shownName = mood.nameText
      placeLabel(false)
      Qt.callLater(placeLabel, false)
      slide = Math.max(-1, Math.min(1, mood.nameDirection)) * (I18n.rightToLeft ? 3 : -3)
      slideIn.restart()
    }
  }
  Connections {
    target: surface.mood
    function onNameTextChanged() {
      if (!surface.naming) return
      surface.shownName = surface.mood.nameText
      Qt.callLater(surface.placeLabel, true)
    }
  }

  TextMetrics {
    id: nameMetrics
    font.family: surface.mood.fontFamily
    font.pixelSize: surface.mood.fontSize
    text: surface.shownName
  }

  // Where the name sits: centred on its own tine, kept off the bar's fixed
  // edge, spilling only toward the free side.
  property real labelLeft: 0
  property real labelWidth: 0
  property int lastIndex: 0
  readonly property int inset: 2
  function wantedLeft(w) {
    if (edge === "center") return Math.round((combBox - w) / 2)
    var lo = inset, hi = combBox - inset - w
    // A name that fits over the comb stays over it, as near its tine as it
    // can: no room is borrowed. A longer one holds the fixed edge and spills
    // toward the free side.
    if (hi >= lo) return Math.max(lo, Math.min(hi, Math.round(tineX(activeIndex) - w / 2)))
    return edge === "end" ? hi : lo
  }
  function placeLabel(glide) {
    var w = Math.ceil(nameMetrics.advanceWidth)
    var l = wantedLeft(w)
    // A step to the next tine glides; a wrap around the comb jumps.
    nameGlider.stop()
    if (glide && Math.abs(activeIndex - lastIndex) === 1 && !mood.reducedMotion) {
      glideLeft.to = l; glideWidth.to = w
      nameGlider.start()
    } else {
      labelLeft = l; labelWidth = w
    }
    lastIndex = activeIndex
  }
  onActiveIndexChanged: if (!naming) lastIndex = activeIndex
  ParallelAnimation {
    id: nameGlider
    NumberAnimation { id: glideLeft; target: surface; property: "labelLeft"; duration: 120; easing.type: Easing.OutCubic }
    NumberAnimation { id: glideWidth; target: surface; property: "labelWidth"; duration: 120; easing.type: Easing.OutCubic }
  }

  // Room borrowed beyond the resting width, only for a name that needs it.
  readonly property real overflow: {
    if (!naming) return 0
    if (edge === "end") return Math.max(0, inset - labelLeft)
    if (edge === "start") return Math.max(0, labelLeft + labelWidth - (combBox - inset))
    return Math.max(0, labelWidth + 2 * inset - combBox)
  }
  property real extra: overflow
  Behavior on extra {
    NumberAnimation {
      duration: Style.duration(surface.naming ? 180 : 120)
      easing.type: Easing.Bezier
      easing.bezierCurve: Style.easeOut
    }
  }
  // From the resting frame to the item: the comb stays put against the fixed
  // edge while the item grows away from it.
  readonly property real offset: edge === "end" ? extra : (edge === "center" ? extra / 2 : 0)

  // 0 closed on the tine, 1 open to the whole name.
  property real open: naming ? 1 : 0
  Behavior on open {
    NumberAnimation {
      duration: Style.duration(surface.naming ? 180 : 140)
      easing.type: Easing.Bezier
      easing.bezierCurve: Style.easeOut
    }
  }
  // The name arrives from the side the mood came from.
  property real slide: 0
  NumberAnimation { id: slideIn; target: surface; property: "slide"; to: 0; duration: Style.duration(180); easing.type: Easing.OutCubic }

  // The window the name is seen through. Whatever of the comb it passes over
  // steps aside, with a little air around the letters.
  readonly property real windowLeft: tineX(activeIndex) + (labelLeft - tineX(activeIndex)) * open
  readonly property real windowRight: tineX(activeIndex) + (labelLeft + labelWidth - tineX(activeIndex)) * open
  function coveredAt(x) { return open > 0 && x >= windowLeft - 4 && x <= windowRight + 4 }
  function coveredBetween(a, b) { return open > 0 && b >= windowLeft - 4 && a <= windowRight + 4 }

  // The mood's own tine relights once the name has closed.
  property real lit: open <= 0.02 ? 1 : 0
  Behavior on lit {
    NumberAnimation { duration: Style.duration(surface.lit < 0.5 ? 140 : 60); easing.type: Easing.OutCubic }
  }

  implicitWidth: mood.vertical ? mood.barSize : combBox + Math.round(extra)
  implicitHeight: mood.vertical ? combBox : mood.barSize

  // ---- live audio state (strictly gated; zero ticking at rest) -------------

  readonly property bool featuresReady: !mood.reducedMotion && mood.state === "playing"
    && !!mood.features && mood.features.available && surface.visible
  readonly property bool liveResonance: mood.variant === "resonance" && featuresReady
  readonly property bool liveImpulse: mood.variant === "impulse" && featuresReady

  // Smoothed continuous envelopes (internal only, never bound to geometry).
  property real sLevel: 0.45
  property real sLow: 0.35
  property real sMid: 0.35
  property real sHigh: 0.25

  // Quantized even-pixel heights (only written when an integer actually changes,
  // avoiding redundant Wayland surface commits).
  property int q0: 12
  property int q1L: 8
  property int q1R: 8
  property int q2: 6
  property int q3: 4

  // The comb beyond the crest. far[k] is the height of an ordinary tine 4 + k
  // away from the mood; empty while the comb is at rest. Only as many as the
  // longer side needs, so a mood mid-comb costs less than one at an end.
  readonly property int farCount: Math.max(0, Math.max(activeIndex, tineCount - 1 - activeIndex) - 3)
  property var far: []
  function farAt(k) { return k < far.length ? far[k] : 2 }
  function farTop(k) { return k < 4 ? 6 : 4 }
  function setFar(next) { if (next.join() !== far.join()) far = next }
  // Resonance: the beat against its own recent average, newest first.
  property var wake: []
  property real sPulse: 0.3
  property real sMean: 0.3
  // Impulse: strikes still travelling, newest first, 0 where there is none.
  property var ring: []
  function carries(strength, k) { return strength > 0 && (k < 4 || strength >= 0.55) }

  function quantizeEven(lo, hi, v) {
    var steps = Math.max(1, Math.round((hi - lo) / 2))
    var q = lo + Math.round(Math.max(0, Math.min(1, v)) * steps) * 2
    return Math.max(lo, Math.min(hi, q))
  }

  function resetCalmHeights() {
    sLevel = 0.45; sLow = 0.35; sMid = 0.35; sHigh = 0.25
    if (q0 !== 12) q0 = 12
    if (q1L !== 8) q1L = 8
    if (q1R !== 8) q1R = 8
    if (q2 !== 6) q2 = 6
    if (q3 !== 4) q3 = 4
    sPulse = 0.3; sMean = 0.3
    wake = []
    if (far.length) far = []
  }

  onLiveResonanceChanged: if (!liveResonance) resetCalmHeights()

  Timer {
    id: resonanceTimer
    interval: 140
    repeat: true
    running: surface.liveResonance
    onTriggered: {
      var f = surface.mood.features
      if (!f || !f.available) return
      surface.sLevel += (f.level - surface.sLevel) * (f.level > surface.sLevel ? 0.40 : 0.22)
      surface.sLow   += (f.low   - surface.sLow)   * (f.low   > surface.sLow   ? 0.36 : 0.20)
      surface.sMid   += (f.mid   - surface.sMid)   * (f.mid   > surface.sMid   ? 0.38 : 0.22)
      surface.sHigh  += (f.high  - surface.sHigh)  * (f.high  > surface.sHigh  ? 0.44 : 0.25)

      var n0  = surface.quantizeEven(8, surface.maxH, surface.sLevel)
      var n1L = surface.quantizeEven(6, surface.maxH - 2, surface.sLow)
      var n1R = surface.quantizeEven(6, surface.maxH - 2, surface.sMid)
      var n2  = surface.quantizeEven(4, Math.max(6, surface.maxH - 4), surface.sHigh)
      var n3  = (surface.sHigh > 0.52 || surface.sLevel > 0.68) ? 6 : 4

      if (surface.q0  !== n0)  surface.q0  = n0
      if (surface.q1L !== n1L) surface.q1L = n1L
      if (surface.q1R !== n1R) surface.q1R = n1R
      if (surface.q2  !== n2)  surface.q2  = n2
      if (surface.q3  !== n3)  surface.q3  = n3

      // The beat, measured against its own recent average so it stands out,
      // reaches each tine beyond the crest a tick after the one before it.
      var x = Math.max(f.low, f.level)
      surface.sPulse += (x - surface.sPulse) * (x > surface.sPulse ? 0.70 : 0.34)
      surface.sMean += (surface.sPulse - surface.sMean) * 0.08
      var w = surface.wake.slice(0, surface.farCount)
      w.unshift(0.5 + (surface.sPulse - surface.sMean) * 3.2)
      surface.wake = w
      var nf = []
      for (var k = 0; k < surface.farCount; k++)
        nf.push(k + 1 < w.length ? surface.quantizeEven(2, surface.farTop(k), w[k + 1]) : 2)
      surface.setFar(nf)
    }
  }

  // Impulse variant: stays completely idle until an onset fires, then runs a
  // 4-step outward sympathetic ripple through the crest, carries the strike
  // on along the comb, and stops its timer again once it has run out.
  property int pluckPhase: 0
  property real pluckStrength: 0
  property double lastPluckMs: 0

  onLiveImpulseChanged: if (!liveImpulse) {
    pluckPhase = 0; pluckStrength = 0
    ring = []
    if (far.length) far = []
  }

  Connections {
    target: surface.mood.features
    function onOnsetCountChanged() {
      if (!surface.liveImpulse) return
      var f = surface.mood.features
      if (!f || f.onset < 0.20) return
      var now = Date.now()
      if (now - surface.lastPluckMs < 160) return
      surface.lastPluckMs = now
      surface.pluckStrength = Math.max(0.2, Math.min(1, f.onset))
      surface.pluckPhase = 4
      var r = surface.ring.slice()
      r[0] = surface.pluckStrength
      surface.ring = r
      pluckTimer.restart()
    }
  }

  Timer {
    id: pluckTimer
    interval: 95
    repeat: true
    running: (surface.pluckPhase > 0 || surface.ring.length > 0) && surface.liveImpulse
    onTriggered: {
      if (surface.pluckPhase > 1) surface.pluckPhase -= 1
      else surface.pluckPhase = 0

      // Every strike moves one tine further out and lifts two tines as it
      // passes. A strong one crosses the comb; a weak one dies out four
      // tines beyond the crest.
      var r = surface.ring.slice(0, surface.farCount + 2)
      r.unshift(0)
      var live = false
      for (var j = 0; j < r.length; j++) {
        if (r[j] > 0 && r[j] < 0.55 && j > 6) r[j] = 0
        if (r[j] > 0) live = true
      }
      var nf = []
      for (var k = 0; k < surface.farCount; k++)
        nf.push((surface.carries(r[k + 2], k) || surface.carries(r[k + 3], k)) ? 4 : 2)
      surface.ring = live ? r : []
      surface.setFar(live ? nf : [])
    }
  }

  function playingHeight(i) {
    var d = Math.abs(i - activeIndex)
    if (d > 3) {
      var rest = isLandmark(i) ? 4 : 2
      if (liveResonance) return Math.max(rest, farAt(d - 4))
      if (liveImpulse) return farAt(d - 4) > 2 ? rest + 2 : rest
      return rest
    }

    if (liveResonance) {
      if (d === 0) return q0
      if (d === 1) {
        if (activeIndex === 0 || activeIndex === tineCount - 1) return Math.max(q1L, q1R)
        return i < activeIndex ? q1L : q1R
      }
      if (d === 2) return q2
      // Never a notch between the crest and the comb beyond it.
      return Math.max(q3, farAt(0))
    }

    if (liveImpulse) {
      var strong = pluckStrength >= 0.55
      if (pluckPhase === 4) {
        if (d === 0) return strong ? maxH : Math.max(12, maxH - 2)
        if (d === 1) return strong ? 10 : 8
        if (d === 2) return 4
        return 2
      }
      if (pluckPhase === 3) {
        if (d === 0) return 12
        if (d === 1) return strong ? 12 : 10
        if (d === 2) return strong ? 8 : 6
        return 4
      }
      if (pluckPhase === 2) {
        if (d === 0) return 10
        if (d === 1) return 8
        if (d === 2) return 6
        return 4
      }
      if (pluckPhase === 1) {
        if (d === 0) return 10
        if (d === 1) return 6
        if (d === 2) return 4
        return 2
      }
      // Poised stillness between onsets: still clearly solid playing crest.
      if (d === 0) return 10
      if (d === 1) return 6
      if (d === 2) return 4
      return 2
    }

    // Calm / Steady / reducedMotion / features unavailable: sculpted playing crest.
    if (d === 0) return Math.min(12, maxH)
    if (d === 1) return 8
    if (d === 2) return 6
    return 4
  }

  // ---- loading wave timer (only runs while state === "loading") ------------

  property int loadingStep: 0
  Timer {
    id: loadingTimer
    interval: 170
    repeat: true
    running: surface.mood.state === "loading" && !surface.mood.reducedMotion && surface.visible
    onTriggered: surface.loadingStep = (surface.loadingStep + 1) % 7
  }

  // ---- skip / back sweep & refusal stop-wall -------------------------------

  property real sweepPos: -1
  property int sweepDir: 1
  property int stillEdgeDir: 0
  property bool refusing: false
  property int refuseDir: -1

  NumberAnimation {
    id: sweepAnim
    target: surface
    property: "sweepPos"
    duration: Style.duration(240)
    easing.type: Easing.Bezier
    easing.bezierCurve: Style.easeOut
    onFinished: surface.sweepPos = -1
  }

  Timer { id: stillEdgeTimer; interval: 380; onTriggered: surface.stillEdgeDir = 0 }
  Timer { id: refusalTimer; interval: 460; onTriggered: surface.refusing = false }

  property real recoil: 0
  SequentialAnimation {
    id: recoilAnim
    property real push: -3
    NumberAnimation { target: surface; property: "recoil"; to: recoilAnim.push; duration: Style.duration(55); easing.type: Easing.OutCubic }
    NumberAnimation { target: surface; property: "recoil"; to: -recoilAnim.push * 0.35; duration: Style.duration(70); easing.type: Easing.OutCubic }
    NumberAnimation { target: surface; property: "recoil"; to: 0; duration: Style.duration(65); easing.type: Easing.OutCubic }
  }

  Connections {
    target: surface.mood
    function onSkipped(direction) {
      var eff = (direction >= 0 ? 1 : -1) * (I18n.rightToLeft ? -1 : 1)
      if (surface.mood.reducedMotion) {
        surface.stillEdgeDir = eff
        stillEdgeTimer.restart()
        return
      }
      surface.sweepDir = eff
      sweepAnim.stop()
      sweepAnim.from = eff > 0 ? 0 : 1
      sweepAnim.to   = eff > 0 ? 1 : 0
      sweepAnim.start()
    }
    function onRefused(what) {
      var raw = what === "skip" ? 1 : -1
      var eff = raw * (I18n.rightToLeft ? -1 : 1)
      surface.refuseDir = eff
      surface.refusing = true
      refusalTimer.restart()
      if (!surface.mood.reducedMotion) {
        recoilAnim.push = eff * 3
        recoilAnim.restart()
      }
    }
  }

  // ---- subtle hover / press plate ------------------------------------------

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: surface.mood.vertical ? 0 : 2
    anchors.bottomMargin: surface.mood.vertical ? 0 : 2
    anchors.leftMargin: surface.mood.vertical ? 2 : 0
    anchors.rightMargin: surface.mood.vertical ? 2 : 0
    radius: Style.cornerRadius
    color: surface.mood.pressed ? Style.pressedFill : (surface.mood.hovered ? Style.hoverFill : "transparent")
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
  }

  // ---- the tine comb -------------------------------------------------------

  Item {
    id: combFrame
    x: surface.mood.vertical ? 0 : Math.round(surface.offset)
    y: 0
    width: surface.mood.vertical ? surface.width : surface.combBox
    height: surface.mood.vertical ? surface.combBox : surface.height

    scale: surface.mood.pressed ? 0.96 : 1.0
    Behavior on scale {
      NumberAnimation { duration: Style.duration(140); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    Item {
      id: comb
      x: surface.mood.vertical
        ? Math.round((parent.width - surface.maxH) / 2)
        : Math.round((parent.width - surface.combSpan) / 2 + surface.recoil)
      y: surface.mood.vertical
        ? Math.round((parent.height - surface.combSpan) / 2 + surface.recoil)
        : Math.round((parent.height - surface.maxH) / 2)
      width: surface.mood.vertical ? surface.maxH : surface.combSpan
      height: surface.mood.vertical ? surface.combSpan : surface.maxH

      readonly property int midCross: Math.floor(surface.maxH / 2)
      readonly property string st: surface.mood.state
      readonly property bool splitCenter: st === "offline" || st === "failed"
      // The slash and the cross sit in the middle of the comb, about 20 px wide.
      readonly property bool glyphCovered: surface.coveredBetween(surface.combBox / 2 - 10, surface.combBox / 2 + 10)

      // -- 1. Tines for stopped, playing, offline, failed --------------------
      Repeater {
        model: surface.tineCount
        Item {
          id: tineSlot
          required property int index
          readonly property int dist: Math.abs(index - surface.activeIndex)
          readonly property bool isActive: dist === 0
          readonly property bool landmark: surface.isLandmark(index)
          readonly property int pos: index * surface.pitch
          readonly property bool inChasm: comb.splitCenter && index > 3 && index < surface.tineCount - 4
          // Under the name while it is open; the mood's own tine relights after.
          visible: !surface.coveredAt(surface.tineX(index))
          opacity: isActive ? surface.lit : 1

          // Stopped & Playing & Offline/Failed outer rail (unbroken bars)
          Rectangle {
            visible: comb.st !== "paused" && comb.st !== "loading" && !tineSlot.inChasm
            readonly property int barLen: {
              if (comb.st === "playing") return surface.playingHeight(tineSlot.index)
              if (comb.st === "stopped") return tineSlot.isActive ? 8 : (tineSlot.landmark ? 4 : 2)
              return tineSlot.landmark ? 4 : 2
            }
            readonly property int barThick: (comb.st === "playing" && tineSlot.isActive) ? surface.thick : surface.thin
            readonly property int shift: barThick > surface.thin ? -Math.floor((barThick - surface.thin) / 2) : 0

            x: surface.mood.vertical ? (comb.midCross - Math.floor(barLen / 2)) : (tineSlot.pos + shift)
            y: surface.mood.vertical ? (tineSlot.pos + shift) : (comb.midCross - Math.floor(barLen / 2))
            width: surface.mood.vertical ? barLen : barThick
            height: surface.mood.vertical ? barThick : barLen
            color: {
              if (comb.st === "playing") {
                if (tineSlot.dist === 0) return surface.accent
                if (tineSlot.dist === 1) return surface.shoulderNear
                if (tineSlot.dist === 2) return surface.shoulderFar
              }
              return surface.ink
            }
            opacity: {
              if (comb.st === "playing") {
                if (tineSlot.dist === 0) return 1.0
                if (tineSlot.dist === 1) return 0.92
                if (tineSlot.dist === 2) return 0.72
                if (tineSlot.dist === 3) return 0.48
                // Beyond the crest: lit enough to read while it moves.
                if (surface.liveResonance)
                  return tineSlot.dist <= 5 ? 0.44 : (tineSlot.dist <= 8 ? 0.38 : (tineSlot.landmark ? 0.42 : 0.32))
                if (surface.liveImpulse && surface.farAt(tineSlot.dist - 4) > 2) return 0.44
                return tineSlot.landmark ? 0.42 : 0.26
              }
              if (comb.st === "stopped") return tineSlot.isActive ? 0.88 : (tineSlot.landmark ? 0.48 : 0.30)
              return tineSlot.landmark ? 0.42 : 0.28
            }
          }

          // Paused: flat comb elsewhere, cleaved hollow aperture at d <= 1
          Rectangle {
            visible: comb.st === "paused" && tineSlot.dist > 1
            readonly property int barLen: tineSlot.landmark ? 4 : 2
            x: surface.mood.vertical ? (comb.midCross - Math.floor(barLen / 2)) : tineSlot.pos
            y: surface.mood.vertical ? tineSlot.pos : (comb.midCross - Math.floor(barLen / 2))
            width: surface.mood.vertical ? barLen : surface.thin
            height: surface.mood.vertical ? surface.thin : barLen
            color: surface.ink
            opacity: tineSlot.landmark ? 0.46 : 0.28
          }
          // Paused upper/leading cap (cleaved by a 4 px empty silent band)
          Rectangle {
            visible: comb.st === "paused" && tineSlot.dist <= 1
            readonly property int capLen: tineSlot.isActive ? 4 : 2
            readonly property int gapHalf: tineSlot.isActive ? 2 : 3
            readonly property int barThick: tineSlot.isActive ? surface.thick : surface.thin
            readonly property int shift: barThick > surface.thin ? -Math.floor((barThick - surface.thin) / 2) : 0
            x: surface.mood.vertical ? (comb.midCross - gapHalf - capLen) : (tineSlot.pos + shift)
            y: surface.mood.vertical ? (tineSlot.pos + shift) : (comb.midCross - gapHalf - capLen)
            width: surface.mood.vertical ? capLen : barThick
            height: surface.mood.vertical ? barThick : capLen
            color: tineSlot.isActive ? surface.accent : surface.ink
            opacity: tineSlot.isActive ? 1.0 : 0.65
          }
          // Paused lower/trailing cap
          Rectangle {
            visible: comb.st === "paused" && tineSlot.dist <= 1
            readonly property int capLen: tineSlot.isActive ? 4 : 2
            readonly property int gapHalf: tineSlot.isActive ? 2 : 3
            readonly property int barThick: tineSlot.isActive ? surface.thick : surface.thin
            readonly property int shift: barThick > surface.thin ? -Math.floor((barThick - surface.thin) / 2) : 0
            x: surface.mood.vertical ? (comb.midCross + gapHalf) : (tineSlot.pos + shift)
            y: surface.mood.vertical ? (tineSlot.pos + shift) : (comb.midCross + gapHalf)
            width: surface.mood.vertical ? capLen : barThick
            height: surface.mood.vertical ? barThick : capLen
            color: tineSlot.isActive ? surface.accent : surface.ink
            opacity: tineSlot.isActive ? 1.0 : 0.65
          }

          // Loading: quiet baseline ticks + mood anchor tick at bottom edge
          Rectangle {
            visible: comb.st === "loading"
            readonly property int barLen: tineSlot.isActive ? 3 : 2
            x: surface.mood.vertical ? (surface.maxH - barLen) : tineSlot.pos
            y: surface.mood.vertical ? tineSlot.pos : (surface.maxH - barLen)
            width: surface.mood.vertical ? barLen : (tineSlot.isActive ? surface.thick : surface.thin)
            height: surface.mood.vertical ? (tineSlot.isActive ? surface.thick : surface.thin) : barLen
            color: tineSlot.isActive ? surface.accent : surface.ink
            opacity: tineSlot.isActive ? 0.95 : (tineSlot.landmark ? 0.36 : 0.20)
          }
        }
      }

      // -- 2. Loading: 7 detached floating beads in a travelling cosine arc --
      Repeater {
        model: comb.st === "loading" ? 7 : 0
        Rectangle {
          required property int index
          readonly property int slotIdx: Math.min(surface.tineCount - 1, Math.round(index * (surface.tineCount - 1) / 6))
          readonly property int peakIdx: surface.mood.reducedMotion ? 3 : surface.loadingStep
          readonly property real wave: Math.cos(((index - peakIdx) * Math.PI) / 3.5)
          readonly property int cross: Math.max(0, Math.min(surface.maxH - 6, Math.round(3.5 - wave * 3.0)))
          readonly property bool isCrest: index === peakIdx

          // The beads wait for a skip or back sweep to pass, so the blade
          // crosses a quiet rail and never cuts through them.
          visible: surface.sweepPos < 0 && !surface.coveredAt(surface.tineX(slotIdx))
          x: surface.mood.vertical ? cross : (slotIdx * surface.pitch)
          y: surface.mood.vertical ? (slotIdx * surface.pitch) : cross
          width: 2
          height: 2
          color: isCrest ? surface.accent : surface.ink
          opacity: isCrest ? 1.0 : Math.max(0.38, 0.52 + wave * 0.25)
        }
      }

      // -- 3. Offline: severed bridge stubs + single diagonal shear (— / —) --
      Item {
        visible: comb.st === "offline" && !comb.glyphCovered
        anchors.fill: parent
        // Left severed hairline stub
        Rectangle {
          x: surface.mood.vertical ? comb.midCross : Math.round(parent.width / 2 - 9)
          y: surface.mood.vertical ? Math.round(parent.height / 2 - 9) : comb.midCross
          width: surface.mood.vertical ? 1 : 4
          height: surface.mood.vertical ? 4 : 1
          color: surface.ink
          opacity: 0.72
        }
        // Right severed hairline stub
        Rectangle {
          x: surface.mood.vertical ? comb.midCross : Math.round(parent.width / 2 + 5)
          y: surface.mood.vertical ? Math.round(parent.height / 2 + 5) : comb.midCross
          width: surface.mood.vertical ? 1 : 4
          height: surface.mood.vertical ? 4 : 1
          color: surface.ink
          opacity: 0.72
        }
        // Single clean diagonal shear stroke
        Rectangle {
          width: 1.4
          height: surface.maxH - 3
          anchors.centerIn: parent
          rotation: 26
          antialiasing: true
          color: surface.ink
          opacity: 0.92
        }
      }

      // -- 4. Failed: sharp crossed fault blades (✕) -------------------------
      Item {
        visible: comb.st === "failed" && !comb.glyphCovered
        anchors.fill: parent
        Repeater {
          model: [45, -45]
          Rectangle {
            required property int modelData
            width: 1.4
            height: surface.maxH - 3
            anchors.centerIn: parent
            rotation: modelData
            antialiasing: true
            color: surface.faultColor
          }
        }
      }

      // Mood position anchor tick tucked cleanly below the comb span on
      // offline & failed so it never touches the slash or fault cross.
      Rectangle {
        visible: comb.splitCenter && !surface.coveredAt(surface.tineX(surface.activeIndex))
        readonly property int pos: surface.activeIndex * surface.pitch
        x: surface.mood.vertical ? (surface.maxH + 1) : pos
        y: surface.mood.vertical ? pos : (surface.maxH + 1)
        width: surface.mood.vertical ? 2 : 2
        height: 2
        color: surface.accent
        opacity: 0.92
      }

      // -- 5. Skip / Back directional sweep blade (animated) -----------------
      Item {
        visible: surface.sweepPos >= 0 && !surface.coveredAt(surface.sidePad + lead + 1)
        anchors.fill: parent
        readonly property int lead: Math.round(surface.sweepPos * (surface.combSpan - 2))
        readonly property int wakeLen: surface.sweepDir > 0
          ? Math.max(0, Math.min(7, lead))
          : Math.max(0, Math.min(7, surface.combSpan - (lead + 2)))
        // Translucent directional wake strictly trailing behind the blade
        Rectangle {
          visible: parent.wakeLen > 0
          x: surface.mood.vertical ? 2 : (surface.sweepDir > 0 ? (parent.lead - parent.wakeLen) : (parent.lead + 2))
          y: surface.mood.vertical ? (surface.sweepDir > 0 ? (parent.lead - parent.wakeLen) : (parent.lead + 2)) : 2
          width: surface.mood.vertical ? (surface.maxH - 4) : parent.wakeLen
          height: surface.mood.vertical ? parent.wakeLen : (surface.maxH - 4)
          color: surface.accent
          opacity: 0.28
        }
        // Crisp 2 px sweep blade
        Rectangle {
          x: surface.mood.vertical ? 0 : parent.lead
          y: surface.mood.vertical ? parent.lead : 0
          width: surface.mood.vertical ? surface.maxH : 2
          height: surface.mood.vertical ? 2 : surface.maxH
          color: surface.accent
          opacity: 0.95
        }
      }

      // Skip / Back static destination post (under reducedMotion)
      Rectangle {
        visible: surface.stillEdgeDir !== 0
          && !surface.coveredAt(surface.sidePad + (surface.stillEdgeDir > 0 ? surface.combSpan + 3 : -3))
        x: surface.mood.vertical ? 0 : (surface.stillEdgeDir > 0 ? surface.combSpan + 2 : -4)
        y: surface.mood.vertical ? (surface.stillEdgeDir > 0 ? surface.combSpan + 2 : -4) : 0
        width: surface.mood.vertical ? surface.maxH : 2
        height: surface.mood.vertical ? 2 : surface.maxH
        color: surface.accent
      }

      // -- 6. Refusal hard stop-wall (visible with or without motion) --------
      Item {
        visible: surface.refusing && !surface.coveredAt(surface.sidePad + wallPos + 1)
        readonly property int wallPos: surface.refuseDir < 0 ? -4 : surface.combSpan + 2
        // The wall stands still while the comb recoils against it.
        readonly property int held: wallPos - Math.round(surface.recoil)
        x: surface.mood.vertical ? 0 : held
        y: surface.mood.vertical ? held : 0
        width: surface.mood.vertical ? surface.maxH : 2
        height: surface.mood.vertical ? 2 : surface.maxH

        Rectangle {
          anchors.fill: parent
          color: surface.faultColor
        }
        // End-cap pins in foreground ink so refusal reads without colour
        Rectangle {
          width: 2; height: 2
          x: 0; y: 0
          color: surface.ink
        }
        Rectangle {
          width: 2; height: 2
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          color: surface.ink
        }
      }
    }

    // The name, seen through a window that opens out of the mood's tine.
    Item {
      visible: surface.open > 0
      x: Math.round(surface.windowLeft)
      width: Math.max(0, Math.round(surface.windowRight) - Math.round(surface.windowLeft))
      height: parent.height
      clip: true
      Text {
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        text: surface.shownName
        x: Math.round(surface.labelLeft) - parent.x + Math.round(surface.slide)
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        color: surface.ink
        opacity: Math.min(1, surface.open * 1.6)
        font.family: surface.mood.fontFamily
        font.pixelSize: surface.mood.fontSize
      }
    }
  }
}
