import "std.str"  as str
import "std.list" as list
import "std.int"  as int

import "lex-schema/schema"      as s
import "lex-schema/constraints" as c
import "lex-schema/json_value"  as jv
import "lex-schema/error"       as se

import "../src/predicate"  as p
import "../src/query"      as q
import "../src/connection" as conn

fn post_schema() -> s.ModelSchema {
  {
    title: "Post",
    description: "A blog post",
    fields: [
      s.required_int("id", []),
      s.required_str("title", [c.StrMaxLen(200)]),
      s.required_str("body",  []),
      s.optional(s.required_str("slug", [])),
    ],
  }
}

fn blog_post_schema() -> s.ModelSchema {
  {
    title: "BlogPost",
    description: "",
    fields: [
      s.required_int("id", []),
      s.required_str("title", []),
    ],
  }
}

fn dummy_decode(j :: jv.Json) -> Result[jv.Json, se.Errors] { Ok(j) }

# lex test convention: run_all :: () -> () — assert on failure.
fn run_all() -> () {
  # SELECT * FROM "post" (no filters)
  let repo_post := q.for_schema(post_schema(), dummy_decode)
  let sel_basic := q.build_select(q.select(repo_post))
  assert sel_basic.sql == "SELECT * FROM \"post\""

  # WHERE adds params
  let sel_where := q.build_select(
    q.where_clause(q.select(repo_post), p.eq("id", PInt(1))))
  assert str.contains(sel_where.sql, "WHERE")
  assert list.len(sel_where.params) == 1

  # LIMIT + OFFSET appear in SQL
  let sel_lim := q.build_select(
    q.offset(q.limit(q.select(repo_post), 10), 20))
  assert str.contains(sel_lim.sql, "LIMIT 10")
  assert str.contains(sel_lim.sql, "OFFSET 20")

  # ORDER BY
  let sel_ord := q.build_select(
    q.order_by(q.select(repo_post), "title", Asc))
  assert str.contains(sel_ord.sql, "ORDER BY \"title\" ASC")

  # Multiple WHERE clauses AND together
  let sel_multi := q.build_select(
    q.where_clause(
      q.where_clause(q.select(repo_post), p.eq("id", PInt(5))),
      p.eq("slug", PStr("hello"))))
  assert str.contains(sel_multi.sql, "AND")
  assert list.len(sel_multi.params) == 2

  # PascalCase title => snake_case table name
  let repo_bp := q.for_schema(blog_post_schema(), dummy_decode)
  assert repo_bp.table == "blog_post"

  # INSERT param count == number of schema fields
  let val := JObj([
    ("id",    JInt(1)),
    ("title", JStr("Hello")),
    ("body",  JStr("World")),
  ])
  let ins := q.build_insert(q.insert(repo_post, val))
  assert list.len(ins.params) == 4

  # UPDATE has SET and WHERE
  let upd := q.build_update(
    q.where_update(
      q.set_col(q.update(repo_post), "title", PStr("New")),
      p.eq("id", PInt(7))))
  assert str.contains(upd.sql, "SET")
  assert str.contains(upd.sql, "WHERE")

  # DELETE without WHERE
  let del_plain := q.build_delete(q.delete_from(repo_post))
  assert del_plain.sql == "DELETE FROM \"post\""

  # DELETE with WHERE
  let del_where := q.build_delete(
    q.where_delete(q.delete_from(repo_post), p.eq("id", PInt(3))))
  assert str.contains(del_where.sql, "WHERE")

  # for_dialect: SQLite leaves ? unchanged
  let sq_one := { sql: "SELECT * FROM \"post\" WHERE \"id\" = ?", params: [PInt(1)] }
  let sq_lite := q.for_dialect(sq_one, DbSqlite)
  assert sq_lite.sql == "SELECT * FROM \"post\" WHERE \"id\" = ?"

  # for_dialect: Postgres replaces ? with $1, $2, $3
  let sq_multi2 := {
    sql: "UPDATE \"t\" SET \"a\" = ?, \"b\" = ? WHERE \"id\" = ?",
    params: [PStr("x"), PInt(2), PInt(3)]
  }
  let sq_pg := q.for_dialect(sq_multi2, DbPostgres)
  assert sq_pg.sql == "UPDATE \"t\" SET \"a\" = $1, \"b\" = $2 WHERE \"id\" = $3"

  # for_dialect on a query with no params is a no-op for both dialects
  let sq_bare := { sql: "SELECT * FROM \"post\"", params: [] }
  let sq_bare_pg := q.for_dialect(sq_bare, DbPostgres)
  assert sq_bare_pg.sql == "SELECT * FROM \"post\""

  ()
}
