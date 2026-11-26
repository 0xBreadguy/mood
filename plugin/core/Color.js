.pragma library

// Parsing and normalizing hex highlight colors, whether typed in the settings
// field or returned by an external screen color picker (`hyprpicker`).

var MAX_INPUT = 256

// Accepts #rgb or #rrggbb, with or without the leading #. Returns lowercase
// #rrggbb, or "" if the text is not a valid hex color.
function normalizeHex(text) {
  if (text === undefined || text === null) return ""
  var s = String(text)
  if (s.length > MAX_INPUT) return ""
  s = s.trim().toLowerCase()
  if (s.length === 0) return ""
  if (s.charAt(0) !== "#") s = "#" + s
  if (/^#[0-9a-f]{3}$/.test(s))
    return "#" + s[1] + s[1] + s[2] + s[2] + s[3] + s[3]
  return /^#[0-9a-f]{6}$/.test(s) ? s : ""
}

// Parses stdout from `hyprpicker -f hex -b -l -r`. Tolerates leading/trailing
// whitespace and strips ANSI SGR escapes if present, but only accepts a line
// that is strictly a 6-digit hex color (#rrggbb). Returns lowercase #rrggbb or "".
function parsePicked(output) {
  if (typeof output !== "string" || output.length === 0 || output.length > 4096) return ""
  var lines = output.split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\x1b\[[0-9;]*m/g, "").trim().toLowerCase()
    if (/^#[0-9a-f]{6}$/.test(line)) return line
  }
  return ""
}
