import "std.str" as str

import "std.list" as list

import "lex-schema/schema" as s

import "lex-schema/json_value" as jv

import "lex-schema/error" as se

import "../src/predicate" as p

import "../src/query" as q

import "../src/connection" as conn

type Post = { id :: Int, title :: Str, body :: Str }

type BlogPost = { id :: Int, title :: Str }

fn post_schema() -> s.ModelSchema {
  { title: "Post", description: "A blog post", fields: [s.required_int("id", []), s.required_str("title", [StrMaxLen(200)]), s.required_str("body", []), s.optional(s.required_str("slug", []))] }
}

fn blog_post_schema() -> s.ModelSchema {
  { title: "BlogPost", description: "", fields: [s.required_int("id", []), s.required_str("title", [])] }
}

fn decode_post(j :: jv.Json) -> Result[Post, se.Errors] {
  match jv.j_int("", j, "id", []) {
    Err(e) => Err(e),
    Ok(id) => match jv.j_str("", j, "title", []) {
      Err(e) => Err(e),
      Ok(title) => match jv.j_str("", j, "body", []) {
        Err(e) => Err(e),
        Ok(body) => Ok({ id: id, title: title, body: body }),
      },
    },
  }
}

fn decode_blog_post(j :: jv.Json) -> Result[BlogPost, se.Errors] {
  match jv.j_int("", j, "id", []) {
    Err(e) => Err(e),
    Ok(id) => match jv.j_str("", j, "title", []) {
      Err(e) => Err(e),
      Ok(title) => Ok({ id: id, title: title }),
    },
  }
}

fn post_repo() -> q.Repo[Post] {
  q.for_schema(post_schema(), decode_post)
}

fn blog_post_repo() -> q.Repo[BlogPost] {
  q.for_schema(blog_post_schema(), decode_blog_post)
}

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn select_basic_sql() -> Result[Unit, Str] {
  let sel := q.build_select(q.select(post_repo()))
  check("select basic", sel.sql == "SELECT * FROM \"post\"")
}

fn select_where_keyword() -> Result[Unit, Str] {
  let sel := q.build_select(q.where_clause(q.select(post_repo()), p.eq("id", PInt(1))))
  check("select WHERE", str.contains(sel.sql, "WHERE"))
}

fn select_where_param_count() -> Result[Unit, Str] {
  let sel := q.build_select(q.where_clause(q.select(post_repo()), p.eq("id", PInt(1))))
  check("select WHERE params", list.len(sel.params) == 1)
}

fn select_limit_keyword() -> Result[Unit, Str] {
  let sel := q.build_select(q.offset(q.limit(q.select(post_repo()), 10), 20))
  check("select LIMIT", str.contains(sel.sql, "LIMIT 10"))
}

fn select_offset_keyword() -> Result[Unit, Str] {
  let sel := q.build_select(q.offset(q.limit(q.select(post_repo()), 10), 20))
  check("select OFFSET", str.contains(sel.sql, "OFFSET 20"))
}

fn select_order_by() -> Result[Unit, Str] {
  let sel := q.build_select(q.order_by(q.select(post_repo()), "title", Asc))
  check("ORDER BY", str.contains(sel.sql, "ORDER BY \"title\" ASC"))
}

fn pascal_to_snake_table() -> Result[Unit, Str] {
  let repo := blog_post_repo()
  check("snake_case table", repo.table == "blog_post")
}

fn insert_param_count_matches_fields() -> Result[Unit, Str] {
  let val := JObj([("id", JInt(1)), ("title", JStr("Hello")), ("body", JStr("World"))])
  let ins := q.build_insert(q.insert(post_repo(), val))
  check("insert param count", list.len(ins.params) == 4)
}

fn delete_no_where() -> Result[Unit, Str] {
  let del := q.build_delete(q.delete_from(post_repo()))
  check("delete plain", del.sql == "DELETE FROM \"post\"")
}

fn dialect_postgres_renumbers() -> Result[Unit, Str] {
  let sq := { sql: "UPDATE \"t\" SET \"a\" = ?, \"b\" = ? WHERE \"id\" = ?", params: [PStr("x"), PInt(2), PInt(3)] }
  let out := q.for_dialect(sq, DbPostgres)
  check("postgres $N", out.sql == "UPDATE \"t\" SET \"a\" = $1, \"b\" = $2 WHERE \"id\" = $3")
}

fn suite() -> List[Result[Unit, Str]] {
  [select_basic_sql(), select_where_keyword(), select_where_param_count(), select_limit_keyword(), select_offset_keyword(), select_order_by(), pascal_to_snake_table(), insert_param_count_matches_fields(), delete_no_where(), dialect_postgres_renumbers()]
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
