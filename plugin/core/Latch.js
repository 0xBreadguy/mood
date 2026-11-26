.pragma library

// The gesture latch: one swipe, one step, on one axis.
//
// Wheel deltas add up per axis until one reaches `threshold`. That axis fires a
// single step and owns the gesture until the wheel has been quiet for `quiet`
// milliseconds, so a long swipe and whatever trails it give one step, and a
// slanted swipe cannot skip a track and change the mood together. A deliberate
// swipe the other way (`reverse`) inside the latch fires the opposite step at
// once, so scrolling back undoes a skip without waiting. Two wheel notches more
// than `quiet` apart are two steps.
//
// Deltas are in pixels of finger travel. A mouse wheel notch is passed as one
// threshold's worth (see units()). A trackpad says when the fingers lift, and
// that ends the gesture at once (end()); a mouse wheel never says, so there
// the quiet gap does it. The defaults were tuned in a browser prototype and
// are exposed as options so they can be tuned again on a real trackpad.
//
//   wheel(dx, dy, t)  ->  null, or { axis: "x" | "y", dir: +1 | -1 }
//
// dir is +1 for a scroll down or to the right, the "forward" directions.

var DEFAULTS = { threshold: 50, quiet: 240, reverse: 90 }

function create(options) {
  var o = options || {}
  var latch = {
    threshold: o.threshold > 0 ? o.threshold : DEFAULTS.threshold,
    quiet: o.quiet > 0 ? o.quiet : DEFAULTS.quiet,
    reverse: o.reverse > 0 ? o.reverse : DEFAULTS.reverse,
    owner: "", sign: 0, accX: 0, accY: 0, against: 0, last: -1e12
  }

  latch.reset = function() {
    latch.owner = ""; latch.sign = 0; latch.accX = 0; latch.accY = 0; latch.against = 0
  }

  // The fingers left the trackpad: the gesture is over, and the next swipe is
  // a new one however soon it comes.
  latch.end = function() { latch.reset(); latch.last = -1e12 }

  // True while a gesture owns the wheel at time t.
  latch.held = function(t) { return latch.owner !== "" && t - latch.last <= latch.quiet }

  latch.wheel = function(dx, dy, t) {
    dx = Number(dx) || 0
    dy = Number(dy) || 0
    if (t - latch.last > latch.quiet) latch.reset()
    latch.last = t

    if (latch.owner === "") {
      latch.accX += dx
      latch.accY += dy
      var ax = Math.abs(latch.accX), ay = Math.abs(latch.accY)
      if (ax < latch.threshold && ay < latch.threshold) return null
      latch.owner = ax > ay ? "x" : "y"
      // A negative wheel delta is a scroll down or to the right: forward.
      latch.sign = (latch.owner === "x" ? latch.accX : latch.accY) < 0 ? 1 : -1
      latch.against = 0
      return { axis: latch.owner, dir: latch.sign }
    }

    // Owned: the other axis is ignored until the wheel goes quiet.
    var d = latch.owner === "x" ? dx : dy
    if (d === 0) return null
    var forward = d < 0 ? 1 : -1
    if (forward === latch.sign) {
      latch.against = 0
      return null
    }
    latch.against += Math.abs(d)
    if (latch.against < latch.reverse) return null
    latch.sign = forward
    latch.against = 0
    return { axis: latch.owner, dir: latch.sign }
  }

  return latch
}

// Wheel deltas as the latch wants them, from what Qt reports on Wayland
// (measured in Quickshell on 2026-11-21):
//
//   a mouse wheel   no scroll phase (0); 120 angle units to the notch. A notch
//                   is one deliberate step, so it is one threshold's worth.
//   a trackpad      phases 2 (moving) and 3 (fingers lifted); 8 angle units to
//                   the pixel of finger travel, finer than the rounded pixels.
//
// `sideways` turns a vertical scroll into a horizontal one, for mice with one
// wheel: Shift where the platform reports it, or the right button held.
function units(pixelX, pixelY, angleX, angleY, phase, sideways, threshold) {
  var t = threshold > 0 ? threshold : DEFAULTS.threshold
  var x = 0, y = 0
  if (!phase) {
    x = (Number(angleX) || 0) / 120 * t
    y = (Number(angleY) || 0) / 120 * t
  } else if (angleX || angleY) {
    x = (Number(angleX) || 0) / 8
    y = (Number(angleY) || 0) / 8
  } else {
    x = Number(pixelX) || 0
    y = Number(pixelY) || 0
  }
  if (sideways && Math.abs(y) > Math.abs(x)) return { x: y, y: 0 }
  return { x: x, y: y }
}
