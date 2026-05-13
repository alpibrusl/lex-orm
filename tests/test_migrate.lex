import "std.str"  as str
import "std.list" as list
import "std.int"  as int

import "lex-schema/schema"     as s
import "lex-schema/constraints" as c

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
      s.required_int("id",    []),
      s.required_str("title", []),
      s.required_str("body",  []),
      s.optional(s.required_str("slug", [])),
    ],
  }
}

# lex test convention: run_all :: () -> () — assert on failure.
fn run_all() -> () {
  # diff v1->v2 detects 2 AddColumn entries
  let ch_1_2 := m.diff(schema_v1(), schema_v2())
  let adds := list.fold(ch_1_2, 0, fn (acc :: Int, ch :: m.DdlChange) -> Int {
    match ch { AddColumn(_) => acc + 1, _ => acc }
  })
  assert adds == 2

  # diff v2->v1 detects 2 DropColumn entries
  let ch_2_1 := m.diff(schema_v2(), schema_v1())
  let drops := list.fold(ch_2_1, 0, fn (acc :: Int, ch :: m.DdlChange) -> Int {
    match ch { DropColumn(_) => acc + 1, _ => acc }
  })
  assert drops == 2

  # identical schemas produce empty diff
  let ch_same := m.diff(schema_v1(), schema_v1())
  assert list.len(ch_same) == 0

  # optional -> required triggers SetNotNull
  let old_s := { title: "Post", description: "",
    fields: [s.optional(s.required_str("body", []))] }
  let new_s := { title: "Post", description: "",
    fields: [s.required_str("body", [])] }
  let ch_nn := m.diff(old_s, new_s)
  let set_nns := list.fold(ch_nn, 0, fn (acc :: Int, ch :: m.DdlChange) -> Int {
    match ch { SetNotNull(_) => acc + 1, _ => acc }
  })
  assert set_nns == 1

  # to_alter_table emits ADD COLUMN
  let alter_add := m.to_alter_table("post", [AddColumn(s.required_str("body", []))], DbPostgres)
  assert str.contains(alter_add, "ADD COLUMN")

  # to_alter_table emits DROP COLUMN
  let alter_drop := m.to_alter_table("post", [DropColumn("old_field")], DbPostgres)
  assert str.contains(alter_drop, "DROP COLUMN")

  # plan_migrations returns only pending versions, sorted
  let versions := [
    { version: 1, schema: schema_v1() },
    { version: 2, schema: schema_v2() },
    { version: 3, schema: schema_v2() },
  ]
  let pending := m.plan_migrations(1, versions)
  assert list.len(pending) == 2
  let first_v := match list.head(pending) {
    Some(sv) => sv.version,
    None     => 0,
  }
  assert first_v == 2

  ()
}
