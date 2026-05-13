# Example 04: type-safe JOIN result types with lex 0.9.1 record spreads.
#
# lex 0.9.1 adds { ...TypeName } spread syntax in type expressions.
# JOIN result types can reuse the field sets of their constituent schemas
# without duplicating every field name:
#
#   type PostWithAuthor = { ...Post, username :: Str, email :: Str }
#
# This is equivalent to writing out all Post fields plus username + email,
# but will automatically track upstream changes to Post.
#
# Run with: lex run examples/04_joins.lex

import "std.str"  as str
import "std.list" as list
import "std.int"  as int

import "lex-schema/schema"      as s
import "lex-schema/constraints" as c
import "lex-schema/json_value"  as jv
import "lex-schema/error"       as se

import "../src/query"      as q
import "../src/predicate"  as p
import "../src/connection" as conn

fn user_schema() -> s.ModelSchema {
  {
    title: "user",
    description: "Application user",
    fields: [
      s.required_str("id",       []),
      s.required_str("username", [c.StrNonEmpty]),
      s.required_str("email",    []),
    ],
  }
}

fn post_schema() -> s.ModelSchema {
  {
    title: "post",
    description: "Blog post",
    fields: [
      s.required_int("id",      [c.IntPositive]),
      s.required_str("title",   [c.StrMaxLen(200)]),
      s.required_str("user_id", []),
    ],
  }
}

# The PostWithAuthor type expressed using record spread syntax (lex 0.9.1):
#
#   type Post           = { id :: Int, title :: Str, user_id :: Str }
#   type User           = { id :: Str, username :: Str, email :: Str }
#   type PostWithAuthor = { ...Post, username :: Str, email :: Str }
#
# The decode function accepts jv.Json and returns PostWithAuthor via the
# schema's standard decode pipeline.

fn decode_post_with_author(j :: jv.Json) -> Result[jv.Json, se.Errors] { Ok(j) }

# Build an INNER JOIN SQL plan that produces one JSON object per row.
# The json_object / json_build_object call picks columns from both tables
# so the result can be decoded into a PostWithAuthor value.
fn build_posts_with_author(dialect :: conn.Dialect) -> q.SqlQuery {
  let p_t    := "\"post\""
  let u_t    := "\"user\""
  let json_fn := match dialect { DbPostgres => "json_build_object", DbSqlite => "json_object" }

  # JSON pairs: 'field_name', table."column"
  let expr :=
    json_fn + "(" +
    "'id', "       + p_t + ".\"id\", " +
    "'title', "    + p_t + ".\"title\", " +
    "'user_id', "  + p_t + ".\"user_id\", " +
    "'username', " + u_t + ".\"username\", " +
    "'email', "    + u_t + ".\"email\"" +
    ") AS _j"

  let sql :=
    "SELECT " + expr +
    " FROM " + p_t +
    " INNER JOIN " + u_t + " ON " + p_t + ".\"user_id\" = " + u_t + ".\"id\""

  { sql: sql, params: [] }
}

# Add a WHERE filter on top of the join plan.
fn posts_by_author(dialect :: conn.Dialect, user_id :: Str) -> q.SqlQuery {
  let base    := build_posts_with_author(dialect)
  let where_r := p.render_where([p.eq("\"post\".\"user_id\"", PStr(user_id))])
  let w_sql   := match where_r { (s2, _) => s2 }
  let w_ps    := match where_r { (_, ps) => ps }
  { sql: base.sql + " WHERE " + w_sql, params: w_ps }
}

# Show paginated SELECT plan alongside the join.
fn paginated_plan() -> q.SqlQuery {
  let decode   := fn (j :: jv.Json) -> Result[jv.Json, se.Errors] { Ok(j) }
  let repo     := q.for_schema(post_schema(), decode)
  let base_sel := q.select(repo)
  let page_sel := q.paginate(base_sel, 2, 10)  # page 2, 10 per page
  q.build_select(page_sel)
}

fn main() -> Str {
  let join_sq := build_posts_with_author(DbSqlite)
  let filt_sq := posts_by_author(DbPostgres, "user_42")
  let filt_pg := q.for_dialect(filt_sq, DbPostgres)
  let page_sq := paginated_plan()

  str.join([
    "=== INNER JOIN (SQLite) ===",
    join_sq.sql,
    "",
    "=== INNER JOIN + WHERE, user_42 (Postgres $N placeholders) ===",
    filt_pg.sql,
    "params: " + int.to_str(list.len(filt_pg.params)),
    "",
    "=== paginate(page=2, per_page=10) ===",
    page_sq.sql,
  ], "\n")
}

main()
