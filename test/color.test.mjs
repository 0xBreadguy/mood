// Hex color normalization and screen-picker output parsing.
import assert from "node:assert/strict"
import { test } from "node:test"
import { load } from "./load.mjs"

const Color = load("Color", ["normalizeHex", "parsePicked"])

test("normalizeHex accepts #rgb, #rrggbb, uppercase, and omitted #", () => {
  assert.equal(Color.normalizeHex("#7AA2F7"), "#7aa2f7")
  assert.equal(Color.normalizeHex("7aa2f7"), "#7aa2f7")
  assert.equal(Color.normalizeHex("  #0fA  "), "#00ffaa")
  assert.equal(Color.normalizeHex("abc"), "#aabbcc")
})

test("normalizeHex rejects malformed, empty, markup-shaped, and oversized input", () => {
  for (const bad of ["", "   ", null, undefined, "#", "#12", "#1234", "#1234567", "#gggggg", "red",
                     "<img src=x>", "#7aa2f7; rm -rf /", "a".repeat(300)]) {
    assert.equal(Color.normalizeHex(bad), "", String(bad))
  }
})

test("parsePicked accepts strict 6-digit hex output from hyprpicker", () => {
  assert.equal(Color.parsePicked("#9ece6a\n"), "#9ece6a")
  assert.equal(Color.parsePicked("  #E0AF68 \r\n"), "#e0af68")
  assert.equal(Color.parsePicked("\x1b[38;2;122;162;247m#7aa2f7\x1b[0m\n"), "#7aa2f7")
  assert.equal(Color.parsePicked("some warning\n#1a1b26\n"), "#1a1b26")
})

test("parsePicked rejects empty, cancelled, partial, or untrusted output", () => {
  for (const bad of ["", "\n", "   ", null, undefined, "#fff", "7aa2f7",
                     "#7aa2f7 extra", "<b>#7aa2f7</b>", "error: no display", "#".repeat(5000)]) {
    assert.equal(Color.parsePicked(bad), "", String(bad))
  }
})
