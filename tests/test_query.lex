import "std.str" as str

import "std.list" as list

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "../src/predicate" as p

import "../src/query" as q

import "../src/connection" as conn

fn post_schema() -> s.ModelSchema {
  { title: "Post", description: "A blog post", fields: [s.required_int("id", []), s.required_str("title", [StrMaxLen(200)]), s.required_str("body", []), s.optional(s.required_str("slug", []))] }
}

fn blog_post_schema() -> s.ModelSchema {
  { title: "BlogPost", description: "", fields: [s.required_int("id", []), s.required_str("title", [])] }
}

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn select_basic_sql() -> Result[Unit, Str] {
  let sel := q.build_select(q.select(q.for_schema(post_schema())))
  check("select basic", sel.sql == "SELECT * FROM \"post\"")
}

fn select_where_keyword() -> Result[Unit, Str] {
  let sel := q.build_select(q.where_clause(q.select(q.for_schema(post_schema())), p.eq("id", PInt(1))))
  check("select WHERE", str.contains(sel.sql, "WHERE"))
}

fn select_where_param_count() -> Result[Unit, Str] {
  let sel := q.build_select(q.where_clause(q.select(q.for_schema(post_schema())), p.eq("id", PInt(1))))
  check("select WHERE params", list.len(sel.params) == 1)
}

fn select_limit_keyword() -> Result[Unit, Str] {
  let sel := q.build_select(q.offset(q.limit(q.select(q.for_schema(post_schema())), 10), 20))
  check("select LIMIT", str.contains(sel.sql, "LIMIT 10"))
}

fn select_offset_keyword() -> Result[Unit, Str] {
  let sel := q.build_select(q.offset(q.limit(q.select(q.for_schema(post_schema())), 10), 20))
  check("select OFFSET", str.contains(sel.sql, "OFFSET 20"))
}

fn select_order_by() -> Result[Unit, Str] {
  let sel := q.build_select(q.order_by(q.select(q.for_schema(post_schema())), "title", Asc))
  check("ORDER BY", str.contains(sel.sql, "ORDER BY \"title\" ASC"))
}

fn select_multi_where_uses_and() -> Result[Unit, Str] {
  let sel := q.build_select(q.where_clause(q.where_clause(q.select(q.for_schema(post_schema())), p.eq("id", PInt(5))), p.eq("slug", PStr("hello"))))
  check("multi-WHERE AND", str.contains(sel.sql, "AND"))
}

fn select_multi_where_param_count() -> Result[Unit, Str] {
  let sel := q.build_select(q.where_clause(q.where_clause(q.select(q.for_schema(post_schema())), p.eq("id", PInt(5))), p.eq("slug", PStr("hello"))))
  check("multi-WHERE params", list.len(sel.params) == 2)
}

fn pascal_to_snake_table() -> Result[Unit, Str] {
  let repo := q.for_schema(blog_post_schema())
  check("snake_case table", repo.table == "blog_post")
}

fn insert_param_count_matches_fields() -> Result[Unit, Str] {
  let val := JObj([("id", JInt(1)), ("title", JStr("Hello")), ("body", JStr("World"))])
  let ins := q.build_insert(q.insert(q.for_schema(post_schema()), val))
  check("insert param count", list.len(ins.params) == 4)
}

fn update_has_set() -> Result[Unit, Str] {
  let upd := q.build_update(q.where_update(q.set_col(q.update(q.for_schema(post_schema())), "title", PStr("New")), p.eq("id", PInt(7))))
  check("update SET", str.contains(upd.sql, "SET"))
}

fn update_has_where() -> Result[Unit, Str] {
  let upd := q.build_update(q.where_update(q.set_col(q.update(q.for_schema(post_schema())), "title", PStr("New")), p.eq("id", PInt(7))))
  check("update WHERE", str.contains(upd.sql, "WHERE"))
}

fn delete_no_where() -> Result[Unit, Str] {
  let del := q.build_delete(q.delete_from(q.for_schema(post_schema())))
  check("delete plain", del.sql == "DELETE FROM \"post\"")
}

fn delete_with_where() -> Result[Unit, Str] {
  let del := q.build_delete(q.where_delete(q.delete_from(q.for_schema(post_schema())), p.eq("id", PInt(3))))
  check("delete WHERE", str.contains(del.sql, "WHERE"))
}

fn dialect_sqlite_leaves_qmark() -> Result[Unit, Str] {
  let sq := { sql: "SELECT * FROM \"post\" WHERE \"id\" = ?", params: [PInt(1)] }
  let out := q.for_dialect(sq, DbSqlite)
  check("sqlite ?", out.sql == "SELECT * FROM \"post\" WHERE \"id\" = ?")
}

fn dialect_postgres_renumbers() -> Result[Unit, Str] {
  let sq := { sql: "UPDATE \"t\" SET \"a\" = ?, \"b\" = ? WHERE \"id\" = ?", params: [PStr("x"), PInt(2), PInt(3)] }
  let out := q.for_dialect(sq, DbPostgres)
  check("postgres $N", out.sql == "UPDATE \"t\" SET \"a\" = $1, \"b\" = $2 WHERE \"id\" = $3")
}

fn dialect_no_params_noop() -> Result[Unit, Str] {
  let sq := { sql: "SELECT * FROM \"post\"", params: [] }
  let out := q.for_dialect(sq, DbPostgres)
  check("no-param no-op", out.sql == "SELECT * FROM \"post\"")
}

fn suite() -> List[Result[Unit, Str]] {
  [select_basic_sql(), select_where_keyword(), select_where_param_count(), select_limit_keyword(), select_offset_keyword(), select_order_by(), select_multi_where_uses_and(), select_multi_where_param_count(), pascal_to_snake_table(), insert_param_count_matches_fields(), update_has_set(), update_has_where(), delete_no_where(), delete_with_where(), dialect_sqlite_leaves_qmark(), dialect_postgres_renumbers(), dialect_no_params_noop()]
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
