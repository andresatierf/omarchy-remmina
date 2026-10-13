// Tests for Model.js, the plugin's display model.
//
//   node --test
//
// Model.js is pure by design, so it needs no QML, no shell and no Remmina: the
// ordering rules that decide what Enter connects to are exercised here rather
// than by opening the picker and squinting at it.

const test = require("node:test")
const assert = require("node:assert/strict")

const Model = require("../Model.js")

// A row as `omarchy-remmina list` emits one.
function row(name, sub, extra) {
  return Object.assign({
    name: name, sub: sub || "", glyph: "", group: "", protocol: "rdp",
    file: "/p/" + name + ".remmina", recent: false, rank: -1
  }, extra || {})
}

function names(rows) {
  return rows.map(function (r) { return r.name })
}

test("parseList reads a well-formed payload", function () {
  const parsed = Model.parseList(JSON.stringify({ rows: [row("beelink")] }))
  assert.equal(parsed.rows.length, 1)
  assert.equal(parsed.missing, false)
})

test("parseList treats unusable input as no profiles rather than throwing", function () {
  for (const raw of ["", null, undefined, "not json", "{", "[]", "null"]) {
    const parsed = Model.parseList(raw)
    assert.deepEqual(parsed.rows, [], "rows for " + JSON.stringify(raw))
    assert.equal(parsed.missing, false)
  }
})

test("parseList reports a missing profiles folder", function () {
  assert.equal(Model.parseList('{"rows":[],"missing":true}').missing, true)
})

test("with no query, recent profiles lead, most recent first", function () {
  const rows = [
    row("alpha"),
    row("bravo", "", { recent: true, rank: 1 }),
    row("charlie"),
    row("delta", "", { recent: true, rank: 0 })
  ]
  assert.deepEqual(names(Model.displayRows(rows, "")), ["delta", "bravo", "alpha", "charlie"])
})

test("a name match beats a match in the address or group", function () {
  const rows = [
    row("nas", "ssh://root@lab.example"),
    row("lab", "rdp://andre@10.0.0.2")
  ]
  assert.deepEqual(names(Model.displayRows(rows, "lab")), ["lab", "nas"])
})

test("recency still orders matches within a query", function () {
  const rows = [
    row("lab-a"),
    row("lab-b", "", { recent: true, rank: 0 })
  ]
  assert.deepEqual(names(Model.displayRows(rows, "lab")), ["lab-b", "lab-a"])
})

test("the query is trimmed and case-insensitive", function () {
  const rows = [row("Beelink", "rdp://andre@192.168.1.9 · local")]
  assert.deepEqual(names(Model.displayRows(rows, "  BEE ")), ["Beelink"])
  assert.deepEqual(names(Model.displayRows(rows, "LOCAL")), ["Beelink"])
  assert.deepEqual(names(Model.displayRows(rows, "nothing")), [])
})

test("a row with no name or no file is dropped", function () {
  const rows = [row(""), row("nofile", "", { file: "" }), row("ok"), null]
  assert.deepEqual(names(Model.displayRows(rows, "")), ["ok"])
})

test("display rows carry every role, typed the same", function () {
  const shown = Model.displayRows([row("a"), { name: "b", file: "/p/b.remmina" }], "")
  for (const r of shown) {
    assert.deepEqual(Object.keys(r).sort(), ["file", "glyph", "name", "recent", "sub"])
    assert.equal(typeof r.recent, "boolean")
  }
})

test("clampIndex keeps the cursor in range", function () {
  assert.equal(Model.clampIndex(5, 3), 2)
  assert.equal(Model.clampIndex(-1, 3), 0)
  assert.equal(Model.clampIndex(1, 3), 1)
  assert.equal(Model.clampIndex(4, 0), 0)
})
