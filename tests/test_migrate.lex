import "std.str"  as str
import "std.list" as list
import "std.int"  as int

import "../vendor/lex-schema/src/schema"     as s
import "../vendor/lex-schema/src/constraints" as c

import "../src/migrate"    as m
import "../src/connection" as conn

fn schema_v1() -> s.ModelSchema {
  {
    title: "Post",
    description: "",
    fields: [
      s.required_int("id",    []),
      s.required_str("title", []),
    ],
  }
}

fn schema_v2() -> s.ModelSchema {
  {
    title: "Post",
    description: "",
    fields: [
      s.required_int("id",         []),
      s.required_str("title",      []),
      s.required_str("body",       []),
      s.optional(s.required_str("slug", [])),
    ],
  }
}

fn suite() -> List[Result[Str, Str]] {
  [
    test_diff_adds_two_columns(),
    test_diff_drops_two_columns(),
    test_diff_identical_empty(),
    test_diff_nullability_change(),
    test_alter_table_add_column(),
    test_alter_table_drop_column(),
    test_plan_migrations_pending(),
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

fn test_diff_adds_two_columns() -> Result[Str, Str] {
  let changes := m.diff(schema_v1(), schema_v2())
  let adds := list.fold(changes, 0, fn (acc :: Int, ch :: m.DdlChange) -> Int {
    match ch { AddColumn(_) => acc + 1, _ => acc }
  })
  assert_eq_int("diff_adds_two", adds, 2)
}

fn test_diff_drops_two_columns() -> Result[Str, Str] {
  let changes := m.diff(schema_v2(), schema_v1())
  let drops := list.fold(changes, 0, fn (acc :: Int, ch :: m.DdlChange) -> Int {
    match ch { DropColumn(_) => acc + 1, _ => acc }
  })
  assert_eq_int("diff_drops_two", drops, 2)
}

fn test_diff_identical_empty() -> Result[Str, Str] {
  let changes := m.diff(schema_v1(), schema_v1())
  assert_eq_int("diff_identical", list.len(changes), 0)
}

fn test_diff_nullability_change() -> Result[Str, Str] {
  let old_s := {
    title: "Post", description: "",
    fields: [s.optional(s.required_str("body", []))],
  }
  let new_s := {
    title: "Post", description: "",
    fields: [s.required_str("body", [])],
  }
  let changes := m.diff(old_s, new_s)
  let set_not_null_count := list.fold(changes, 0,
    fn (acc :: Int, ch :: m.DdlChange) -> Int {
      match ch { SetNotNull(_) => acc + 1, _ => acc }
    })
  assert_eq_int("diff_set_not_null", set_not_null_count, 1)
}

fn test_alter_table_add_column() -> Result[Str, Str] {
  let changes := [AddColumn(s.required_str("body", []))]
  let sql := m.to_alter_table("post", changes, DbPostgres)
  assert_contains("alter_add_col", sql, "ADD COLUMN")
}

fn test_alter_table_drop_column() -> Result[Str, Str] {
  let changes := [DropColumn("old_field")]
  let sql := m.to_alter_table("post", changes, DbPostgres)
  assert_contains("alter_drop_col", sql, "DROP COLUMN")
}

fn test_plan_migrations_pending() -> Result[Str, Str] {
  let versions := [
    { version: 1, schema: schema_v1() },
    { version: 2, schema: schema_v2() },
    { version: 3, schema: schema_v2() },
  ]
  let pending := m.plan_migrations(1, versions)
  assert_eq_int("plan_pending_count", list.len(pending), 2)
}
