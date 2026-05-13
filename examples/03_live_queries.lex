# Example 03: real SQL queries against an in-memory SQLite database.
# Demonstrates open -> migrate -> insert -> select -> count -> transaction -> close.
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

fn decode_post(j :: jv.Json) -> Result[jv.Json, se.Errors] { Ok(j) }

fn versions() -> List[m.SchemaVersion] {
  [{ version: 1, schema: post_schema() }]
}

fn main() -> [sql, fs_write] Str {
  match conn.connect_sqlite(":memory:") {
    Err(e) => dbe.message(e),
    Ok(db) => {
      let repo := q.for_schema(post_schema(), decode_post)

      # Run migrations (creates the `post` table)
      match m.apply(db, 0, versions()) {
        Err(e) => dbe.message(e),
        Ok(_)  =>

          # Transaction: insert two posts atomically
          match q.transaction(db, fn (tx :: conn.Db) -> [sql] Result[Int, dbe.DbErr] {
            let p1 := JObj([
              ("id",    JInt(1)),
              ("title", JStr("Hello, lex-orm!")),
              ("body",  JStr("First post via real std.sql execution.")),
            ])
            let p2 := JObj([
              ("id",    JInt(2)),
              ("title", JStr("Paginated queries")),
              ("body",  JStr("Use q.paginate(sel, page, per_page) for cursor-free paging.")),
            ])
            match q.run_insert(q.insert(repo, p1), tx) {
              Err(e) => Err(e),
              Ok(_)  => match q.run_insert(q.insert(repo, p2), tx) {
                Err(e) => Err(e),
                Ok(_)  => Ok(2),
              },
            }
          }) {
            Err(e) => dbe.message(e),
            Ok(_)  =>

              # SELECT with WHERE + ORDER BY + LIMIT
              let sel :=
                q.limit(
                  q.order_by(
                    q.where_clause(q.select(repo), p.gt("id", PInt(0))),
                    "id", Desc
                  ),
                  10
                )
              match q.run_select(sel, db) {
                Err(e)   => dbe.message(e),
                Ok(rows) =>

                  # COUNT
                  match q.run_count(q.select(repo), db) {
                    Err(e) => dbe.message(e),
                    Ok(n)  => {
                      let _ := conn.close(db)
                      "found " + int.to_str(list.len(rows)) + " rows, total count = " + int.to_str(n)
                    },
                  }
              }
          }
      }
    },
  }
}

main()
