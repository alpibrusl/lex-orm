import "std.list" as list
import "std.str"  as str

import "../src/predicate" as p

# lex test convention: run_all :: () -> () — assert on failure.
fn run_all() -> () {
  # empty WHERE => ("", [])
  let r0 := p.render_where([])
  let s0 := match r0 { (sql, _) => sql }
  let p0 := match r0 { (_, ps) => ps }
  assert s0 == ""
  assert list.len(p0) == 0

  # PEq renders col = ?
  let r_eq := p.render_pred(p.eq("id", PInt(42)))
  let s_eq := match r_eq { (sql, _) => sql }
  assert s_eq == "\"id\" = ?"

  # PNeq renders col != ?
  let r_neq := p.render_pred(p.neq("status", PStr("deleted")))
  let s_neq := match r_neq { (sql, _) => sql }
  assert s_neq == "\"status\" != ?"

  # PAnd combines with AND, collects both params
  let r_and := p.render_pred(p.and_pred(
    p.eq("a", PInt(1)),
    p.eq("b", PInt(2))
  ))
  let s_and := match r_and { (sql, _) => sql }
  let p_and := match r_and { (_, ps) => ps }
  assert s_and == "\"a\" = ? AND \"b\" = ?"
  assert list.len(p_and) == 2

  # PIn renders IN (?, ?, ?)
  let r_in := p.render_pred(p.in_list("status", [PStr("a"), PStr("b"), PStr("c")]))
  let s_in := match r_in { (sql, _) => sql }
  let p_in := match r_in { (_, ps) => ps }
  assert s_in == "\"status\" IN (?, ?, ?)"
  assert list.len(p_in) == 3

  # PIsNull has no params
  let r_null := p.render_pred(p.is_null("deleted_at"))
  let s_null := match r_null { (sql, _) => sql }
  let p_null := match r_null { (_, ps) => ps }
  assert s_null == "\"deleted_at\" IS NULL"
  assert list.len(p_null) == 0

  # PNot wraps with NOT (...)
  let r_not := p.render_pred(p.not_pred(p.eq("active", PBool(true))))
  let s_not := match r_not { (sql, _) => sql }
  assert s_not == "NOT (\"active\" = ?)"

  # POr renders (a OR b)
  let r_or := p.render_pred(p.or_pred(
    p.eq("role", PStr("admin")),
    p.eq("role", PStr("mod"))
  ))
  let s_or := match r_or { (sql, _) => sql }
  assert s_or == "(\"role\" = ? OR \"role\" = ?)"

  # render_where list ANDs multiple predicates
  let r_list := p.render_where([
    p.eq("x", PInt(1)),
    p.eq("y", PInt(2)),
    p.eq("z", PInt(3)),
  ])
  let s_list := match r_list { (sql, _) => sql }
  let p_list := match r_list { (_, ps) => ps }
  assert s_list == "\"x\" = ? AND \"y\" = ? AND \"z\" = ?"
  assert list.len(p_list) == 3

  # PLike emits col LIKE ? with PStr param
  let r_like := p.render_pred(p.like("name", "%alice%"))
  let s_like := match r_like { (sql, _) => sql }
  let p_like := match r_like { (_, ps) => ps }
  assert s_like == "\"name\" LIKE ?"
  assert list.len(p_like) == 1

  # PILike emits col ILIKE ?
  let r_ilike := p.render_pred(p.ilike("email", "%@example.com"))
  let s_ilike := match r_ilike { (sql, _) => sql }
  assert s_ilike == "\"email\" ILIKE ?"

  # PBetween emits col BETWEEN ? AND ? with two params
  let r_bet := p.render_pred(p.between("age", PInt(18), PInt(65)))
  let s_bet := match r_bet { (sql, _) => sql }
  let p_bet := match r_bet { (_, ps) => ps }
  assert s_bet == "\"age\" BETWEEN ? AND ?"
  assert list.len(p_bet) == 2

  # PRaw passes SQL and params through unchanged
  let r_raw := p.render_pred(p.raw_pred("ST_DWithin(location, ST_Point(?, ?), ?)", [PFloat(1.0), PFloat(2.0), PInt(500)]))
  let s_raw := match r_raw { (sql, _) => sql }
  let p_raw := match r_raw { (_, ps) => ps }
  assert s_raw == "ST_DWithin(location, ST_Point(?, ?), ?)"
  assert list.len(p_raw) == 3

  # PBetween inside render_where integrates cleanly
  let r_combo := p.render_where([
    p.eq("active", PBool(true)),
    p.between("score", PInt(10), PInt(100)),
  ])
  let s_combo := match r_combo { (sql, _) => sql }
  let p_combo := match r_combo { (_, ps) => ps }
  assert str.contains(s_combo, "BETWEEN")
  assert str.contains(s_combo, "AND")
  assert list.len(p_combo) == 3

  ()
}
