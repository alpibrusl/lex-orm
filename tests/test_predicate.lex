import "std.list" as list

import "std.str" as str

import "../src/predicate" as p

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn empty_where_sql() -> Result[Unit, Str] {
  let r0 := p.render_where([])
  check("empty where sql", match r0 {
    (sql, _) => sql,
  } == "")
}

fn empty_where_params() -> Result[Unit, Str] {
  let r0 := p.render_where([])
  check("empty where params", list.len(match r0 {
    (_, ps) => ps,
  }) == 0)
}

fn eq_render() -> Result[Unit, Str] {
  check("eq", match p.render_pred(p.eq("id", PInt(42))) {
    (sql, _) => sql,
  } == "\"id\" = ?")
}

fn neq_render() -> Result[Unit, Str] {
  check("neq", match p.render_pred(p.neq("status", PStr("x"))) {
    (sql, _) => sql,
  } == "\"status\" != ?")
}

fn gt_render() -> Result[Unit, Str] {
  check("gt", match p.render_pred(p.gt("score", PInt(100))) {
    (sql, _) => sql,
  } == "\"score\" > ?")
}

fn gte_render() -> Result[Unit, Str] {
  check("gte", match p.render_pred(p.gte("score", PInt(100))) {
    (sql, _) => sql,
  } == "\"score\" >= ?")
}

fn lt_render() -> Result[Unit, Str] {
  check("lt", match p.render_pred(p.lt("score", PInt(100))) {
    (sql, _) => sql,
  } == "\"score\" < ?")
}

fn lte_render() -> Result[Unit, Str] {
  check("lte", match p.render_pred(p.lte("score", PInt(100))) {
    (sql, _) => sql,
  } == "\"score\" <= ?")
}

fn is_null_render() -> Result[Unit, Str] {
  check("is_null", match p.render_pred(p.is_null("deleted_at")) {
    (sql, _) => sql,
  } == "\"deleted_at\" IS NULL")
}

fn is_not_null_render() -> Result[Unit, Str] {
  check("is_not_null", match p.render_pred(p.is_not_null("published_at")) {
    (sql, _) => sql,
  } == "\"published_at\" IS NOT NULL")
}

fn in_list_sql() -> Result[Unit, Str] {
  let r := p.render_pred(p.in_list("status", [PStr("a"), PStr("b"), PStr("c")]))
  check("in_list sql", match r {
    (sql, _) => sql,
  } == "\"status\" IN (?, ?, ?)")
}

fn in_list_param_count() -> Result[Unit, Str] {
  let r := p.render_pred(p.in_list("status", [PStr("a"), PStr("b"), PStr("c")]))
  check("in_list param count", list.len(match r {
    (_, ps) => ps,
  }) == 3)
}

fn and_render_sql() -> Result[Unit, Str] {
  let r := p.render_pred(p.and_pred(p.eq("a", PInt(1)), p.eq("b", PInt(2))))
  check("and sql", match r {
    (sql, _) => sql,
  } == "\"a\" = ? AND \"b\" = ?")
}

fn and_param_count() -> Result[Unit, Str] {
  let r := p.render_pred(p.and_pred(p.eq("a", PInt(1)), p.eq("b", PInt(2))))
  check("and params", list.len(match r {
    (_, ps) => ps,
  }) == 2)
}

fn or_render() -> Result[Unit, Str] {
  let r := p.render_pred(p.or_pred(p.eq("role", PStr("admin")), p.eq("role", PStr("mod"))))
  check("or", match r {
    (sql, _) => sql,
  } == "(\"role\" = ? OR \"role\" = ?)")
}

fn not_render() -> Result[Unit, Str] {
  let r := p.render_pred(p.not_pred(p.eq("active", PInt(1))))
  check("not", match r {
    (sql, _) => sql,
  } == "NOT (\"active\" = ?)")
}

fn render_where_joins_with_and() -> Result[Unit, Str] {
  let r := p.render_where([p.eq("x", PInt(1)), p.eq("y", PInt(2)), p.eq("z", PInt(3))])
  check("render_where AND", match r {
    (sql, _) => sql,
  } == "\"x\" = ? AND \"y\" = ? AND \"z\" = ?")
}

fn render_where_param_count() -> Result[Unit, Str] {
  let r := p.render_where([p.eq("x", PInt(1)), p.eq("y", PInt(2)), p.eq("z", PInt(3))])
  check("render_where params", list.len(match r {
    (_, ps) => ps,
  }) == 3)
}

fn like_sql() -> Result[Unit, Str] {
  let r := p.render_pred(p.like("name", "%alice%"))
  check("like sql", match r {
    (sql, _) => sql,
  } == "\"name\" LIKE ?")
}

fn like_param_count() -> Result[Unit, Str] {
  let r := p.render_pred(p.like("name", "%alice%"))
  check("like params", list.len(match r {
    (_, ps) => ps,
  }) == 1)
}

fn ilike_render() -> Result[Unit, Str] {
  let r := p.render_pred(p.ilike("email", "%@example.com"))
  check("ilike", match r {
    (sql, _) => sql,
  } == "\"email\" ILIKE ?")
}

fn between_sql() -> Result[Unit, Str] {
  let r := p.render_pred(p.between("age", PInt(18), PInt(65)))
  check("between sql", match r {
    (sql, _) => sql,
  } == "\"age\" BETWEEN ? AND ?")
}

fn between_param_count() -> Result[Unit, Str] {
  let r := p.render_pred(p.between("age", PInt(18), PInt(65)))
  check("between params", list.len(match r {
    (_, ps) => ps,
  }) == 2)
}

fn raw_pred_sql() -> Result[Unit, Str] {
  let r := p.render_pred(p.raw_pred("ST_DWithin(location, ST_Point(?, ?), ?)", [PStr("1.0"), PStr("2.0"), PInt(500)]))
  check("raw sql", match r {
    (sql, _) => sql,
  } == "ST_DWithin(location, ST_Point(?, ?), ?)")
}

fn raw_pred_param_count() -> Result[Unit, Str] {
  let r := p.render_pred(p.raw_pred("ST_DWithin(location, ST_Point(?, ?), ?)", [PStr("1.0"), PStr("2.0"), PInt(500)]))
  check("raw params", list.len(match r {
    (_, ps) => ps,
  }) == 3)
}

fn between_in_where_keyword() -> Result[Unit, Str] {
  let r := p.render_where([p.eq("active", PInt(1)), p.between("score", PInt(10), PInt(100))])
  check("BETWEEN in where", str.contains(match r {
    (sql, _) => sql,
  }, "BETWEEN"))
}

fn between_in_where_param_count() -> Result[Unit, Str] {
  let r := p.render_where([p.eq("active", PInt(1)), p.between("score", PInt(10), PInt(100))])
  check("BETWEEN params", list.len(match r {
    (_, ps) => ps,
  }) == 3)
}

fn suite() -> List[Result[Unit, Str]] {
  [empty_where_sql(), empty_where_params(), eq_render(), neq_render(), gt_render(), gte_render(), lt_render(), lte_render(), is_null_render(), is_not_null_render(), in_list_sql(), in_list_param_count(), and_render_sql(), and_param_count(), or_render(), not_render(), render_where_joins_with_and(), render_where_param_count(), like_sql(), like_param_count(), ilike_render(), between_sql(), between_param_count(), raw_pred_sql(), raw_pred_param_count(), between_in_where_keyword(), between_in_where_param_count()]
}

fn run_all() -> Int {
  let failed := list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
  if failed > 0 {
    1 / 0
  } else {
    0
  }
}

