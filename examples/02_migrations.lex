# Example: schema diffing and ALTER TABLE generation.
# Run with: lex run examples/02_migrations.lex

import "std.str"  as str
import "std.list" as list

import "../vendor/lex-schema/src/schema"     as s
import "../vendor/lex-schema/src/constraints" as c
import "../vendor/lex-schema/src/sdk"        as sdk

import "../src/migrate"    as m
import "../src/connection" as conn

fn v1() -> s.ModelSchema {
  {
    title: "Post",
    description: "Blog post v1",
    fields: [
      s.required_int("id",    [c.IntPositive]),
      s.required_str("title", [c.StrMaxLen(200)]),
    ],
  }
}

fn v2() -> s.ModelSchema {
  {
    title: "Post",
    description: "Blog post v2",
    fields: [
      s.required_int("id",         [c.IntPositive]),
      s.required_str("title",      [c.StrMaxLen(200)]),
      s.required_str("body",       []),
      s.optional(s.required_str("slug", [c.StrMaxLen(300)])),
    ],
  }
}

fn v3() -> s.ModelSchema {
  {
    title: "Post",
    description: "Blog post v3 — slug required",
    fields: [
      s.required_int("id",         [c.IntPositive]),
      s.required_str("title",      [c.StrMaxLen(200)]),
      s.required_str("body",       []),
      s.required_str("slug",       [c.StrMaxLen(300)]),
    ],
  }
}

fn main() -> Str {
  let changes_1_to_2 := m.diff(v1(), v2())
  let alter_pg := m.to_alter_table("post", changes_1_to_2, DbPostgres)
  let alter_sq := m.to_alter_table("post", changes_1_to_2, DbSqlite)

  let changes_2_to_3 := m.diff(v2(), v3())
  let alter_2_to_3 := m.to_alter_table("post", changes_2_to_3, DbPostgres)

  let versions := [
    { version: 1, schema: v1() },
    { version: 2, schema: v2() },
    { version: 3, schema: v3() },
  ]
  let pending := m.plan_migrations(1, versions)

  let create_pg := sdk.to_sql_ddl(v3(), DialectPostgres)
  let migrations_ddl := m.migrations_table_ddl(DbPostgres)

  str.join([
    "=== v1 -> v2: ALTER TABLE (Postgres) ===",
    alter_pg,
    "",
    "=== v1 -> v2: ALTER TABLE (SQLite) ===",
    alter_sq,
    "",
    "=== v2 -> v3: SET NOT NULL on slug ===",
    alter_2_to_3,
    "",
    str.concat("=== pending migrations from v1: ",
      str.from_int(list.len(pending))),
    "",
    "=== CREATE TABLE v3 (Postgres) ===",
    create_pg,
    "",
    "=== migrations tracking table ===",
    migrations_ddl,
  ], "\n")
}

main()
