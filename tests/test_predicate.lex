import "std.str"  as str
import "std.list" as list

import "../src/predicate" as p

fn suite() -> List[Result[Str, Str]] {
  [
    test_empty_where(),
    test_eq_renders(),
    test_neq_renders(),
    test_and_combines(),
    test_in_placeholders(),
    test_is_null_no_params(),
    test_not_wraps(),
    test_or_renders(),
    test_where_list_ands(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Str, Str]) -> Int {
    match v {
      Ok(_)    => acc,
      Err(msg) => {
        let _ := msg
        acc + 1
      },
    }
  })
}

fn assert_eq_str(label :: Str, got :: Str, want :: Str) -> Result[Str, Str] {
  if got == want { Ok(label) }
  else {
    Err(str.concat(label, str.concat(" FAIL: got=",
      str.concat(got, str.concat(" want=", want)))))
  }
}

fn assert_eq_int(label :: Str, got :: Int, want :: Int) -> Result[Str, Str] {
  if got == want { Ok(label) }
  else {
    Err(str.concat(label, str.concat(" FAIL: got=",
      str.concat(str.from_int(got), str.concat(" want=", str.from_int(want))))))
  }
}

fn test_empty_where() -> Result[Str, Str] {
  let r := p.render_where([])
  let s := match r { (sql, _) => sql }
  let ps := match r { (_, params) => params }
  match assert_eq_str("empty_where_sql", s, "") {
    Err(e) => Err(e),
    Ok(_)  => assert_eq_int("empty_where_params", list.len(ps), 0),
  }
}

fn test_eq_renders() -> Result[Str, Str] {
  let pred := p.eq("id", PInt(42))
  let r := p.render_pred(pred)
  let s := match r { (sql, _) => sql }
  assert_eq_str("eq_renders", s, "\"id\" = ?")
}

fn test_neq_renders() -> Result[Str, Str] {
  let pred := p.neq("status", PStr("deleted"))
  let r := p.render_pred(pred)
  let s := match r { (sql, _) => sql }
  assert_eq_str("neq_renders", s, "\"status\" != ?")
}

fn test_and_combines() -> Result[Str, Str] {
  let pred := p.and_pred(
    p.eq("a", PInt(1)),
    p.eq("b", PInt(2))
  )
  let r := p.render_pred(pred)
  let s := match r { (sql, _) => sql }
  let ps := match r { (_, params) => params }
  match assert_eq_str("and_sql", s, "\"a\" = ? AND \"b\" = ?") {
    Err(e) => Err(e),
    Ok(_)  => assert_eq_int("and_params", list.len(ps), 2),
  }
}

fn test_in_placeholders() -> Result[Str, Str] {
  let pred := p.in_list("status", [PStr("a"), PStr("b"), PStr("c")])
  let r := p.render_pred(pred)
  let s := match r { (sql, _) => sql }
  let ps := match r { (_, params) => params }
  match assert_eq_str("in_sql", s, "\"status\" IN (?, ?, ?)") {
    Err(e) => Err(e),
    Ok(_)  => assert_eq_int("in_params", list.len(ps), 3),
  }
}

fn test_is_null_no_params() -> Result[Str, Str] {
  let pred := p.is_null("deleted_at")
  let r := p.render_pred(pred)
  let s := match r { (sql, _) => sql }
  let ps := match r { (_, params) => params }
  match assert_eq_str("is_null_sql", s, "\"deleted_at\" IS NULL") {
    Err(e) => Err(e),
    Ok(_)  => assert_eq_int("is_null_params", list.len(ps), 0),
  }
}

fn test_not_wraps() -> Result[Str, Str] {
  let pred := p.not_pred(p.eq("active", PBool(true)))
  let r := p.render_pred(pred)
  let s := match r { (sql, _) => sql }
  assert_eq_str("not_wraps", s, "NOT (\"active\" = ?)")
}

fn test_or_renders() -> Result[Str, Str] {
  let pred := p.or_pred(
    p.eq("role", PStr("admin")),
    p.eq("role", PStr("mod"))
  )
  let r := p.render_pred(pred)
  let s := match r { (sql, _) => sql }
  assert_eq_str("or_renders", s, "(\"role\" = ? OR \"role\" = ?)")
}

fn test_where_list_ands() -> Result[Str, Str] {
  let r := p.render_where([
    p.eq("x", PInt(1)),
    p.eq("y", PInt(2)),
    p.eq("z", PInt(3)),
  ])
  let s := match r { (sql, _) => sql }
  let ps := match r { (_, params) => params }
  match assert_eq_str("where_list_sql", s, "\"x\" = ? AND \"y\" = ? AND \"z\" = ?") {
    Err(e) => Err(e),
    Ok(_)  => assert_eq_int("where_list_params", list.len(ps), 3),
  }
}
