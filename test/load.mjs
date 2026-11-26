// Loads one of the plugin's QML JavaScript libraries into Node for unit tests:
// strip the QML pragma, evaluate the rest, and hand back the names asked for.
import { readFileSync } from "node:fs"

export function load(name, exports) {
  const source = readFileSync(new URL(`../plugin/core/${name}.js`, import.meta.url), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
  return new Function(`${source}\nreturn { ${exports.join(", ")} }`)()
}

// A repeatable random source, so a shuffle in a test is the same every run.
export function seeded(seed) {
  let s = seed >>> 0
  return () => {
    s = (s + 0x6D2B79F5) >>> 0
    let t = Math.imul(s ^ (s >>> 15), 1 | s)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
