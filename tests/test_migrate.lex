import "std.str" as str

import "std.list" as list

import "lex-schema/schema" as s

import "../src/migrate" as m

import "../src/connection" as conn

fn schema_v1() -> s.ModelSchema {
  { title: "Post", description: "", fields: [s.required_int("id", []), s.required_str("title", [])] }
}

fn schema_v2() -> s.ModelSchema {
  { title: "Post", description: "", fields: [s.required_int("id", []), s.required_str("title", []), s.required_str("body", []), s.optional(s.required_str("slug", []))] }
}

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

# diff v1->v2 detects 2 AddColumn entries
fn diff_v1_to_v2_adds_two() -> Result[Unit, Str] {
  let ch := m.diff(schema_v1(), schema_v2())
  let adds := list.fold(ch, 0, fn (acc :: Int, c :: m.DdlChange) -> Int {
    match c {
      AddColumn(_) => acc + 1,
      _ => acc,
    }
  })
  check("v1->v2 add count", adds == 2)
}

# diff v2->v1 detects 2 DropColumn entries
fn diff_v2_to_v1_drops_two() -> Result[Unit, Str] {
  let ch := m.diff(schema_v2(), schema_v1())
  let drops := list.fold(ch, 0, fn (acc :: Int, c :: m.DdlChange) -> Int {
    match c {
      DropColumn(_) => acc + 1,
      _ => acc,
    }
  })
  check("v2->v1 drop count", drops == 2)
}

# identical schemas produce empty diff
fn diff_identical_is_empty() -> Result[Unit, Str] {
  let ch := m.diff(schema_v1(), schema_v1())
  check("identical empty", list.len(ch) == 0)
}

# optional -> required triggers SetNotNull
fn diff_optional_to_required_sets_not_null() -> Result[Unit, Str] {
  let old_s := { title: "Post", description: "", fields: [s.optional(s.required_str("body", []))] }
  let new_s := { title: "Post", description: "", fields: [s.required_str("body", [])] }
  let ch := m.diff(old_s, new_s)
  let set_nns := list.fold(ch, 0, fn (acc :: Int, c :: m.DdlChange) -> Int {
    match c {
      SetNotNull(_) => acc + 1,
      _ => acc,
    }
  })
  check("SetNotNull count", set_nns == 1)
}

fn alter_table_emits_add_column() -> Result[Unit, Str] {
  let alter := m.to_alter_table("post", [AddColumn(s.required_str("body", []))], DbPostgres)
  check("ADD COLUMN", str.contains(alter, "ADD COLUMN"))
}

fn alter_table_emits_drop_column() -> Result[Unit, Str] {
  let alter := m.to_alter_table("post", [DropColumn("old_field")], DbPostgres)
  check("DROP COLUMN", str.contains(alter, "DROP COLUMN"))
}

# plan_migrations returns only pending versions, sorted
fn plan_returns_pending_count() -> Result[Unit, Str] {
  let versions := [{ version: 1, schema: schema_v1() }, { version: 2, schema: schema_v2() }, { version: 3, schema: schema_v2() }]
  let pending := m.plan_migrations(1, versions)
  check("pending count", list.len(pending) == 2)
}

fn plan_first_pending_version() -> Result[Unit, Str] {
  let versions := [{ version: 1, schema: schema_v1() }, { version: 2, schema: schema_v2() }, { version: 3, schema: schema_v2() }]
  let pending := m.plan_migrations(1, versions)
  let first_v := match list.head(pending) {
    Some(sv) => sv.version,
    None => 0,
  }
  check("first pending = 2", first_v == 2)
}

fn suite() -> List[Result[Unit, Str]] {
  [diff_v1_to_v2_adds_two(), diff_v2_to_v1_drops_two(), diff_identical_is_empty(), diff_optional_to_required_sets_not_null(), alter_table_emits_add_column(), alter_table_emits_drop_column(), plan_returns_pending_count(), plan_first_pending_version()]
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

