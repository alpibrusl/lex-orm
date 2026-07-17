# lex-orm

[![CI](https://github.com/alpibrusl/lex-orm/actions/workflows/ci.yml/badge.svg)](https://github.com/alpibrusl/lex-orm/actions/workflows/ci.yml)

**Part of the [Lex](https://lexlang.org) project** — Library · [Manifesto](https://lexlang.org/manifesto) · [All packages](https://lexlang.org)

A typed query builder, migration runner, and **live `std.sql` driver** for
[lex-lang](https://github.com/alpibrusl/lex-lang), built on top of
[lex-schema](https://github.com/alpibrusl/lex-schema).

Implements [lex-lang#357](https://github.com/alpibrusl/lex-lang/issues/357).
Requires **lex 0.9.1+** for record row spreads, `std.sql` Postgres support,
`Iter[T]`, and the `lex pkg install` resolver.

## What it does

- **Pure SQL builders.** `build_select`, `build_count`, `build_insert`,
  `build_update`, `build_delete`, `build_upsert`, `build_bulk_insert` return
  a `SqlQuery = { sql, params }` value with no effects. Fully testable
  without a database.
- **Predicate DSL.** Composable `PEq` / `PNeq` / `PGt` / `PGte` / `PLt` /
  `PLte` / `PIn` / `PIsNull` / `PIsNotNull` / `PAnd` / `POr` / `PNot`
  predicates. `?` placeholders during build; `for_dialect` rewrites them to
  `$1, $2, …` for Postgres at execution time.
- **Schema-driven DDL diffing.** `diff(old, new)` detects added /
  dropped columns and nullability changes; `to_alter_table` emits
  `ALTER TABLE` SQL for Postgres and SQLite.
- **Live SQL execution via `std.sql`.** `run_select`, `run_count`,
  `run_insert` (`INSERT … RETURNING`), `run_insert_returning`, `run_update`,
  `run_delete`, `run_upsert`, `run_bulk_insert`, and `transaction` all
  carry the `[sql]` effect and run against real `std.sql` handles. Rows
  flow through a `json_object` / `json_build_object` bridge so the same
  `decode :: (Json) -> Result[T, Errors]` works on both dialects.
- **Migration runner.** `apply` writes a single `SchemaVersion` and
  records it in `lex_schema_migrations`; `run_pending` plans + applies
  every unrecorded version in order; `rollback` / `rollback_pending`
  reverse them. `plan_migrations` returns the pending list sorted
  ascending (uses `list.sort_by` from lex 0.9).
- **Pagination.** `paginate(q, page, per_page)` composes with `select`;
  `Page[T]` and `page_result` package items + total + page metadata.

## Repository layout

```
lex.toml           package manifest (lex 0.9.1+)
src/
  error.lex        DbErr ADT + message/0
  connection.lex   Dialect (DbPostgres | DbSqlite), Db, Tx, open / connect_* / close
  predicate.lex    Param, Predicate ADT, render_where / render_pred
  query.lex        Repo[T], query builders, build_*, run_* (live), transaction, paginate
  migrate.lex      DdlChange, diff, to_alter_table, plan_migrations, apply, run_pending, rollback

tests/
  test_predicate.lex
  test_query.lex
  test_migrate.lex

examples/
  01_blog_posts.lex     SELECT / INSERT / UPDATE / DELETE query plans
  02_migrations.lex     Schema diffing and ALTER TABLE generation
  03_live_queries.lex   open → migrate → insert → select → transaction → close
                        round-trip on in-memory SQLite
  04_joins.lex          Type-safe JOIN results via lex 0.9.1 record row
                        spreads ({ ...Post, username :: Str })

vendor/             vendored lex-schema for environments that resolve the
                    dependency from disk; ignored when lex.toml resolves it
                    via path / git
```

## Installation

Add lex-orm and lex-schema as dependencies in your project's `lex.toml`:

```toml
[dependencies]
lex-orm    = { path = "../lex-orm" }
lex-schema = { path = "../lex-schema" }
```

Or via git:

```toml
[dependencies]
lex-orm    = { git = "https://github.com/alpibrusl/lex-orm" }
lex-schema = { git = "https://github.com/alpibrusl/lex-schema" }
```

Then import by package name:

```lex
import "lex-orm/connection" as conn
import "lex-orm/query"      as q
import "lex-orm/predicate"  as p
import "lex-orm/migrate"    as m
```

## Usage

### Building a Repo[T]

```lex
import "lex-orm/query"      as q
import "lex-schema/schema"  as s
import "lex-schema/json_value" as jv
import "lex-schema/error"   as se

type User = { id :: Int, name :: Str, age :: Int }

fn user_schema() -> s.ModelSchema {
  { title: "users", description: "",
    fields: [
      s.required_int("id",   []),
      s.required_str("name", [StrNonEmpty]),
      s.required_int("age",  [IntInRange(0, 130)]),
    ] }
}

fn decode_user(j :: jv.Json) -> Result[User, se.Errors] {
  match jv.j_int("", j, "id", []) {
    Err(e)  => Err(e),
    Ok(id)  =>
      match jv.j_str("", j, "name", []) {
        Err(e)   => Err(e),
        Ok(name) =>
          match jv.j_int("", j, "age", []) {
            Err(e)  => Err(e),
            Ok(age) => Ok({ id: id, name: name, age: age }),
          },
      },
  }
}

fn user_repo() -> q.Repo[User] {
  q.for_schema(user_schema(), decode_user)
}
```

### Pure query plans (no DB needed)

```lex
let plan :=
  q.build_select(
    q.limit(
      q.where_clause(q.select(user_repo()),
        p.eq("status", PStr("active"))),
      50))

# plan.sql    => SELECT * FROM "users" WHERE "status" = ? LIMIT 50
# plan.params => [PStr("active")]
```

### Live execution against std.sql

```lex
import "lex-orm/connection" as conn

fn list_active(db :: conn.Db) -> [sql] Result[List[User], dbe.DbErr] {
  q.run_select(
    q.where_clause(q.select(user_repo()),
      p.eq("status", PStr("active"))),
    db)
}

fn create(db :: conn.Db, name :: Str, age :: Int) -> [sql] Result[User, dbe.DbErr] {
  let body := jv.from_pairs([
    ("name", JStr(name)),
    ("age",  JInt(age)),
  ])
  q.run_insert(q.insert(user_repo(), body), db)
}

fn main() -> [sql, fs_write] Unit {
  match conn.open(":memory:") {
    Err(e)  => (),
    Ok(db) => {
      let _ := q.transaction(db, fn (tx :: conn.Db) -> [sql] Result[User, dbe.DbErr] {
        create(tx, "alice", 30)
      })
      let _ := conn.close(db)
      ()
    },
  }
}
```

### Pagination

```lex
let plan := q.paginate(q.select(user_repo()), 2, 20)
# Page 2, 20 per page → LIMIT 20 OFFSET 20
```

`q.run_select` returns a `List[T]`; combine with `q.run_count` and
`q.page_result` to populate a `Page[T]` envelope.

### Upsert

```lex
let q1 := q.upsert(user_repo(), payload, ["id"])
        |> fn (u :: q.UpsertQuery[User]) -> q.UpsertQuery[User] {
             q.on_conflict_update(u, "name", PStr("alice"))
           }
match q.run_upsert(q1, db) { ... }
```

### Migrations

```lex
import "lex-orm/migrate" as m

# Plan-only — pure
let changes := m.diff(schema_v1, schema_v2)
let sql_str := m.to_alter_table("posts", changes, DbPostgres)

# Apply — [sql]
let pending := m.plan_migrations(current_version, all_versions)
match m.run_pending(db, all_versions) { ... }

# Roll back the most-recent N versions
match m.rollback_pending(db, all_versions, 1) { ... }
```

`run_pending` and `rollback` write to a `lex_schema_migrations` book-keeping
table created by `migrations_table_ddl(dialect)`.

### Dialect variants

lex-orm uses `DbPostgres | DbSqlite` (not `DialectPostgres | DialectSqlite`)
to avoid constructor collision with lex-schema's `sdk.SqlDialect` type.

`for_dialect(plan, dialect)` rewrites `?` placeholders to `$1, $2, …` for
Postgres. The `run_*` functions call it internally; if you execute a
`SqlQuery` outside `run_*`, call it yourself before handing the SQL to
`std.sql.exec` / `query`.

## Pairing with lex-web

[lex-web](https://github.com/alpibrusl/lex-web) v0.2's
[`examples/with_lex_orm.lex`](https://github.com/alpibrusl/lex-web/blob/main/examples/with_lex_orm.lex)
shows a single `ModelSchema` driving:

- request validation (`body.require_json_body`)
- OpenAPI requestBody + per-route success status
- the lex-orm `Repo[Item]` for `SELECT` / `INSERT … RETURNING` / `WHERE id = ?`

The `[sql]` effect propagates from `q.run_*` through
`router.dispatch` → `net.serve_fn`.

## Running tests

```sh
lex test                            # runs all tests/test_*.lex via lex 0.9 runner
lex test tests/test_predicate.lex   # single file
```

All test files export `run_all() -> ()` and use `assert` per the lex 0.9
test convention.

## Running examples

```sh
lex run examples/01_blog_posts.lex
lex run examples/02_migrations.lex
lex run --allow-effects sql,fs_write examples/03_live_queries.lex main
lex run examples/04_joins.lex
```

## Design notes

- **Pure / effectful split.** All SQL *building* is pure (`build_*`,
  `for_dialect`, `paginate`, `page_result`). Execution (`run_*`, `apply`,
  `run_pending`, `rollback`, `transaction`) carries `[sql]`. Connection
  open / close additionally carries `[fs_write]` for SQLite path setup.
- **Generics.** `Repo[T]` is parameterised; the caller supplies
  `decode :: (Json) -> Result[T, Errors]`. lex-orm only serialises (via
  schema fields) and bridges the row through a single `_j :: Str` JSON
  column so one decoder works across both dialects.
- **`?` placeholders.** Uniform during build for both Postgres and SQLite;
  `for_dialect` rewrites them to `$1, $2, …` for Postgres. Called
  automatically by every `run_*`.
- **`list.sort_by`.** `plan_migrations` uses the key-extractor form added
  in lex 0.9 ([#338](https://github.com/alpibrusl/lex-lang/issues/338)).
- **Tuple destructuring.** lex-lang does not support
  `let (a, b) := tuple`; all pair unpacking uses
  `match pair { (a, b) => ... }`.
- **Record row spreads.** Examples 04 uses the lex 0.9.1 syntax
  `{ ...Post, username :: Str }` to express join-result types
  ([#363](https://github.com/alpibrusl/lex-lang/issues/363)).

---

Built under the principles of [Trust Without Comprehension](https://lexlang.org/manifesto).


## uuid columns on Postgres

Postgres will not bind a lex `PStr` to a `uuid` column, and `$1::uuid` does not
help — PG infers the *parameter* type through the cast, so serialization still
fails. The only working form pins the param to text and casts server-side:
`$1::text::uuid`.

You don't have to remember that:

- declare the field with the `StrUuid` check and `build_insert` marks it for you
- use `predicate.eq_uuid(col, v)` / `neq_uuid` in a WHERE clause
- or emit the portable marker `?::uuid` in raw SQL

`query.for_dialect` expands the marker to `?::text::uuid` on Postgres and strips
it on SQLite (which has neither `::` casts nor a uuid type).
