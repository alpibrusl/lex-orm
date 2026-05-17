# Example 03: real SQL queries against an in-memory SQLite database.
# Run with: lex run --allow-sql --allow-fs-write examples/03_live_queries.lex

import "std.str"  as str
import "std.list" as list
import "std.int"  as int

import "lex-schema/schema"      as s
import "lex-schema/constraints" as c
import "lex-schema/json_value"  as jv
import "lex-schema/error"       as se

import "../src/connection" as conn
import "../src/migrate"    as m
import "../src/query"      as q
import "../src/predicate"  as p
import "../src/error"      as dbe

type Post = { id :: Int, title :: Str, body :: Str }

fn post_schema() -> s.ModelSchema {
  {
    title: "post",
    description: "Blog post",
    fields: [
      s.required_int("id",    [c.IntPositive]),
      s.required_str("title", [c.StrMaxLen(200)]),
      s.required_str("body",  []),
    ],
  }
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

fn versions() -> List[m.SchemaVersion] {
  [{ version: 1, schema: post_schema() }]
}

fn main() -> [sql, fs_write] Str {
  match conn.connect_sqlite(":memory:") {
    Err(e) => dbe.message(e),
    Ok(db) => {
      let repo := q.for_schema(post_schema(), decode_post)
      match m.apply(db, 0, versions()) {
        Err(e) => dbe.message(e),
        Ok(_)  => {
          let p1 := JObj([("id", JInt(1)), ("title", JStr("Hello")), ("body", JStr("World"))])
          match q.run_insert(q.insert(repo, p1), db) {
            Err(e) => dbe.message(e),
            Ok(_) => match q.run_count(q.select(repo), db) {
              Err(e) => dbe.message(e),
              Ok(n) => {
                let _ := conn.close(db)
                "total = " + int.to_str(n)
              },
            },
          }
        },
      }
    },
  }
}

main()
