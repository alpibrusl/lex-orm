import "std.list" as list
import "std.str"  as str

import "../src/predicate" as p

# lex test convention: run_all :: () -> () — assert on failure.
fn run_all() -> () {
  # empty WHERE => ("", [])
  let r0 := p.render_where([])
  assert match r0 { (sql, _) => sql } == ""
  assert list.len(match r0 { (_, ps) => ps }) == 0

  # basic comparison operators
  let r_eq := p.render_pred(p.eq("id", PInt(42)))
  assert match r_eq { (sql, _) => sql } == "\"id\" = ?"

  let r_neq := p.render_pred(p.neq("status", PStr("deleted")))
  assert match r_neq { (sql, _) => sql } == "\"status\" != ?"

  let r_gt  := p.render_pred(p.gt("score", PInt(100)))
  assert match r_gt  { (sql, _) => sql } == "\"score\" > ?"

  # PIn renders IN (?, ?, ?)
  let r_in := p.render_pred(p.in_list("status", [PStr("a"), PStr("b"), PStr("c")]))
  assert match r_in { (sql, _) => sql } == "\"status\" IN (?, ?, ?)"
  assert list.len(match r_in { (_, ps) => ps }) == 3

  # PIsNull / PIsNotNull
  let r_null    := p.render_pred(p.is_null("deleted_at"))
  let r_notnull := p.render_pred(p.is_not_null("published_at"))
  assert match r_null    { (sql, _) => sql } == "\"deleted_at\" IS NULL"
  assert match r_notnull { (sql, _) => sql } == "\"published_at\" IS NOT NULL"
  assert list.len(match r_null { (_, ps) => ps }) == 0

  # PAnd
  let r_and := p.render_pred(p.and_pred(p.eq("a", PInt(1)), p.eq("b", PInt(2))))
  assert match r_and { (sql, _) => sql } == "\"a\" = ? AND \"b\" = ?"
  assert list.len(match r_and { (_, ps) => ps }) == 2

  # POr
  let r_or := p.render_pred(p.or_pred(p.eq("role", PStr("admin")), p.eq("role", PStr("mod"))))
  assert match r_or { (sql, _) => sql } == "(\"role\" = ? OR \"role\" = ?)"

  # PNot
  let r_not := p.render_pred(p.not_pred(p.eq("active", PBool(true))))
  assert match r_not { (sql, _) => sql } == "NOT (\"active\" = ?)"

  # render_where ANDs a list
  let r_list := p.render_where([p.eq("x", PInt(1)), p.eq("y", PInt(2)), p.eq("z", PInt(3))])
  assert match r_list { (sql, _) => sql } == "\"x\" = ? AND \"y\" = ? AND \"z\" = ?"
  assert list.len(match r_list { (_, ps) => ps }) == 3

  # PLike — col LIKE ? with PStr param
  let r_like := p.render_pred(p.like("name", "%alice%"))
  assert match r_like { (sql, _) => sql } == "\"name\" LIKE ?"
  assert list.len(match r_like { (_, ps) => ps }) == 1

  # PILike — col ILIKE ? (Postgres case-insensitive)
  let r_ilike := p.render_pred(p.ilike("email", "%@example.com"))
  assert match r_ilike { (sql, _) => sql } == "\"email\" ILIKE ?"

  # PBetween — col BETWEEN ? AND ? with two params
  let r_bet := p.render_pred(p.between("age", PInt(18), PInt(65)))
  assert match r_bet { (sql, _) => sql } == "\"age\" BETWEEN ? AND ?"
  assert list.len(match r_bet { (_, ps) => ps }) == 2

  # PRaw — passes SQL and params through unchanged
  let r_raw := p.render_pred(p.raw_pred(
    "ST_DWithin(location, ST_Point(?, ?), ?)",
    [PFloat(1.0), PFloat(2.0), PInt(500)]))
  assert match r_raw { (sql, _) => sql } == "ST_DWithin(location, ST_Point(?, ?), ?)"
  assert list.len(match r_raw { (_, ps) => ps }) == 3

  # PBetween inside render_where — param count sums correctly
  let r_combo := p.render_where([
    p.eq("active", PBool(true)),
    p.between("score", PInt(10), PInt(100)),
  ])
  assert str.contains(match r_combo { (sql, _) => sql }, "BETWEEN")
  assert list.len(match r_combo { (_, ps) => ps }) == 3

  ()
}
