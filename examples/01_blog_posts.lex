# Example: building SQL query plans for a blog post schema.
# Run with: lex run examples/01_blog_posts.lex

import "std.str"  as str
import "std.list" as list
import "std.int"  as int

import "lex-schema/schema"     as s
import "lex-schema/constraints" as c
import "lex-schema/json_value"  as jv
import "lex-schema/error"       as se

import "../src/predicate" as p
import "../src/query"     as q

fn post_schema() -> s.ModelSchema {
  {
    title: "BlogPost",
    description: "A published blog post",
    fields: [
      s.required_int("id",           [c.IntPositive]),
      s.required_str("title",        [c.StrMaxLen(200), c.StrNonEmpty]),
      s.required_str("body",         []),
      s.required_str("author_id",    []),
      s.optional(s.required_str("slug",         [])),
      s.optional(s.required_str("published_at", [])),
    ],
  }
}

fn identity_decode(j :: jv.Json) -> Result[jv.Json, se.Errors] { Ok(j) }

fn main() -> Str {
  let repo := q.for_schema(post_schema(), identity_decode)

  # SELECT with WHERE + ORDER BY + LIMIT
  let select_plan :=
    q.build_select(
      q.limit(
        q.order_by(
          q.where_clause(
            q.select(repo),
            p.and_pred(
              p.eq("author_id", PStr("user_42")),
              p.is_not_null("published_at")
            )
          ),
          "published_at", Desc
        ),
        20
      )
    )

  # INSERT
  let insert_val := JObj([
    ("id",           JInt(0)),
    ("title",        JStr("Hello, lex-orm!")),
    ("body",         JStr("This is the body.")),
    ("author_id",    JStr("user_42")),
    ("slug",         JNull),
    ("published_at", JNull),
  ])
  let insert_plan := q.build_insert(q.insert(repo, insert_val))

  # UPDATE
  let update_plan :=
    q.build_update(
      q.where_update(
        q.set_col(
          q.set_col(q.update(repo), "title", PStr("Updated Title")),
          "slug", PStr("updated-title")
        ),
        p.eq("id", PInt(1))
      )
    )

  # DELETE
  let delete_plan :=
    q.build_delete(
      q.where_delete(q.delete_from(repo), p.eq("id", PInt(1)))
    )

  str.join([
    str.concat("-- table name: ", repo.table),
    "",
    str.concat("SELECT: ", select_plan.sql),
    str.concat("params: ", int.to_str(list.len(select_plan.params))),
    "",
    str.concat("INSERT: ", insert_plan.sql),
    str.concat("params: ", int.to_str(list.len(insert_plan.params))),
    "",
    str.concat("UPDATE: ", update_plan.sql),
    str.concat("params: ", int.to_str(list.len(update_plan.params))),
    "",
    str.concat("DELETE: ", delete_plan.sql),
    str.concat("params: ", int.to_str(list.len(delete_plan.params))),
  ], "\n")
}

main()
