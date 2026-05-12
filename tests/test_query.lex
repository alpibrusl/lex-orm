import "std.str"  as str
import "std.list" as list
import "std.int"  as int

import "../vendor/lex-schema/src/schema"     as s
import "../vendor/lex-schema/src/constraints" as c
import "../vendor/lex-schema/src/json_value"  as jv

import "../src/predicate" as p
import "../src/query"     as q

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

fn dummy_decode(j :: jv.Json) -> Result[jv.Json, s.Errors] { Ok(j) }

fn suite() -> List[Result[Str, Str]] {
  [
    test_select_basic(),
    test_select_where(),
    test_select_limit_offset(),
    test_select_order_by(),
    test_select_multi_where(),
    test_table_from_pascal_case(),
    test_build_insert_param_count(),
    test_build_update(),
    test_build_delete_no_where(),
    test_build_delete_with_where(),
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
    Err(str.concat(label, str.concat(" FAIL\ngot:  ",
      str.concat(got, str.concat("\nwant: ", want)))))
  }
}

fn assert_eq_int(label :: Str, got :: Int, want :: Int) -> Result[Str, Str] {
  if got == want { Ok(label) }
  else {
    Err(str.concat(label, str.concat(" FAIL: got=",
      str.concat(int.to_str(got), str.concat(" want=", int.to_str(want))))))
  }
}

fn assert_contains(label :: Str, haystack :: Str, needle :: Str) -> Result[Str, Str] {
  if str.contains(haystack, needle) { Ok(label) }
  else {
    Err(str.concat(label, str.concat(" FAIL: ",
      str.concat(needle, str.concat(" not found in: ", haystack)))))
  }
}

fn test_select_basic() -> Result[Str, Str] {
  let repo := q.for_schema(post_schema(), dummy_decode)
  let built := q.build_select(q.select(repo))
  assert_eq_str("select_basic", built.sql, "SELECT * FROM \"post\"")
}

fn test_select_where() -> Result[Str, Str] {
  let repo  := q.for_schema(post_schema(), dummy_decode)
  let query := q.where_clause(q.select(repo), p.eq("id", PInt(1)))
  let built := q.build_select(query)
  match assert_contains("select_where_sql", built.sql, "WHERE") {
    Err(e) => Err(e),
    Ok(_)  => assert_eq_int("select_where_params", list.len(built.params), 1),
  }
}

fn test_select_limit_offset() -> Result[Str, Str] {
  let repo  := q.for_schema(post_schema(), dummy_decode)
  let query := q.offset(q.limit(q.select(repo), 10), 20)
  let built := q.build_select(query)
  match assert_contains("limit_in_sql", built.sql, "LIMIT 10") {
    Err(e) => Err(e),
    Ok(_)  => assert_contains("offset_in_sql", built.sql, "OFFSET 20"),
  }
}

fn test_select_order_by() -> Result[Str, Str] {
  let repo  := q.for_schema(post_schema(), dummy_decode)
  let query := q.order_by(q.select(repo), "title", Asc)
  let built := q.build_select(query)
  assert_contains("order_by", built.sql, "ORDER BY \"title\" ASC")
}

fn test_select_multi_where() -> Result[Str, Str] {
  let repo  := q.for_schema(post_schema(), dummy_decode)
  let query :=
    q.where_clause(
      q.where_clause(q.select(repo), p.eq("id", PInt(5))),
      p.eq("slug", PStr("hello")))
  let built := q.build_select(query)
  match assert_contains("multi_where_and", built.sql, "AND") {
    Err(e) => Err(e),
    Ok(_)  => assert_eq_int("multi_where_params", list.len(built.params), 2),
  }
}

fn test_table_from_pascal_case() -> Result[Str, Str] {
  let repo := q.for_schema(blog_post_schema(), dummy_decode)
  assert_eq_str("pascal_to_snake", repo.table, "blog_post")
}

fn test_build_insert_param_count() -> Result[Str, Str] {
  let repo := q.for_schema(post_schema(), dummy_decode)
  let val  := JObj([
    ("id",    JInt(1)),
    ("title", JStr("Hello")),
    ("body",  JStr("World")),
  ])
  let built := q.build_insert(q.insert(repo, val))
  # post_schema has 4 fields, so 4 params
  assert_eq_int("insert_param_count", list.len(built.params), 4)
}

fn test_build_update() -> Result[Str, Str] {
  let repo  := q.for_schema(post_schema(), dummy_decode)
  let query :=
    q.where_update(
      q.set_col(q.update(repo), "title", PStr("New Title")),
      p.eq("id", PInt(7)))
  let built := q.build_update(query)
  match assert_contains("update_set", built.sql, "SET") {
    Err(e) => Err(e),
    Ok(_)  => assert_contains("update_where", built.sql, "WHERE"),
  }
}

fn test_build_delete_no_where() -> Result[Str, Str] {
  let repo  := q.for_schema(post_schema(), dummy_decode)
  let built := q.build_delete(q.delete_from(repo))
  assert_eq_str("delete_no_where", built.sql, "DELETE FROM \"post\"")
}

fn test_build_delete_with_where() -> Result[Str, Str] {
  let repo  := q.for_schema(post_schema(), dummy_decode)
  let query := q.where_delete(q.delete_from(repo), p.eq("id", PInt(3)))
  let built := q.build_delete(query)
  assert_contains("delete_with_where", built.sql, "WHERE")
}
