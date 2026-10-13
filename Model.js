// Display model for the Remmina picker: everything between `omarchy-remmina
// list` and the rows on screen. Pure functions only — no Process, no
// Quickshell, no filesystem. The overlay owns all I/O and hands the results in,
// which is what lets this file be required from node and tested on its own.

// One list payload from the helper, normalized so the caller never has to think
// about a truncated read or a missing key. A parse failure arrives here as "no
// rows", which is exactly how the overlay wants to draw it.
function parseList(raw) {
  var parsed = null
  try {
    parsed = JSON.parse(raw || "null")
  } catch (e) {
    parsed = null
  }

  return {
    rows: (parsed && Array.isArray(parsed.rows)) ? parsed.rows : [],
    missing: !!(parsed && parsed.missing)
  }
}

// The shape the overlay's ListModel wants. Kept flat and typed the same on
// every row: a ListModel infers its roles from the first row it is given, so a
// missing or differently-typed key on a later row would be silently dropped.
function displayRow(row) {
  return {
    name: String(row.name || ""),
    sub: String(row.sub || ""),
    glyph: String(row.glyph || ""),
    file: String(row.file || ""),
    recent: row.recent === true
  }
}

function rank(row) {
  return typeof row.rank === "number" && row.rank >= 0 ? row.rank : Infinity
}

// Recent rows first, most recent at the top; everything else keeps the order
// the helper sent, which is by name. Array.prototype.sort is stable, so ties
// keep that order too.
function byRecency(rows) {
  return rows.slice().sort(function(a, b) {
    var ra = rank(a), rb = rank(b)
    if (ra === rb) return 0
    return ra < rb ? -1 : 1
  })
}

// The rows to draw, in order.
//
// With no query the profiles you connected to last come first, so Enter
// reconnects to the one you most likely want. With a query, a name match beats
// a match that only landed in the subtext (address or group), and recency
// orders each of those two groups.
function displayRows(rows, query) {
  var values = byRecency((Array.isArray(rows) ? rows : []).filter(Boolean))
  var needle = String(query || "").trim().toLowerCase()

  var primary = []
  var secondary = []

  for (var i = 0; i < values.length; i++) {
    var row = values[i]
    if (!row || !row.name || !row.file) continue

    if (needle.length === 0 || String(row.name).toLowerCase().indexOf(needle) >= 0)
      primary.push(displayRow(row))
    else if (String(row.sub || "").toLowerCase().indexOf(needle) >= 0)
      secondary.push(displayRow(row))
  }

  return primary.concat(secondary)
}

// Where the cursor lands once the list underneath it has changed size. Clamps
// into range rather than resetting to the top, so narrowing a filter keeps the
// selection near whatever the user was looking at.
function clampIndex(index, count) {
  if (count <= 0) return 0
  if (index >= count) return count - 1
  if (index < 0) return 0
  return index
}

if (typeof module !== "undefined") {
  module.exports = {
    parseList: parseList,
    displayRow: displayRow,
    displayRows: displayRows,
    clampIndex: clampIndex
  }
}
